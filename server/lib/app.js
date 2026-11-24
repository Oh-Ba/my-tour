/**
 * The HTTP API. All collaborators are injected, so the routes can be tested
 * without the network, the AI, or the file system.
 */

const path = require('path');
const express = require('express');
const cors = require('cors');
const { calculateDistance } = require('./geo');
const { GuideError } = require('./guide');

const MAX_LIST_ITEMS = 12;
const MAX_NARRATIONS = 500;
const DEFAULT_LANGUAGE = 'English';
const MAX_REQUEST_LENGTH = 500;

/** Split a comma-separated query value into trimmed, non-empty terms. */
function parseList(value) {
  if (!value) return [];
  return String(value)
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean)
    .slice(0, MAX_LIST_ITEMS);
}

/** Read lat/lon/radiusM; returns { error } or { lat, lon, radius }. */
function parseCoordinates(query, defaultRadius) {
  if (!query.lat || !query.lon) {
    return { error: 'Missing required parameters: lat and lon are required' };
  }
  const lat = parseFloat(query.lat);
  const lon = parseFloat(query.lon);
  const radius = query.radiusM ? parseFloat(query.radiusM) : defaultRadius;
  if (isNaN(lat) || isNaN(lon) || isNaN(radius)) {
    return { error: 'Invalid parameter format: lat, lon, and radiusM must be numbers' };
  }
  return { lat, lon, radius };
}

const isTrue = (value) => value === 'true' || value === '1';

/** Read a /pois query; returns { error } or { params }. */
function parsePoiQuery(query) {
  const coordinates = parseCoordinates(query, 1000);
  if (coordinates.error) return coordinates;
  return {
    params: {
      ...coordinates,
      interests: parseList(query.interests),
      classics: isTrue(query.classics),
      learned: parseList(query.learned),
    },
  };
}

const text = (value, max) => (typeof value === 'string' ? value.slice(0, max) : '');
const strings = (value, max) =>
  Array.isArray(value) ? value.slice(0, MAX_LIST_ITEMS).map((v) => String(v).slice(0, max)) : [];

/** Keep only the fields of a place the guide needs, bounded in size. */
function sanitizePlace(place) {
  return {
    name: text(place.name, 200),
    categories: strings(place.categories, 40),
    lat: Number(place.lat),
    lon: Number(place.lon),
    snippet: text(place.snippet, 500),
    wikipedia: text(place.wikipedia, 200),
  };
}

/** What identifies a place when looking up what is known about it. */
function placeIdentity(place) {
  return {
    id: text(place.id, 200),
    name: text(place.name, 200),
    lat: Number(place.lat),
    lon: Number(place.lon),
  };
}

function nearestSpots(spots, { lat, lon, radius }) {
  return spots
    .map((spot) => ({
      ...spot,
      distance: Math.round(calculateDistance(lat, lon, spot.lat, spot.lon)),
    }))
    .filter((spot) => spot.distance <= radius)
    .sort((a, b) => a.distance - b.distance)
    .slice(0, 20);
}

/**
 * @param {object} deps
 * @param {Function} deps.searchPois  async (params) -> { pois, source, extendedRadius }
 * @param {object} deps.guide         { explainPlace, explainPhoto }; both
 *        resolve to { text, minutes }
 * @param {Function} [deps.findRestSpots]  async ({ lat, lon, radius }) -> spots
 * @param {Function} [deps.knowledgeFor]  (place) -> { notes, photos, style, revision }:
 *        what the developer taught the guide about a place
 * @param {Function} [deps.isPhotoFile]   (name) -> whether a stored file may be served
 * @param {string} [deps.mediaDir]        folder holding the stored photos
 * @param {object} [deps.devRouter]       developer-mode routes; absent for a
 *        server without developer mode
 * @param {object[]} [deps.coffeeSpots]
 * @param {Map} [deps.narrations]     cache: narrations are the same for everyone
 * @param {Function} [deps.log]
 */
