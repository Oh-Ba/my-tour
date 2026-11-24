/**
 * Finds a pleasant place to sit and listen: the nearest garden, cafe and
 * viewpoint around a position.
 */

const { groupFor } = require('./categories');

/** What to look for, and what the app calls each kind. */
const KINDS = { park: 'garden', cafe: 'cafe', viewpoint: 'viewpoint' };
const REST_GROUPS = Object.keys(KINDS);

const byDistance = (a, b) => a.distance - b.distance;

function toSpot(place, category) {
  return {
    id: place.id,
    name: place.name,
    kind: KINDS[category],
    lat: place.lat,
    lon: place.lon,
    distance: place.distance,
  };
}

/** The nearest place of one kind, or undefined. */
function nearestOf(places, category) {
  return places.filter((place) => place.matched.includes(category)).sort(byDistance)[0];
}

/** One spot of each kind that exists nearby, closest first. */
function pickSpots(places) {
  const spots = new Map();
  for (const category of REST_GROUPS) {
    const place = nearestOf(places, category);
    if (place && !spots.has(place.id)) spots.set(place.id, toSpot(place, category));
  }
  return [...spots.values()].sort(byDistance);
}

/**
 * @param {object} deps
 * @param {'osm'|'fixtures'} deps.source
 * @param {{search: Function}} [deps.osm]
 * @param {{search: Function}} deps.fixtures
 * @param {Function} [deps.log]
 * @returns {Function} findRestSpots({ lat, lon, radius })
 */
function createRestSpotFinder({ source, osm, fixtures, log = console.error }) {
  const provider = source === 'osm' ? osm : fixtures;

  return async function findRestSpots({ lat, lon, radius }) {
    const groups = REST_GROUPS.map((category) => ({ ...groupFor(category), radius }));
    try {
      return pickSpots(await provider.search({ lat, lon, radius, groups }));
    } catch (error) {
      // A seat is a nicety: the story is told on the spot instead.
      log('Could not look for places to sit:', error.message);
      return [];
    }
  };
}

module.exports = { createRestSpotFinder, pickSpots, REST_GROUPS };
