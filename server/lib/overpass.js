/**
 * Talks to the Overpass API, the query service for OpenStreetMap data.
 */

const { boundingBox } = require('./geo');

// Public Overpass servers are free but often overloaded, so a query is sent to
// several mirrors at once and the first good answer wins. Set OVERPASS_URL
// (comma-separated) to use your own instance instead.
const DEFAULT_URLS = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.openstreetmap.fr/api/interpreter',
  'https://overpass.private.coffee/api/interpreter',
];
const DEFAULT_TIMEOUT_MS = 40000;
const PER_GROUP_LIMIT = 60;
const NEAR_RADIUS = 3000;

/** The Overpass tag filter for one selector. Only named places are wanted. */
function selectorFilter(selector) {
  if (selector.nameRegex) return `["name"~"${selector.nameRegex}",i]`;
  if (selector.regex) return `["name"]["${selector.key}"~"^(${selector.regex})$"]`;
  return `["name"]["${selector.key}"="${selector.value}"]`;
}

/**
 * Overpass's own "within N metres" filter takes tens of seconds at larger
 * radii, while a bounding box is answered from an index. So the query asks
 * for the box and the exact distance is checked when places are built.
 */
function boxFilter(lat, lon, radius) {
  const { south, west, north, east } = boundingBox(lat, lon, radius);
  return `(${[south, west, north, east].map((n) => n.toFixed(5)).join(',')})`;
}

/** Everything matching any of the selectors inside the box, at most 60. */
function ringStatement(name, selectors, box) {
  const union = selectors.map((selector) => `nwr${selectorFilter(selector)}${box};`).join('');
  return `(${union})->.${name};.${name} out center tags ${PER_GROUP_LIMIT};`;
}

/**
 * One group. Overpass cannot sort by distance, so a wide group could fill its
 * 60 places with far-away ones; a second, near ring makes sure the closest
 * places are always included.
 */
function groupStatements(group, index, lat, lon) {
  const full = ringStatement(`g${index}`, group.selectors, boxFilter(lat, lon, group.radius));
  if (group.radius <= NEAR_RADIUS) return full;
  return full + ringStatement(`n${index}`, group.selectors, boxFilter(lat, lon, NEAR_RADIUS));
}

function buildOverpassQuery({ lat, lon, groups }) {
  const statements = groups.map((group, index) => groupStatements(group, index, lat, lon));
  return `[out:json][timeout:25];${statements.join('')}`;
}

/**
 * An overloaded server can answer 200 with a "remark" instead of results.
 * A remark alongside results means the query was cut short: partial results
 * are still worth showing.
 */
function isUsable(body) {
  return Array.isArray(body.elements) && !(body.remark && body.elements.length === 0);
}

async function queryMirror(fetch, url, query, signal) {
  const host = new URL(url).host;
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      'User-Agent': 'poi-server/1.0',
    },
    body: `data=${encodeURIComponent(query)}`,
    signal,
  });
  if (!response.ok) throw new Error(`${host} responded with HTTP ${response.status}`);

  const body = await response.json();
  if (!isUsable(body)) throw new Error(`${host}: ${body.remark || 'malformed response'}`);
  return body;
}

function describeFailures(error) {
  return (error.errors || [error]).map((e) => e.message).join('; ');
}

function urlsFromEnv(env = process.env) {
  if (!env.OVERPASS_URL) return DEFAULT_URLS;
  return env.OVERPASS_URL.split(',').map((url) => url.trim()).filter(Boolean);
}

/**
 * @param {object} deps
 * @param {Function} deps.fetch      fetch implementation
 * @param {string[]} deps.urls       mirrors to race
 * @param {number}   deps.timeoutMs  overall deadline
 */
function createOverpassClient({
  fetch = globalThis.fetch,
  urls = urlsFromEnv(),
  timeoutMs = DEFAULT_TIMEOUT_MS,
} = {}) {
  async function query(overpassQuery) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      return await Promise.any(
        urls.map((url) => queryMirror(fetch, url, overpassQuery, controller.signal)),
      );
    } catch (error) {
      throw new Error(`no Overpass server answered (${describeFailures(error)})`);
    } finally {
      clearTimeout(timer);
      controller.abort(); // stop the mirrors that lost the race
    }
  }

  return { query };
}

module.exports = { buildOverpassQuery, createOverpassClient, urlsFromEnv };
