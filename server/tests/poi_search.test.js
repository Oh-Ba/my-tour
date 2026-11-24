const { createPoiSearch } = require('../lib/poi_search');
const { createFixtureProvider } = require('../lib/providers');
const { SAMPLE_POIS } = require('./helpers/fakes');

const here = { lat: 0, lon: 0, radius: 500, interests: [], classics: false, learned: [] };
const ids = (result) => result.pois.map((poi) => poi.id);

function fixtureSearch(overrides = {}) {
  return createPoiSearch({
    source: 'fixtures',
    fixtures: createFixtureProvider(SAMPLE_POIS),
    ...overrides,
  });
}

describe('searchPois on sample data', () => {
  it('returns everything nearby when nothing is selected', async () => {
    const result = await fixtureSearch()(here);
    expect(ids(result)).toEqual(['near_museum', 'near_park', 'near_thrift']);
  });

  it('filters by interest', async () => {
    const result = await fixtureSearch()({ ...here, interests: ['Parks'] });
    expect(result.pois).toMatchObject([{ id: 'near_park', reason: 'interest', outsideRadius: false }]);
  });

  it('adds tourist classics on top of the interests', async () => {
    const result = await fixtureSearch()({ ...here, interests: ['Parks'], classics: true });
    expect(result.pois.map((p) => [p.id, p.reason])).toEqual([
      ['near_museum', 'classic'],
      ['near_park', 'interest'],
    ]);
  });

  it('labels a classic the traveller asked for as their interest', async () => {
    const result = await fixtureSearch()({ ...here, interests: ['Museums'], classics: true });
    expect(result.pois).toMatchObject([{ id: 'near_museum', reason: 'interest' }]);
  });

  it('recommends learned categories beyond the radius, up to the extended radius', async () => {
    const result = await fixtureSearch()({ ...here, interests: ['Parks'], learned: ['viewpoint'] });
    expect(result.extendedRadius).toBe(5500);
    expect(result.pois).toMatchObject([
      { id: 'near_park', reason: 'interest', outsideRadius: false },
      { id: 'far_viewpoint', reason: 'for_you', outsideRadius: true },
    ]);
  });

  it('never leaves the radius without learned categories', async () => {
    const result = await fixtureSearch()({ ...here, classics: true });
    expect(result.extendedRadius).toBeNull();
    result.pois.forEach((poi) => expect(poi.outsideRadius).toBe(false));
  });

  it('sorts by distance and never repeats a place', async () => {
    const result = await fixtureSearch()({ ...here, interests: ['Museums'], learned: ['museum'] });
    expect(ids(result)).toEqual(['near_museum', 'far_museum']);
    expect(result.pois[0].reason).toBe('interest');
    expect(result.pois[1].reason).toBe('for_you');
  });
});