function createApp({
  searchPois,
  guide,
  coffeeSpots = [],
  findRestSpots = async () => [],
  knowledgeFor = null,
  isPhotoFile = () => false,
  mediaDir = '',
  devRouter = null,
  narrations = new Map(),
  log = console.error,
}) {
  const app = express();
  app.use(cors());
  // Photos arrive base64-encoded in the JSON body.
  app.use(express.json({ limit: '10mb' }));

  function sendGuideError(res, err) {
    if (err instanceof GuideError) return res.status(err.status).json({ error: err.message });
    log('Guide request failed:', err);
    return res.status(500).json({ error: 'The guide ran into an unexpected problem' });
  }

  function rememberNarration(key, narration) {
    if (narrations.size >= MAX_NARRATIONS) narrations.delete(narrations.keys().next().value);
    narrations.set(key, narration);
  }

  /**
   * GET /pois - places for the current tour
   *   lat, lon     user position (required)
   *   radiusM      tour radius in meters (default 1000)
   *   interests    comma-separated; known categories or free text such as
   *                "second hand stores"
   *   classics     "true" to also include tourist classics (museums, history,
   *                archaeology, landmarks)
   *   learned      comma-separated categories the app learned the user likes;
   *                matches are returned even beyond radiusM, flagged
   *                reason=for_you / outsideRadius=true
   */
  app.get('/pois', async (req, res) => {
    const { error, params } = parsePoiQuery(req.query);
    if (error) return res.status(400).json({ error });

    try {
      const result = await searchPois(params);
      return res.json({
        count: result.pois.length,
        radius: params.radius,
        extendedRadius: result.extendedRadius,
        source: result.source,
        pois: result.pois,
      });
    } catch (err) {
      log('POI search failed:', err);
      return res.status(500).json({ error: 'Failed to search for places' });
    }
  });

  /**
   * POST /guide/explain - AI narration about a place
   * Body: { place: { id, name, categories, lat, lon, snippet, wikipedia },
   *         language: "English", interests: ["museum"],
   *         request: "what the traveller typed or said, optional" }
   * Returns: { text, minutes, language }
   */
  app.post('/guide/explain', async (req, res) => {
    const { place, interests } = req.body || {};
    const language = (req.body || {}).language || DEFAULT_LANGUAGE;
    if (!place || !text(place.name, 200).trim()) {
      return res.status(400).json({ error: 'place.name is required' });
    }

    const asked = text((req.body || {}).request, MAX_REQUEST_LENGTH).trim();
    const known = knowledgeFor ? knowledgeFor(placeIdentity(place)) : null;
    // A story is rewritten once the developer has taught something new.
    const version = known ? `|v${known.revision}` : '';
    const key = `${place.id || place.name}|${language}|${asked.toLowerCase()}${version}`;
    if (narrations.has(key)) {
      return res.json({ ...narrations.get(key), language, cached: true });
    }

    try {
      const story = await guide.explainPlace(sanitizePlace(place), {
        language,
        interests: strings(interests, 60),
        request: asked,
        ...(known ? { lore: { notes: known.notes, style: known.style } } : {}),
      });
      const narration = { text: story.text, minutes: story.minutes };
      rememberNarration(key, narration);
      return res.json({ ...narration, language });
    } catch (err) {
      return sendGuideError(res, err);
    }
  });

  /**
   * POST /guide/photo - the story behind a photo the traveller took
   * Body: { image: "<base64>", mediaType: "image/jpeg", language: "English",
   *         lat, lon, placeName: "optional", nearby: ["Place A", "Place B"],
   *         request: "optional" }
   * Returns: { text, minutes, language }
   */
  app.post('/guide/photo', async (req, res) => {
    const body = req.body || {};
    const language = body.language || DEFAULT_LANGUAGE;
    if (!body.image) return res.status(400).json({ error: 'image (base64) is required' });

    try {
      const story = await guide.explainPhoto(
        { data: body.image, mediaType: body.mediaType || 'image/jpeg' },
        {
          language,
          lat: Number(body.lat),
          lon: Number(body.lon),
          placeName: text(body.placeName, 200),
          nearby: strings(body.nearby, 100),
          request: text(body.request, MAX_REQUEST_LENGTH).trim(),
        },
      );
      return res.json({ text: story.text, minutes: story.minutes, language });
    } catch (err) {
      return sendGuideError(res, err);
    }
  });

  /**
   * GET /rest-spots - a garden, cafe and viewpoint to sit at while listening
   *   lat, lon   where to look around (required)
   *   radiusM    how far the traveller should have to walk (default 400)
   */
  app.get('/rest-spots', async (req, res) => {
    const where = parseCoordinates(req.query, 400);
    if (where.error) return res.status(400).json({ error: where.error });
    return res.json({ spots: await findRestSpots(where) });
  });

  /**
   * GET /places/photos - photos the developer took of a place
   *   id, name, lat, lon   the place
   */
  app.get('/places/photos', (req, res) => {
    const place = placeIdentity({ ...req.query });
    const photos = knowledgeFor ? knowledgeFor(place).photos : [];
    res.json({ photos: photos.map(({ file, caption }) => ({ url: `/media/${file}`, caption })) });
  });

  /** GET /media/:file - one of those photos. Recordings are never served. */
  app.get('/media/:file', (req, res) => {
    if (!isPhotoFile(req.params.file)) return res.status(404).end();
    return res.sendFile(path.join(mediaDir, req.params.file));
  });

  if (devRouter) app.use('/dev', devRouter);
  /** Continue developer work a restart interrupted (transcribing, learning). */
  app.resumeDevWork = () => (devRouter ? devRouter.resumePending() : undefined);

  /** GET /coffee - coffee shops near a position (default radius 800 m) */
  app.get('/coffee', (req, res) => {
    const where = parseCoordinates(req.query, 800);
    if (where.error) return res.status(400).json({ error: where.error });

    const spots = nearestSpots(coffeeSpots, where);
    return res.json({ count: spots.length, radius: where.radius, spots });
  });

  app.get('/health', (req, res) => {
    res.json({ status: 'ok', timestamp: new Date().toISOString() });
  });

  return app;
}

module.exports = { createApp, parsePoiQuery, parseList };
