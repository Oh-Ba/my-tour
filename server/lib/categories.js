/**
 * Category vocabulary shared by every POI provider.
 *
 * A "category" is a canonical key (e.g. `museum`). Each one knows how to find
 * itself in OpenStreetMap through a list of tag selectors.
 *
 * Selector shape: { key: 'tourism', value: 'museum' }      exact match
 *                 { key: 'historic', regex: 'castle|fort' } anchored regex
 *                 { key: 'name', nameRegex: 'vinyl' }       case-insensitive, unanchored
 */

const CATEGORIES = {
  museum: {
    label: 'Museum',
    selectors: [{ key: 'tourism', value: 'museum' }],
  },
  art: {
    label: 'Art',
    selectors: [{ key: 'tourism', regex: 'gallery|artwork' }],
  },
  historical: {
    label: 'Historical site',
    selectors: [
      {
        key: 'historic',
        regex:
          'castle|monument|ruins|fort|city_gate|citywalls|palace|manor|monastery|church|tomb|battlefield|building|tower|aqueduct|heritage',
      },
    ],
  },
  archaeology: {
    label: 'Archaeological site',
    selectors: [{ key: 'historic', value: 'archaeological_site' }],
  },
  landmark: {
    label: 'Landmark',
    selectors: [{ key: 'tourism', value: 'attraction' }],
  },
  viewpoint: {
    label: 'Viewpoint',
    selectors: [{ key: 'tourism', value: 'viewpoint' }],
  },
  park: {
    label: 'Park',
    selectors: [{ key: 'leisure', regex: 'park|garden|nature_reserve' }],
  },
  restaurant: {
    label: 'Restaurant',
    selectors: [{ key: 'amenity', value: 'restaurant' }],
  },
  cafe: {
    label: 'Cafe',
    selectors: [{ key: 'amenity', value: 'cafe' }],
  },
  shopping: {
    label: 'Shopping',
    selectors: [
      { key: 'shop', regex: 'mall|department_store' },
      { key: 'amenity', value: 'marketplace' },
    ],
  },
  nightlife: {
    label: 'Nightlife',
    selectors: [{ key: 'amenity', regex: 'bar|pub|nightclub' }],
  },
  theater: {
    label: 'Theater',
    selectors: [{ key: 'amenity', regex: 'theatre|cinema|arts_centre' }],
  },
  sports: {
    label: 'Sports',
    selectors: [{ key: 'leisure', regex: 'stadium|sports_centre' }],
  },
  second_hand: {
    label: 'Second-hand store',
    selectors: [
      { key: 'shop', regex: 'second_hand|charity' },
      { key: 'second_hand', regex: 'only|yes' },
    ],
  },
  antiques: {
    label: 'Antiques',
    selectors: [{ key: 'shop', value: 'antiques' }],
  },
  books: {
    label: 'Bookshop',
    selectors: [{ key: 'shop', value: 'books' }],
  },
  market: {
    label: 'Market',
    selectors: [{ key: 'amenity', value: 'marketplace' }],
  },
  music: {
    label: 'Music',
    selectors: [
      { key: 'shop', regex: 'music|musical_instrument' },
      { key: 'amenity', value: 'music_venue' },
    ],
  },
  religious: {
    label: 'Place of worship',
    selectors: [{ key: 'amenity', value: 'place_of_worship' }],
  },
  beach: {
    label: 'Beach',
    selectors: [{ key: 'natural', value: 'beach' }],
  },
  nature: {
    label: 'Nature',
    selectors: [
      { key: 'natural', regex: 'peak|waterfall|cave_entrance|spring' },
      { key: 'leisure', value: 'nature_reserve' },
    ],
  },
  bakery: {
    label: 'Bakery',
    selectors: [{ key: 'shop', regex: 'bakery|pastry' }],
  },
  winery: {
    label: 'Winery',
    selectors: [{ key: 'craft', regex: 'winery|brewery|distillery' }],
  },
};

/** The tourist classics that are recommended on every tour unless opted out. */
const CLASSIC_CATEGORIES = ['museum', 'historical', 'archaeology', 'landmark'];

