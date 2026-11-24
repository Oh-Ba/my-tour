const { buildOverpassQuery, createOverpassClient } = require('../lib/overpass');
const { fakeFetch } = require('./helpers/fakes');

const groups = [
  { category: 'second_hand', radius: 1500, selectors: [{ key: 'shop', regex: 'second_hand|charity' }] },
  { category: 'museum', radius: 4000, selectors: [{ key: 'tourism', value: 'museum' }] },
  { category: 'vinyl', radius: 1500, selectors: [{ key: 'name', nameRegex: 'vinyl' }] },
];

describe('buildOverpassQuery', () => {
  const query = buildOverpassQuery({ lat: 0, lon: 10, groups });
  // 1500 m and 4000 m around (0, 10); the near ring is 3000 m.
  const box1500 = '(-0.01347,9.98653,0.01347,10.01347)';
  const box4000 = '(-0.03593,9.96407,0.03593,10.03593)';
  const boxNear = '(-0.02695,9.97305,0.02695,10.02695)';

  it('searches each group within the box around its own radius', () => {
    expect(query).toContain(`nwr["name"]["shop"~"^(second_hand|charity)$"]${box1500};`);
    expect(query).toContain(`nwr["name"]["tourism"="museum"]${box4000};`);
  });

  it('searches place names case-insensitively for free-text groups', () => {
    expect(query).toContain(`nwr["name"~"vinyl",i]${box1500};`);
  });

  it('limits the output of every group separately', () => {
    expect(query).toContain('.g0 out center tags 60;');
    expect(query).toContain('.g2 out center tags 60;');
  });

  it('adds a near ring to wide groups so the closest places are never missed', () => {
    expect(query).toContain(`nwr["name"]["tourism"="museum"]${boxNear};`);
    expect(query).toContain('.n1 out center tags 60;');
    expect(query).not.toContain('.n0 out');
  });
});

describe('createOverpassClient', () => {
  const good = { elements: [{ type: 'node', id: 1 }] };

  it('returns the first mirror that answers', async () => {
    const fetch = fakeFetch({ 'https://a.test/api': 502, 'https://b.test/api': good });
    const client = createOverpassClient({ fetch, urls: ['https://a.test/api', 'https://b.test/api'] });

    await expect(client.query('Q')).resolves.toEqual(good);
    expect(fetch.calls[0].options.body).toBe('data=Q');
    expect(fetch.calls[0].options.method).toBe('POST');
  });

  it('treats an empty answer with a remark as a failure', async () => {
    const overloaded = { elements: [], remark: 'runtime error: timed out' };
    const fetch = fakeFetch({ 'https://a.test/api': overloaded, 'https://b.test/api': good });
    const client = createOverpassClient({ fetch, urls: ['https://a.test/api', 'https://b.test/api'] });

    await expect(client.query('Q')).resolves.toEqual(good);
  });

  it('accepts a genuinely empty result', async () => {
    const fetch = fakeFetch({ 'https://a.test/api': { elements: [] } });
    const client = createOverpassClient({ fetch, urls: ['https://a.test/api'] });

    await expect(client.query('Q')).resolves.toEqual({ elements: [] });
  });

  it('fails with every reason when no mirror answers', async () => {
    const fetch = fakeFetch({ 'https://a.test/api': 502, 'https://b.test/api': new Error('socket hang up') });
    const client = createOverpassClient({ fetch, urls: ['https://a.test/api', 'https://b.test/api'] });

    await expect(client.query('Q')).rejects.toThrow(/a\.test responded with HTTP 502.*socket hang up/);
  });
});
