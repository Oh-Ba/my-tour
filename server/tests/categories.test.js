const { resolveLocally, nameSelector, slugify, groupFor } = require('../lib/categories');

describe('resolveLocally', () => {
  it.each([
    ['Museums', 'museum'],
    ['Historical Sites', 'historical'],
    ['Art Galleries', 'art'],
    ['Cafes', 'cafe'],
    ['Parks', 'park'],
    ['Restaurants', 'restaurant'],
    ['Shopping', 'shopping'],
    ['Nightlife', 'nightlife'],
    ['Theater', 'theater'],
    ['Sports', 'sports'],
  ])('resolves the app label %s', (label, category) => {
    expect(resolveLocally(label)).toBe(category);
  });

  it.each([
    ['Second hand stores', 'second_hand'],
    ['thrift shops', 'second_hand'],
    ['flea markets', 'second_hand'],
    ['archeology', 'archaeology'],
    ['old bookshops', 'books'],
  ])('resolves the free text "%s"', (text, category) => {
    expect(resolveLocally(text)).toBe(category);
  });

  it('does not match short keywords inside other words', () => {
    expect(resolveLocally('birthday party supplies')).toBeNull();
    expect(resolveLocally('quantum physics')).toBeNull();
  });

  it('returns null for empty input', () => {
    expect(resolveLocally('  ')).toBeNull();
    expect(resolveLocally(undefined)).toBeNull();
  });
});

describe('groupFor', () => {
  it('builds a search group for a canonical category', () => {
    expect(groupFor('museum')).toEqual({
      category: 'museum',
      selectors: [{ key: 'tourism', value: 'museum' }],
    });
  });
});

describe('nameSelector', () => {
  it('keeps only characters that are safe inside a query', () => {
    expect(nameSelector('Vinyl "Records"]; (x)')).toEqual({
      key: 'name',
      nameRegex: 'vinyl records x',
    });
  });
});

describe('slugify', () => {
  it('makes a stable key from free text, in any script', () => {
    expect(slugify('  Vinyl  Record-Shops ')).toBe('vinyl_record_shops');
    expect(slugify('חנויות יד שנייה')).toBe('חנויות_יד_שנייה');
  });
});
