const request = require('supertest');
const { createApp, parsePoiQuery, parseList } = require('../lib/app');
const { GuideError } = require('../lib/guide');

describe('parseList', () => {
  it('splits, trims and drops empty items', () => {
    expect(parseList(' museum, ,second hand stores ')).toEqual(['museum', 'second hand stores']);
    expect(parseList(undefined)).toEqual([]);
  });
});

describe('parsePoiQuery', () => {
  it('requires coordinates', () => {
    expect(parsePoiQuery({ lat: '1' }).error).toContain('required');
  });

  it('rejects non-numeric values', () => {
    expect(parsePoiQuery({ lat: 'a', lon: 'b' }).error).toContain('Invalid');
    expect(parsePoiQuery({ lat: '1', lon: '2', radiusM: 'x' }).error).toContain('Invalid');
  });

  it('applies defaults', () => {
    expect(parsePoiQuery({ lat: '1.5', lon: '2.5' }).params).toEqual({
      lat: 1.5, lon: 2.5, radius: 1000, interests: [], classics: false, learned: [],
    });
  });

  it('reads the tour options', () => {
    const { params } = parsePoiQuery({
      lat: '1', lon: '2', radiusM: '2500', interests: 'park,thrift shops', classics: 'true', learned: 'viewpoint',
    });
    expect(params).toMatchObject({
      radius: 2500, interests: ['park', 'thrift shops'], classics: true, learned: ['viewpoint'],
    });
  });
});

describe('routes', () => {
  function setup(guideOverrides = {}) {
    const calls = { search: [], explainPlace: [], explainPhoto: [], restSpots: [] };
    const app = createApp({
      searchPois: async (params) => {
        calls.search.push(params);
        return { pois: [{ id: 'a' }], source: 'osm', extendedRadius: 6000 };
      },
      guide: {
        explainPlace: async (...args) => {
          calls.explainPlace.push(args);
          return { text: 'A story.', minutes: 4, extended: false };
        },
        explainPhoto: async (...args) => {
          calls.explainPhoto.push(args);
          return { text: 'A photo story.', minutes: 2, extended: false };
        },
        ...guideOverrides,
      },
      coffeeSpots: [],
      findRestSpots: async (where) => {
        calls.restSpots.push(where);
        return [{ id: 'g', name: 'Garden', kind: 'garden', lat: 1, lon: 2, distance: 90 }];
      },
    });
    return { app, calls };
  }

  it('GET /pois passes the parsed query to the search', async () => {
    const { app, calls } = setup();
    const response = await request(app).get('/pois?lat=1&lon=2&classics=true&learned=viewpoint');

    expect(response.body).toEqual({
      count: 1, radius: 1000, extendedRadius: 6000, source: 'osm', pois: [{ id: 'a' }],
    });
    expect(calls.search[0]).toMatchObject({ classics: true, learned: ['viewpoint'] });
  });

  it('GET /pois answers 500 when the search throws', async () => {
    const app = createApp({
      searchPois: async () => {
        throw new Error('boom');
      },
      guide: {},
      log: () => {},
    });
    const response = await request(app).get('/pois?lat=1&lon=2');
    expect(response.status).toBe(500);
  });

  it('POST /guide/explain requires a place name', async () => {
    const { app } = setup();
    const response = await request(app).post('/guide/explain').send({ place: { name: ' ' } });
    expect(response.status).toBe(400);
  });

  it('POST /guide/explain narrates and then serves repeats from cache', async () => {
    const { app, calls } = setup();
    const body = { place: { id: 'p1', name: 'Coit Tower', lat: 1, lon: 2 }, language: 'French', interests: ['Art'] };

    const first = await request(app).post('/guide/explain').send(body);
    const second = await request(app).post('/guide/explain').send(body);
    const otherLanguage = await request(app).post('/guide/explain').send({ ...body, language: 'Hebrew' });

    expect(first.body).toEqual({ text: 'A story.', minutes: 4, language: 'French' });
    expect(second.body).toEqual({ text: 'A story.', minutes: 4, language: 'French', cached: true });
    expect(otherLanguage.body.cached).toBeUndefined();
    expect(calls.explainPlace).toHaveLength(2);
    expect(calls.explainPlace[0][1]).toEqual({ language: 'French', interests: ['Art'], request: '' });
  });

  it('POST /guide/explain treats a request from the traveller as a different story', async () => {
    const { app, calls } = setup();
    const body = { place: { id: 'p1', name: 'Coit Tower' }, language: 'French' };

    await request(app).post('/guide/explain').send(body);
    const asked = await request(app).post('/guide/explain').send({ ...body, request: 'More thorough please' });
    const askedAgain = await request(app).post('/guide/explain').send({ ...body, request: 'More thorough please' });

    expect(asked.body.cached).toBeUndefined();
    expect(askedAgain.body.cached).toBe(true);
    expect(calls.explainPlace[1][1].request).toBe('More thorough please');
  });

  it('POST /guide/explain surfaces guide errors with their status', async () => {
    const { app } = setup({
      explainPlace: async () => {
        throw new GuideError('AI guide is not configured', 503);
      },
    });
    const response = await request(app).post('/guide/explain').send({ place: { name: 'X' } });
    expect(response.status).toBe(503);
    expect(response.body.error).toBe('AI guide is not configured');
  });

  it('POST /guide/photo requires an image', async () => {
    const { app } = setup();
    const response = await request(app).post('/guide/photo').send({ language: 'English' });
    expect(response.status).toBe(400);
  });

  it('POST /guide/photo passes the photo and its context to the guide', async () => {
    const { app, calls } = setup();
    const response = await request(app).post('/guide/photo').send({
      image: 'aGVsbG8=', mediaType: 'image/png', language: 'Hebrew', lat: 1, lon: 2,
      placeName: 'Coit Tower', nearby: ['Lombard Street'],
    });

    expect(response.body).toEqual({ text: 'A photo story.', minutes: 2, language: 'Hebrew' });
    expect(calls.explainPhoto[0]).toEqual([
      { data: 'aGVsbG8=', mediaType: 'image/png' },
      { language: 'Hebrew', lat: 1, lon: 2, placeName: 'Coit Tower', nearby: ['Lombard Street'], request: '' },
    ]);
  });

  it('GET /rest-spots suggests places to sit near a position', async () => {
    const { app, calls } = setup();
    const response = await request(app).get('/rest-spots?lat=37.5&lon=15.08');

    expect(response.body).toEqual({
      spots: [{ id: 'g', name: 'Garden', kind: 'garden', lat: 1, lon: 2, distance: 90 }],
    });
    expect(calls.restSpots[0]).toEqual({ lat: 37.5, lon: 15.08, radius: 400 });
  });

  it('GET /rest-spots requires coordinates', async () => {
    const { app } = setup();
    const response = await request(app).get('/rest-spots?lat=37.5');
    expect(response.status).toBe(400);
  });

  it('GET /health reports ok', async () => {
    const { app } = setup();
    const response = await request(app).get('/health');
    expect(response.body.status).toBe('ok');
  });
});
