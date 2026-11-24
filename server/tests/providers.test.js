const { createFixtureProvider, createOsmProvider } = require('../lib/providers');
const { SAMPLE_POIS } = require('./helpers/fakes');

describe('fixture provider', () => {
  const provider = createFixtureProvider(SAMPLE_POIS);

  it('returns everything within the radius when there is no filter', async () => {
    const places = await provider.search({ lat: 0, lon: 0, radius: 500, groups: null });
    expect(places.map((p) => p.id)).toEqual(['near_museum', 'near_park', 'near_thrift']);
  });

  it('applies each group within its own radius', async () => {
    const places = await provider.search({
      lat: 0,
      lon: 0,
      radius: 500,
      groups: [
        { category: 'park', radius: 500, selectors: [] },
        { id: 'for_you:museum', category: 'museum', radius: 5000, selectors: [] },
      ],
    });
    expect(places.map((p) => [p.id, p.matched])).toEqual([
      ['near_museum', ['for_you:museum']],
      ['near_park', ['park']],
      ['far_museum', ['for_you:museum']],
    ]);
  });

  it('matches free-text groups against the name', async () => {
    const groups = [{ category: 'vinyl', radius: 500, selectors: [{ key: 'name', nameRegex: 'vinyl' }] }];
    const places = await provider.search({ lat: 0, lon: 0, radius: 500, groups });
    expect(places.map((p) => p.id)).toEqual(['near_thrift']);
  });
});

describe('OSM provider', () => {
  const groups = [{ category: 'museum', radius: 1000, selectors: [{ key: 'tourism', value: 'museum' }] }];
  const element = { type: 'node', id: 7, lat: 0, lon: 0.001, tags: { name: 'City Museum', tourism: 'museum' } };

  function setup(now = () => 0) {
    const queries = [];
    const overpass = {
      query: async (q) => {
        queries.push(q);
        return { elements: [element, element] };
      },
    };
    return { queries, provider: createOsmProvider({ overpass, now }) };
  }

  it('converts and de-duplicates elements', async () => {
    const { provider } = setup();
    const places = await provider.search({ lat: 0, lon: 0, groups });
    expect(places).toHaveLength(1);
    expect(places[0]).toMatchObject({ id: 'osm_node_7', name: 'City Museum', matched: ['museum'] });
  });

  it('does not query when nothing is asked for', async () => {
    const { provider, queries } = setup();
    await expect(provider.search({ lat: 0, lon: 0, groups: [] })).resolves.toEqual([]);
    expect(queries).toHaveLength(0);
  });

  it('caches identical searches for ten minutes', async () => {
    let time = 0;
    const { provider, queries } = setup(() => time);
    await provider.search({ lat: 0, lon: 0, groups });
    time = 9 * 60 * 1000;
    await provider.search({ lat: 0, lon: 0, groups });
    expect(queries).toHaveLength(1);

    time = 11 * 60 * 1000;
    await provider.search({ lat: 0, lon: 0, groups });
    expect(queries).toHaveLength(2);
  });
});
