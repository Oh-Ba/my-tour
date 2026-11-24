/**
 * POI providers. Each one answers the same question:
 *
 *   search({ lat, lon, radius, groups }) -> [{ id, name, lat, lon, snippet,
 *                                              categories, matched, distance }]
 *
 * `groups` is a list of { category, selectors, radius, id? }. Each group
 * searches within its own radius, so one request can cover both the tour
 * radius and the wider "for you" ring. A place is returned when it matches at
 * least one group; `matched` lists those groups' ids (`id`, or `category`).
 * `groups: null` means "everything within `radius`" (fixtures only).
 */

const { calculateDistance } = require('./geo');
const { buildOverpassQuery } = require('./overpass');
const { toPlace } = require('./places');

const CACHE_TTL_MS = 10 * 60 * 1000;
const CACHE_MAX = 200;

function fixtureMatches(poi, group) {
  if (poi.categories.includes(group.category)) return true;
  return group.selectors.some(
    (selector) => selector.nameRegex && new RegExp(selector.nameRegex, 'i').test(poi.name),
  );
}

function fixtureMatchedGroups(poi, groups, distance) {
  return groups
    .filter((group) => distance <= group.radius && fixtureMatches(poi, group))
    .map((group) => group.id || group.category);
}

/** Provider over a fixed list of POIs (the bundled sample data). */
function createFixtureProvider(pois) {
  async function search({ lat, lon, radius, groups }) {
    return pois
      .map((poi) => ({
        ...poi,
        distance: Math.round(calculateDistance(lat, lon, poi.lat, poi.lon)),
      }))
      .map((poi) => ({
        ...poi,
        matched: groups ? fixtureMatchedGroups(poi, groups, poi.distance) : [],
      }))
      .filter((poi) => (groups ? poi.matched.length > 0 : poi.distance <= radius));
  }

  return { search };
}

function uniqueById(places) {
  return [...new Map(places.map((place) => [place.id, place])).values()];
}

/** Remember `value` under `key`, evicting the oldest entry when full. */
function remember(cache, key, value) {
  if (cache.size >= CACHE_MAX) cache.delete(cache.keys().next().value);
  cache.set(key, value);
}

/**
 * Provider over OpenStreetMap: real places, worldwide, no API key.
 * @param {object} deps
 * @param {{query: Function}} deps.overpass  Overpass client
 * @param {Map} deps.cache                   query -> { time, places }
 * @param {Function} deps.now                clock, in milliseconds
 */
function createOsmProvider({ overpass, cache = new Map(), now = Date.now }) {
  async function search({ lat, lon, groups }) {
    if (!groups || groups.length === 0) return [];

    const query = buildOverpassQuery({ lat, lon, groups });
    const cached = cache.get(query);
    if (cached && now() - cached.time < CACHE_TTL_MS) return cached.places;

    const body = await overpass.query(query);
    const places = uniqueById(
      body.elements.map((element) => toPlace(element, groups, { lat, lon })).filter(Boolean),
    );
    remember(cache, query, { time: now(), places });
    return places;
  }

  return { search };
}

module.exports = { createFixtureProvider, createOsmProvider };
