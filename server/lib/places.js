/**
 * Turns raw OpenStreetMap elements into the places the app shows.
 */

const { CATEGORIES } = require('./categories');
const { calculateDistance } = require('./geo');

/** Does a set of OSM tags satisfy one selector? */
function tagsMatch(tags, selector) {
  if (selector.nameRegex) return new RegExp(selector.nameRegex, 'i').test(tags.name || '');
  const value = tags[selector.key];
  if (value === undefined) return false;
  if (selector.regex) return new RegExp(`^(${selector.regex})$`).test(value);
  return value === selector.value;
}

function matchesAny(tags, selectors) {
  return selectors.some((selector) => tagsMatch(tags, selector));
}

function addressOf(tags) {
  const street = [tags['addr:street'], tags['addr:housenumber']].filter(Boolean).join(' ');
  return [street, tags['addr:city']].filter(Boolean).join(', ');
}

/**
 * A one-line description: the English one, or "Kind · address". Untranslated
 * descriptions are skipped; they are often practical notes for locals.
 */
function describePlace(tags, categories) {
  if (tags['description:en']) return tags['description:en'];
  const kind = categories.map((key) => CATEGORIES[key]?.label).find(Boolean) || 'Place';
  const address = addressOf(tags);
  return address ? `${kind} · ${address}` : kind;
}

/**
 * The place's own website, as an http(s) address, or undefined. Mappers write
 * these by hand, so a missing scheme and several addresses in one tag are
 * tolerated, and anything that is not a web address is dropped.
 */
function websiteOf(tags) {
  const raw = tags.website || tags['contact:website'] || tags.url;
  if (!raw) return undefined;
  const first = raw.split(';')[0].trim();
  const address = /^[a-z][a-z0-9+.-]*:/i.test(first) ? first : `https://${first}`;
  return /^https?:\/\/[^\s/]+\.[^\s]+$/i.test(address) ? address : undefined;
}

/** Elements are nodes (own coordinates) or ways/relations (a centre). */
function positionOf(element) {
  const lat = element.lat ?? element.center?.lat;
  const lon = element.lon ?? element.center?.lon;
  return lat === undefined || lon === undefined ? null : { lat, lon };
}

/**
 * Every category the place belongs to: the requested ones first, then all
 * canonical ones, so that what the traveller engages with can be learned from.
 */
function categoriesOf(tags, groups) {
  const requested = groups
    .filter((group) => matchesAny(tags, group.selectors))
    .map((group) => group.category);
  const canonical = Object.keys(CATEGORIES).filter((key) =>
    matchesAny(tags, CATEGORIES[key].selectors),
  );
  return [...new Set([...requested, ...canonical])];
}

/** Ids of the groups the place satisfies within each group's own radius. */
function matchedGroups(tags, groups, distance) {
  return groups
    .filter((group) => distance <= group.radius && matchesAny(tags, group.selectors))
    .map((group) => group.id || group.category);
}

/**
 * @returns the place, or null when the element is unnamed, has no position,
 *          or matches none of the groups.
 */
function toPlace(element, groups, origin) {
  const tags = element.tags || {};
  const position = positionOf(element);
  if (!tags.name || !position) return null;

  // Overpass measures to the nearest point of a shape; measure to its centre.
  const distance = Math.round(
    calculateDistance(origin.lat, origin.lon, position.lat, position.lon),
  );
  const matched = matchedGroups(tags, groups, distance);
  if (matched.length === 0) return null;

  const categories = categoriesOf(tags, groups);
  const place = {
    id: `osm_${element.type}_${element.id}`,
    name: tags['name:en'] || tags.name,
    categories,
    ...position,
    snippet: describePlace(tags, categories),
    matched,
    distance,
    // Having an encyclopedia entry is a good sign a place is worth a detour.
    notable: Boolean(tags.wikipedia || tags.wikidata),
  };
  if (tags['name:en'] && tags['name:en'] !== tags.name) place.localName = tags.name;
  if (tags.wikipedia) place.wikipedia = tags.wikipedia;
  const website = websiteOf(tags);
  if (website) place.website = website;
  return place;
}

module.exports = { toPlace, tagsMatch, describePlace, websiteOf };
