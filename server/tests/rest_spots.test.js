const { createRestSpotFinder, pickSpots, REST_GROUPS } = require('../lib/rest_spots');
const { createFixtureProvider } = require('../lib/providers');

const place = (id, matched, distance) => ({
  id, name: id, lat: 1, lon: 2, categories: [], snippet: '', matched, distance,
});

describe('pickSpots', () => {
  it('offers the nearest garden, cafe and viewpoint, closest first', () => {
    const spots = pickSpots([
      place('far_cafe', ['cafe'], 300),
      place('garden', ['park'], 250),
      place('near_cafe', ['cafe'], 80),
      place('lookout', ['viewpoint'], 150),
    ]);
    expect(spots).toEqual([
      { id: 'near_cafe', name: 'near_cafe', kind: 'cafe', lat: 1, lon: 2, distance: 80 },
      { id: 'lookout', name: 'lookout', kind: 'viewpoint', lat: 1, lon: 2, distance: 150 },
      { id: 'garden', name: 'garden', kind: 'garden', lat: 1, lon: 2, distance: 250 },
    ]);
  });

  it('offers what there is', () => {
    expect(pickSpots([place('garden', ['park'], 90)]).map((s) => s.kind)).toEqual(['garden']);
    expect(pickSpots([])).toEqual([]);
  });
});

describe('createRestSpotFinder', () => {
  const fixtures = createFixtureProvider([
    { id: 'g', name: 'Garden', categories: ['park'], lat: 0, lon: 0.001, snippet: '' },
    { id: 'c', name: 'Cafe', categories: ['cafe'], lat: 0, lon: 0.002, snippet: '' },
    { id: 'm', name: 'Museum', categories: ['museum'], lat: 0, lon: 0.001, snippet: '' },
    { id: 'far', name: 'Far Garden', categories: ['park'], lat: 0, lon: 0.02, snippet: '' },
  ]);

  it('looks for gardens, cafes and viewpoints within the radius', async () => {
    const requests = [];
    const osm = {
      search: async (request) => {
        requests.push(request);
        return [place('near_cafe', ['cafe'], 80)];
      },
    };
    const find = createRestSpotFinder({ source: 'osm', osm, fixtures });

    const spots = await find({ lat: 37.5, lon: 15.08, radius: 400 });

    expect(spots.map((s) => s.id)).toEqual(['near_cafe']);
    expect(requests[0].groups.map((g) => [g.category, g.radius])).toEqual([
      ['park', 400], ['cafe', 400], ['viewpoint', 400],
    ]);
    expect(REST_GROUPS).toEqual(['park', 'cafe', 'viewpoint']);
  });

  it('uses the sample data when asked to', async () => {
    const find = createRestSpotFinder({ source: 'fixtures', fixtures });
    const spots = await find({ lat: 0, lon: 0, radius: 400 });
    expect(spots.map((s) => [s.id, s.kind])).toEqual([['g', 'garden'], ['c', 'cafe']]);
  });

  it('suggests nothing, rather than failing, when the search is down', async () => {
    const osm = {
      search: async () => {
        throw new Error('no Overpass server answered');
      },
    };
    const find = createRestSpotFinder({ source: 'osm', osm, fixtures, log: () => {} });
    await expect(find({ lat: 0, lon: 0, radius: 400 })).resolves.toEqual([]);
  });
});
