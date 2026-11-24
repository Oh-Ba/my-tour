const { toPlace, tagsMatch, describePlace, websiteOf } = require('../lib/places');

const groups = [
  { category: 'second_hand', radius: 2000, selectors: [{ key: 'shop', regex: 'second_hand|charity' }] },
  { category: 'museum', radius: 2000, selectors: [{ key: 'tourism', value: 'museum' }] },
  { id: 'for_you:museum', category: 'museum', radius: 9000, selectors: [{ key: 'tourism', value: 'museum' }] },
];
const origin = { lat: 48.85, lon: 2.35 };

describe('tagsMatch', () => {
  it('matches exact values, anchored regexes and names', () => {
    expect(tagsMatch({ tourism: 'museum' }, { key: 'tourism', value: 'museum' })).toBe(true);
    expect(tagsMatch({ shop: 'charity' }, { key: 'shop', regex: 'second_hand|charity' })).toBe(true);
    expect(tagsMatch({ shop: 'charity_extra' }, { key: 'shop', regex: 'second_hand|charity' })).toBe(false);
    expect(tagsMatch({ name: 'Big VINYL Shop' }, { key: 'name', nameRegex: 'vinyl' })).toBe(true);
    expect(tagsMatch({}, { key: 'tourism', value: 'museum' })).toBe(false);
  });
});

describe('describePlace', () => {
  it('prefers the English description', () => {
    expect(describePlace({ 'description:en': 'Oldest shop in town' }, ['books'])).toBe('Oldest shop in town');
  });

  it('ignores untranslated descriptions, which are often notes for locals', () => {
    expect(describePlace({ description: 'Il biglietto è nominativo.' }, ['museum'])).toBe('Museum');
  });

  it('falls back to the kind of place and its address', () => {
    const tags = { 'addr:street': 'Rue de Rivoli', 'addr:housenumber': '99', 'addr:city': 'Paris' };
    expect(describePlace(tags, ['museum'])).toBe('Museum · Rue de Rivoli 99, Paris');
    expect(describePlace({}, ['vinyl'])).toBe('Place');
  });
});

describe('websiteOf', () => {
  it('reads the website from the usual tags', () => {
    expect(websiteOf({ website: 'https://museum.example/' })).toBe('https://museum.example/');
    expect(websiteOf({ 'contact:website': 'https://shop.example' })).toBe('https://shop.example');
    expect(websiteOf({ url: 'https://old.example' })).toBe('https://old.example');
  });

  it('adds https to addresses written without a scheme', () => {
    expect(websiteOf({ website: 'www.museum.example/visit' })).toBe('https://www.museum.example/visit');
  });

  it('takes the first of several addresses', () => {
    expect(websiteOf({ website: 'https://a.example; https://b.example' })).toBe('https://a.example');
  });

  it('ignores anything that is not a web address', () => {
    expect(websiteOf({})).toBeUndefined();
    expect(websiteOf({ website: 'javascript:alert(1)' })).toBeUndefined();
    expect(websiteOf({ website: 'mailto:info@museum.example' })).toBeUndefined();
    expect(websiteOf({ website: 'not a url' })).toBeUndefined();
  });
});

describe('toPlace', () => {
  it('carries the website of the place', () => {
    const shop = {
      type: 'node', id: 5, lat: 48.85, lon: 2.35,
      tags: { name: 'Fripes', shop: 'second_hand', website: 'fripes.example' },
    };
    expect(toPlace(shop, groups, origin).website).toBe('https://fripes.example');
    const plain = { ...shop, tags: { name: 'Fripes', shop: 'second_hand' } };
    expect(toPlace(plain, groups, origin)).not.toHaveProperty('website');
  });

  const louvre = {
    type: 'way',
    id: 42,
    center: { lat: 48.8606, lon: 2.3376 },
    tags: { name: 'Musée du Louvre', 'name:en': 'Louvre Museum', tourism: 'museum', wikipedia: 'fr:Musée du Louvre' },
  };

  it('converts an element into a place', () => {
    const place = toPlace(louvre, groups, origin);
    expect(place).toMatchObject({
      id: 'osm_way_42',
      name: 'Louvre Museum',
      localName: 'Musée du Louvre',
      categories: ['museum'],
      wikipedia: 'fr:Musée du Louvre',
      notable: true,
    });
    expect(place.distance).toBeGreaterThan(1000);
  });

  it('lists every group it matched within that group radius', () => {
    expect(toPlace(louvre, groups, origin).matched).toEqual(['museum', 'for_you:museum']);

    const far = { ...louvre, center: { lat: 48.9, lon: 2.35 } }; // ~5.5 km away
    expect(toPlace(far, groups, origin).matched).toEqual(['for_you:museum']);
  });

  it('marks places without a Wikipedia or Wikidata entry as not notable', () => {
    const shop = { type: 'node', id: 9, lat: 48.85, lon: 2.35, tags: { name: 'Fripes', shop: 'second_hand' } };
    expect(toPlace(shop, groups, origin).notable).toBe(false);
    expect(toPlace({ ...shop, tags: { ...shop.tags, wikidata: 'Q1' } }, groups, origin).notable).toBe(true);
  });

  it('skips unnamed, unlocated or unmatched elements', () => {
    expect(toPlace({ type: 'node', id: 1, lat: 48.85, lon: 2.35, tags: { tourism: 'museum' } }, groups, origin)).toBeNull();
    expect(toPlace({ type: 'node', id: 2, tags: { name: 'X', tourism: 'museum' } }, groups, origin)).toBeNull();
    expect(toPlace({ type: 'node', id: 3, lat: 48.85, lon: 2.35, tags: { name: 'X', shop: 'bakery' } }, groups, origin)).toBeNull();
  });
});