describe('searchPois on OpenStreetMap', () => {
  function osmSearch({ places = [], mapInterest, fail = false } = {}) {
    const requests = [];
    const osm = {
      search: async (request) => {
        requests.push(request);
        if (fail) throw new Error('no Overpass server answered');
        return places;
      },
    };
    const searchPois = createPoiSearch({
      source: 'osm',
      osm,
      fixtures: createFixtureProvider(SAMPLE_POIS),
      mapInterest,
      log: () => {},
    });
    return { searchPois, requests };
  }

  const categoriesOf = (request) => request.groups.map((g) => g.id || g.category);

  it('shows the classics when nothing is selected', async () => {
    const { searchPois, requests } = osmSearch();
    await searchPois(here);
    expect(categoriesOf(requests[0])).toEqual(['museum', 'historical', 'archaeology', 'landmark']);
  });

  it('asks for interests, classics and learned categories in one request', async () => {
    const { searchPois, requests } = osmSearch();
    await searchPois({ ...here, interests: ['second hand stores'], classics: true, learned: ['viewpoint'] });

    expect(requests).toHaveLength(1);
    expect(categoriesOf(requests[0])).toEqual([
      'second_hand', 'museum', 'historical', 'archaeology', 'landmark', 'for_you:viewpoint',
    ]);
    expect(requests[0].groups.map((g) => g.radius)).toEqual([500, 500, 500, 500, 500, 5500]);
  });

  it('translates unknown interests with the AI and remembers the answer', async () => {
    const asked = [];
    const mapInterest = async (term) => {
      asked.push(term);
      return [{ key: 'shop', value: 'games' }];
    };
    const { searchPois, requests } = osmSearch({ mapInterest });

    await searchPois({ ...here, interests: ['Board Games'] });
    await searchPois({ ...here, interests: ['board games'] });

    expect(asked).toEqual(['board games']);
    expect(requests[0].groups[0]).toMatchObject({
      category: 'board_games',
      selectors: [{ key: 'shop', value: 'games' }],
    });
  });

  it('falls back to a name search when the AI has no answer', async () => {
    const { searchPois, requests } = osmSearch({ mapInterest: async () => null });
    await searchPois({ ...here, interests: ['board games'] });
    expect(requests[0].groups[0].selectors).toEqual([{ key: 'name', nameRegex: 'board games' }]);
  });

  it('falls back to sample data when OpenStreetMap is unreachable', async () => {
    const { searchPois } = osmSearch({ fail: true });
    const result = await searchPois({ ...here, interests: ['Parks'] });
    expect(result.source).toBe('fixtures');
    expect(ids(result)).toEqual(['near_park']);
  });

  it('keeps at most thirty classics, the notable ones first', async () => {
    const places = Array.from({ length: 40 }, (_, i) => ({
      id: `c${i}`, name: `C${i}`, categories: ['historical'], lat: 0, lon: 0,
      snippet: '', matched: ['historical'], distance: 10 + i, notable: i >= 35,
    }));
    places.push({
      id: 'shop', name: 'Shop', categories: ['second_hand'], lat: 0, lon: 0,
      snippet: '', matched: ['second_hand'], distance: 400, notable: false,
    });
    const { searchPois } = osmSearch({ places });
    const result = await searchPois({ ...here, interests: ['thrift'], classics: true });

    const classics = result.pois.filter((poi) => poi.reason === 'classic').map((poi) => poi.id);
    expect(classics).toHaveLength(30);
    expect(classics).toEqual(expect.arrayContaining(['c35', 'c36', 'c37', 'c38', 'c39', 'c0', 'c24']));
    expect(classics).not.toContain('c25');
    expect(ids(result)).toContain('shop');
  });

  it('reserves half of the "for you" places for beyond the radius', async () => {
    const forYou = (id, distance) => ({
      id, name: id, categories: ['viewpoint'], lat: 0, lon: 0,
      snippet: '', matched: ['for_you:viewpoint'], distance,
    });
    const places = [
      ...Array.from({ length: 8 }, (_, i) => forYou(`in${i}`, 100 + i)),
      ...Array.from({ length: 8 }, (_, i) => forYou(`out${i}`, 2000 + i)),
    ];
    const { searchPois } = osmSearch({ places });
    const result = await searchPois({ ...here, interests: ['Parks'], learned: ['viewpoint'] });

    expect(ids(result)).toEqual([
      'in0', 'in1', 'in2', 'in3', 'in4', 'out0', 'out1', 'out2', 'out3', 'out4',
    ]);
  });

  it('fills unused "for you" places from the other side of the radius', async () => {
    const forYou = (id, distance) => ({
      id, name: id, categories: ['viewpoint'], lat: 0, lon: 0,
      snippet: '', matched: ['for_you:viewpoint'], distance,
    });
    const places = [forYou('in0', 100), ...Array.from({ length: 12 }, (_, i) => forYou(`out${i}`, 2000 + i))];
    const { searchPois } = osmSearch({ places });
    const result = await searchPois({ ...here, interests: ['Parks'], learned: ['viewpoint'] });

    expect(result.pois).toHaveLength(10);
    expect(ids(result).slice(0, 2)).toEqual(['in0', 'out0']);
    expect(ids(result)[9]).toBe('out8');
  });

  it('keeps at most ten "for you" places, nearest first', async () => {
    const places = Array.from({ length: 15 }, (_, i) => ({
      id: `p${i}`, name: `P${i}`, categories: ['viewpoint'], lat: 0, lon: 0,
      snippet: '', matched: ['for_you:viewpoint'], distance: 1000 + (15 - i),
    }));
    const { searchPois } = osmSearch({ places });
    const result = await searchPois({ ...here, interests: ['Parks'], learned: ['viewpoint'] });

    expect(result.pois).toHaveLength(10);
    expect(result.pois[0].id).toBe('p14');
    expect(result.pois[0]).not.toHaveProperty('matched');
  });
});
