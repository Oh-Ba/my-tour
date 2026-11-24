/**
 * Decides which places a traveller should see, and why:
 *
 *   interest  – matches something they asked for on this tour
 *   classic   – a tourist classic (museum, history, archaeology, landmark),
 *               added on every tour unless they opted out
 *   for_you   – matches what the app has learned they like; these may lie
 *               outside the tour radius
 */

const {
  CLASSIC_CATEGORIES,
  normalizeTerm,
  slugify,
  resolveLocally,
  nameSelector,
  groupFor,
} = require('./categories');
const { extendedRadius } = require('./geo');

const MAX_FOR_YOU = 10;
const MAX_CLASSICS = 30;
const FOR_YOU_PREFIX = 'for_you:';

const byDistance = (a, b) => a.distance - b.distance;
const notableFirst = (a, b) => Boolean(b.notable) - Boolean(a.notable) || byDistance(a, b);
const isForYouMatch = (id) => id.startsWith(FOR_YOU_PREFIX);

function uniqueByCategory(groups) {
  return [...new Map(groups.filter(Boolean).map((g) => [g.category, g])).values()];
}

function classicGroupsExcept(categories) {
  return CLASSIC_CATEGORIES.filter((category) => !categories.has(category)).map(groupFor);
}

/** Inner-ring groups search the tour radius; "for you" groups reach further. */
function withRadius(groups, radius) {
  return groups.map((group) => ({ ...group, radius }));
}

function asForYou(groups, radius) {
  return groups.map((group) => ({
    ...group,
    id: `${FOR_YOU_PREFIX}${group.category}`,
    radius,
  }));
}

/** A place belongs to the tour itself unless only "for you" groups found it. */
function isTourPlace(place, radius) {
  if (place.distance > radius) return false;
  return place.matched.length === 0 || !place.matched.every(isForYouMatch);
}

function reasonFor(place, interestKeys) {
  if (place.matched.length === 0) return 'interest';
  return place.matched.some((id) => interestKeys.has(id)) ? 'interest' : 'classic';
}

function toPoi(place, reason, radius) {
  const { matched, ...poi } = place;
  return { ...poi, reason, outsideRadius: place.distance > radius };
}

/**
 * The nearest "for you" places, half inside the radius and half beyond it, so
 * that suggestions outside the perimeter are never crowded out. Slots one side
 * cannot fill go to the other.
 */
function pickForYou(candidates, radius) {
  const sorted = [...candidates].sort(byDistance);
  const inside = sorted.filter((place) => place.distance <= radius);
  const outside = sorted.filter((place) => place.distance > radius);
  const half = MAX_FOR_YOU / 2;
  const insideCount = Math.min(inside.length, Math.max(half, MAX_FOR_YOU - outside.length));
  return [...inside.slice(0, insideCount), ...outside.slice(0, MAX_FOR_YOU - insideCount)];
}

/** A historic city has hundreds of classics; keep the ones most worth seeing. */
function topClassics(pois) {
  return pois.filter((poi) => poi.reason === 'classic').sort(notableFirst).slice(0, MAX_CLASSICS);
}

/** Split found places into the tour's own and the nearest "for you" extras. */
function labelPlaces(places, radius, interestKeys) {
  const labelled = places
    .filter((place) => isTourPlace(place, radius))
    .map((place) => toPoi(place, reasonFor(place, interestKeys), radius));
  const tour = [...labelled.filter((poi) => poi.reason !== 'classic'), ...topClassics(labelled)];
  const forYou = pickForYou(places.filter((place) => !isTourPlace(place, radius)), radius)
    .map((place) => toPoi(place, 'for_you', radius));
  return [...tour, ...forYou].sort(byDistance);
}

/**
 * @param {object} deps
 * @param {'osm'|'fixtures'} deps.source  which provider to ask first
 * @param {{search: Function}} deps.osm
 * @param {{search: Function}} deps.fixtures  also the fallback when OSM fails
 * @param {Function} [deps.mapInterest]  async (term) -> selectors | null; the
 *        AI translation of free-text interests
 * @param {Function} [deps.log]
 * @returns {Function} searchPois({ lat, lon, radius, interests, classics, learned })
 */
function createPoiSearch({ source, osm, fixtures, mapInterest, log = console.error }) {
  const translated = new Map();

  async function translate(term) {
    if (!mapInterest) return null;
    if (!translated.has(term)) {
      const selectors = await mapInterest(term);
      if (!selectors) return null; // not remembered, so it is retried later
      translated.set(term, selectors);
    }
    return translated.get(term);
  }

  /** Known categories resolve locally; other text is translated or name-searched. */
  async function resolveTerm(term) {
    const normalized = normalizeTerm(term);
    if (!normalized) return null;

    const known = resolveLocally(normalized);
    if (known) return groupFor(known);

    const selectors = (await translate(normalized)) || [nameSelector(normalized)];
    return { category: slugify(normalized), selectors };
  }

  async function resolveTerms(terms) {
    return uniqueByCategory(await Promise.all(terms.map(resolveTerm)));
  }

  async function findPlaces(request) {
    if (source === 'osm') {
      try {
        return { places: await osm.search(request), source };
      } catch (error) {
        log('OpenStreetMap search failed, using sample data:', error.message);
      }
    }
    return { places: await fixtures.search(request), source: 'fixtures' };
  }

  return async function searchPois({ lat, lon, radius, interests, classics, learned }) {
    const interestGroups = await resolveTerms(interests);
    const learnedGroups = await resolveTerms(learned);
    const interestKeys = new Set(interestGroups.map((group) => group.category));

    // OpenStreetMap has no sensible "everything", so a tour with nothing
    // selected shows the classics. Sample data keeps its unfiltered behaviour.
    const wantClassics = classics || (source === 'osm' && interestGroups.length === 0);
    const classicGroups = wantClassics ? classicGroupsExcept(interestKeys) : [];

    const outerRadius = learnedGroups.length ? extendedRadius(radius) : null;
    const groups = [
      ...withRadius([...interestGroups, ...classicGroups], radius),
      ...asForYou(learnedGroups, outerRadius),
    ];

    const found = await findPlaces({ lat, lon, radius, groups: groups.length ? groups : null });
    return {
      pois: labelPlaces(found.places, radius, interestKeys),
      source: found.source,
      extendedRadius: outerRadius,
    };
  };
}

module.exports = { createPoiSearch };
