const { calculateDistance, extendedRadius, boundingBox } = require('../lib/geo');

describe('calculateDistance', () => {
  it('is zero for the same point', () => {
    expect(calculateDistance(10, 20, 10, 20)).toBe(0);
  });

  it('measures one degree of longitude on the equator as ~111 km', () => {
    expect(calculateDistance(0, 0, 0, 1)).toBeCloseTo(111195, -2);
  });
});

describe('extendedRadius', () => {
  it('reaches at least 5 km beyond a small radius', () => {
    expect(extendedRadius(1000)).toBe(6000);
  });

  it('triples a medium radius', () => {
    expect(extendedRadius(3000)).toBe(9000);
  });

  it('is capped at 60 km, where wider searches become too slow', () => {
    expect(extendedRadius(30000)).toBe(60000);
  });

  it('still reaches 10 km beyond the largest tour radius', () => {
    expect(extendedRadius(50000)).toBe(60000);
    expect(extendedRadius(55000)).toBe(65000);
  });
});

describe('boundingBox', () => {
  it('extends the radius in every direction', () => {
    const box = boundingBox(0, 10, 111320);
    expect(box.south).toBeCloseTo(-1, 5);
    expect(box.north).toBeCloseTo(1, 5);
    expect(box.west).toBeCloseTo(9, 5);
    expect(box.east).toBeCloseTo(11, 5);
  });

  it('widens in longitude away from the equator', () => {
    const box = boundingBox(60, 10, 111320);
    expect(box.east - box.west).toBeCloseTo(4, 3);
    expect(box.north - box.south).toBeCloseTo(2, 5);
  });
});
