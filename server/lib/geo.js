/**
 * Distance between two coordinates using the Haversine formula.
 * @returns {number} Distance in meters
 */
function calculateDistance(lat1, lon1, lat2, lon2) {
  const R = 6371000; // Earth's radius in meters
  const φ1 = (lat1 * Math.PI) / 180;
  const φ2 = (lat2 * Math.PI) / 180;
  const Δφ = ((lat2 - lat1) * Math.PI) / 180;
  const Δλ = ((lon2 - lon1) * Math.PI) / 180;

  const a =
    Math.sin(Δφ / 2) * Math.sin(Δφ / 2) +
    Math.cos(φ1) * Math.cos(φ2) * Math.sin(Δλ / 2) * Math.sin(Δλ / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

  return R * c;
}

const METERS_PER_DEGREE = 111320;
const MAX_EXTENDED_RADIUS = 60000;

/**
 * How far beyond the user's radius "for you" recommendations may reach:
 * three times the radius and at least 5 km further out. Capped at 60 km,
 * where wider searches become too slow, but always 10 km past the radius.
 */
function extendedRadius(radiusM) {
  const cap = Math.max(MAX_EXTENDED_RADIUS, radiusM + 10000);
  return Math.min(Math.max(radiusM * 3, radiusM + 5000), cap);
}

/** The smallest latitude/longitude box containing a circle. */
function boundingBox(lat, lon, radiusM) {
  const dLat = radiusM / METERS_PER_DEGREE;
  const dLon = radiusM / (METERS_PER_DEGREE * Math.cos((lat * Math.PI) / 180));
  return { south: lat - dLat, west: lon - dLon, north: lat + dLat, east: lon + dLon };
}

module.exports = { calculateDistance, extendedRadius, boundingBox };
