/**
 * Entry point: wires the real dependencies together and starts the server.
 * The logic lives in ./lib, where every module takes its collaborators as
 * arguments.
 */

const fs = require('fs');
const path = require('path');

/** Pick up server/.env (ANTHROPIC_API_KEY etc.) when present. */
function loadEnvFile(file) {
  if (fs.existsSync(file) && typeof process.loadEnvFile === 'function') {
    process.loadEnvFile(file);
  }
}

function readFixture(name) {
  try {
    return JSON.parse(fs.readFileSync(path.join(__dirname, 'fixtures', name), 'utf8'));
  } catch (err) {
    console.error(`Error loading fixture ${name}:`, err.message);
    return [];
  }
}

/** Tests run against the bundled sample data so they stay offline and stable. */
function poiSource(env) {
  if (env.POI_PROVIDER) return env.POI_PROVIDER;
  return env.NODE_ENV === 'test' ? 'fixtures' : 'osm';
}

loadEnvFile(path.join(__dirname, '.env'));

const { createApp } = require('./lib/app');
const { createGuide } = require('./lib/guide');
const { createOverpassClient } = require('./lib/overpass');
const { createFixtureProvider, createOsmProvider } = require('./lib/providers');
const { createPoiSearch } = require('./lib/poi_search');
const { createRestSpotFinder } = require('./lib/rest_spots');
const { createStore } = require('./lib/store');
const { createDevRouter } = require('./lib/dev_routes');
const { transcriberFromEnv } = require('./lib/transcriber');

const guide = createGuide();
const source = poiSource(process.env);
const osm = createOsmProvider({ overpass: createOverpassClient() });
const fixtures = createFixtureProvider(readFixture('pois.json'));
// What the developer teaches the guide lives in server/data (not committed).
const store = createStore({ dir: process.env.DATA_DIR || path.join(__dirname, 'data') });

/**
 * Developer mode exists only on a server that has a DEV_TOKEN. Recordings are
 * transcribed when OPENAI_API_KEY is set; without it they are kept and wait.
 */
function devRouter(env) {
  if (!env.DEV_TOKEN) return null;
  return createDevRouter({
    store,
    guide,
    transcriber: transcriberFromEnv(env),
    token: env.DEV_TOKEN,
  });
}

const app = createApp({
  guide,
  knowledgeFor: store.knowledgeFor,
  isPhotoFile: store.isPhotoFile,
  mediaDir: store.filesDir,
  devRouter: devRouter(process.env),
  coffeeSpots: readFixture('coffee.json'),
  searchPois: createPoiSearch({ source, osm, fixtures, mapInterest: guide.mapInterest }),
  findRestSpots: createRestSpotFinder({ source, osm, fixtures }),
});

// Start server unless running inside a test harness
if (require.main === module) {
  const PORT = process.env.PORT || 1402;
  app.resumeDevWork();
  app.listen(PORT, () => {
    console.log(`POI server running on http://localhost:${PORT} (places from: ${source})`);
    console.log('Available endpoints:');
    console.log('  GET  /health');
    console.log('  GET  /pois?lat=&lon=&radiusM=&interests=&classics=&learned=');
    console.log('  GET  /coffee?lat=&lon=&radiusM=');
    console.log('  POST /guide/explain  - AI narration for a place');
    console.log('  POST /guide/photo    - AI story behind a photo');
    console.log('  GET  /rest-spots?lat=&lon= - a garden, cafe or viewpoint to sit at');
    console.log(`  Developer mode: ${process.env.DEV_TOKEN ? 'ON (/dev/*)' : 'off (no DEV_TOKEN)'}`);
    if (process.env.DEV_TOKEN) {
      console.log(`  Speech-to-text: ${process.env.OPENAI_API_KEY ? 'connected' : 'not connected (no OPENAI_API_KEY)'}`);
    }
  });
}

module.exports = app; // Export for testing