/**
 * Phrases a traveller might type, mapped to a canonical category.
 * Checked as substrings of the lowercased input, first match wins, so more
 * specific phrases come first.
 */
const KEYWORDS = [
  [['second hand', 'second-hand', 'secondhand', 'thrift', 'vintage', 'flea', 'charity shop', 'used clothes'], 'second_hand'],
  [['antique'], 'antiques'],
  [['book'], 'books'],
  [['archaeolog', 'archeolog', 'archiolog', 'excavation', 'ancient ruin'], 'archaeology'],
  [['histor', 'heritage', 'castle', 'monument', 'old town'], 'historical'],
  [['museum'], 'museum'],
  [['gallery', 'galleries', 'street art', 'art'], 'art'],
  [['viewpoint', 'lookout', 'panorama', 'scenic'], 'viewpoint'],
  [['landmark', 'attraction', 'sightseeing'], 'landmark'],
  [['market', 'bazaar', 'souk', 'shuk'], 'market'],
  [['bakery', 'bakeries', 'pastry', 'pastries'], 'bakery'],
  [['winery', 'wineries', 'brewery', 'breweries', 'distillery'], 'winery'],
  [['coffee', 'cafe', 'café'], 'cafe'],
  [['restaurant', 'food', 'dining', 'eat'], 'restaurant'],
  [['nightlife', 'bar', 'pub', 'club'], 'nightlife'],
  [['theater', 'theatre', 'cinema', 'movie'], 'theater'],
  [['record', 'vinyl', 'music', 'concert'], 'music'],
  [['church', 'synagogue', 'mosque', 'temple', 'cathedral', 'worship'], 'religious'],
  [['beach'], 'beach'],
  [['hike', 'hiking', 'nature', 'waterfall', 'mountain'], 'nature'],
  [['park', 'garden'], 'park'],
  [['sport', 'stadium', 'gym'], 'sports'],
  [['shop', 'mall', 'store', 'boutique'], 'shopping'],
];

/** Lowercase, trim, collapse whitespace. */
function normalizeTerm(term) {
  return String(term || '').trim().toLowerCase().replace(/\s+/g, ' ');
}

/** Stable key for a free-text interest that has no canonical category. */
function slugify(term) {
  return normalizeTerm(term)
    .replace(/[^\p{L}\p{N}]+/gu, '_')
    .replace(/^_+|_+$/g, '');
}

/**
 * Resolve an interest term without calling out to anything.
 * Returns the canonical category key, or null when the term is unknown.
 */
function resolveLocally(term) {
  const normalized = normalizeTerm(term);
  if (!normalized) return null;

  const asKey = normalized.replace(/[\s-]+/g, '_');
  if (CATEGORIES[asKey]) return asKey;

  // Plurals of canonical keys: "museums", "parks", "cafes", "bakeries".
  for (const candidate of [asKey.replace(/ies$/, 'y'), asKey.replace(/s$/, '')]) {
    if (CATEGORIES[candidate]) return candidate;
  }

  for (const [phrases, category] of KEYWORDS) {
    if (phrases.some((phrase) => matchesPhrase(normalized, phrase))) {
      return category;
    }
  }
  return null;
}

/** Short phrases must match a whole word ("art" must not match "party"). */
function matchesPhrase(text, phrase) {
  if (phrase.length > 3) return text.includes(phrase);
  return new RegExp(`(^|[^\\p{L}])${phrase}s?($|[^\\p{L}])`, 'u').test(text);
}

/**
 * Last-resort selector for an unknown term: look for it in place names.
 * Only letters, digits and spaces survive, so the result is safe to embed in
 * both a regular expression and an Overpass query string.
 */
function nameSelector(term) {
  const words = normalizeTerm(term).replace(/[^\p{L}\p{N} ]+/gu, ' ').trim();
  return { key: 'name', nameRegex: words.replace(/\s+/g, ' ') };
}

/** The search group for a canonical category. */
function groupFor(category) {
  return { category, selectors: CATEGORIES[category].selectors };
}

module.exports = {
  CATEGORIES,
  groupFor,
  CLASSIC_CATEGORIES,
  normalizeTerm,
  slugify,
  resolveLocally,
  nameSelector,
};
