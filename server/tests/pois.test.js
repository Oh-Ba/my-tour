const request = require('supertest');
const app = require('../index');

describe('POI API', () => {
  describe('GET /health', () => {
    it('should return health status', async () => {
      const response = await request(app).get('/health');
      expect(response.status).toBe(200);
      expect(response.body.status).toBe('ok');
      expect(response.body.timestamp).toBeDefined();
    });
  });

  describe('GET /pois', () => {
    it('should return 400 if lat or lon is missing', async () => {
      const response = await request(app).get('/pois');
      expect(response.status).toBe(400);
      expect(response.body.error).toContain('required');
    });

    it('should return 400 if lat is missing', async () => {
      const response = await request(app).get('/pois?lon=-122.4194');
      expect(response.status).toBe(400);
      expect(response.body.error).toContain('required');
    });

    it('should return 400 if lon is missing', async () => {
      const response = await request(app).get('/pois?lat=37.7749');
      expect(response.status).toBe(400);
      expect(response.body.error).toContain('required');
    });

    it('should return 400 for invalid lat/lon format', async () => {
      const response = await request(app).get('/pois?lat=invalid&lon=also-invalid');
      expect(response.status).toBe(400);
      expect(response.body.error).toContain('Invalid');
    });

    it('should return POIs within default 1km radius', async () => {
      // San Francisco coordinates
      const response = await request(app).get('/pois?lat=37.7749&lon=-122.4194');
      expect(response.status).toBe(200);
      expect(response.body.count).toBeDefined();
      expect(response.body.radius).toBe(1000);
      expect(response.body.pois).toBeInstanceOf(Array);

      // All POIs should have required fields and distance
      response.body.pois.forEach(poi => {
        expect(poi.id).toBeDefined();
        expect(poi.name).toBeDefined();
        expect(poi.categories).toBeInstanceOf(Array);
        expect(poi.lat).toBeDefined();
        expect(poi.lon).toBeDefined();
        expect(poi.snippet).toBeDefined();
        expect(poi.distance).toBeDefined();
        expect(poi.distance).toBeLessThanOrEqual(1000);
      });
    });

    it('should return POIs within custom radius', async () => {
      const response = await request(app).get('/pois?lat=37.7749&lon=-122.4194&radiusM=5000');
      expect(response.status).toBe(200);
      expect(response.body.radius).toBe(5000);

      // All POIs should be within 5km
      response.body.pois.forEach(poi => {
        expect(poi.distance).toBeLessThanOrEqual(5000);
      });
    });

    it('should return POIs sorted by distance', async () => {
      const response = await request(app).get('/pois?lat=37.7749&lon=-122.4194&radiusM=10000');
      expect(response.status).toBe(200);

      const pois = response.body.pois;
      if (pois.length > 1) {
        for (let i = 1; i < pois.length; i++) {
          expect(pois[i].distance).toBeGreaterThanOrEqual(pois[i - 1].distance);
        }
      }
    });

    it('should filter POIs by interests', async () => {
      const response = await request(app).get('/pois?lat=37.7749&lon=-122.4194&radiusM=10000&interests=museum');
      expect(response.status).toBe(200);

      // All returned POIs should have 'museum' in categories
      response.body.pois.forEach(poi => {
        expect(poi.categories).toContain('museum');
      });
    });

    it('should filter POIs by multiple interests', async () => {
      const response = await request(app).get('/pois?lat=37.7749&lon=-122.4194&radiusM=10000&interests=museum,landmark');
      expect(response.status).toBe(200);

      // All returned POIs should have either 'museum' or 'landmark' in categories
      response.body.pois.forEach(poi => {
        const hasMuseum = poi.categories.includes('museum');
        const hasLandmark = poi.categories.includes('landmark');
        expect(hasMuseum || hasLandmark).toBe(true);
      });
    });

    it('should return empty array for location with no nearby POIs', async () => {
      // Coordinates in the middle of the ocean
      const response = await request(app).get('/pois?lat=0&lon=0&radiusM=1000');
      expect(response.status).toBe(200);
      expect(response.body.count).toBe(0);
      expect(response.body.pois).toEqual([]);
    });

    it('should calculate distance correctly', async () => {
      // Test with known coordinates
      const response = await request(app).get('/pois?lat=37.8199&lon=-122.4783&radiusM=100');
      expect(response.status).toBe(200);

      // Should find Golden Gate Bridge POI at this exact location
      const goldenGate = response.body.pois.find(poi => poi.id === 'poi_001');
      if (goldenGate) {
        // Distance should be very small (within 100m)
        expect(goldenGate.distance).toBeLessThan(100);
      }
    });
  });

  describe('GET /coffee', () => {
    it('should enforce required coordinates', async () => {
      const response = await request(app).get('/coffee');
      expect(response.status).toBe(400);
      expect(response.body.error).toContain('required');
    });

    it('should validate numeric parameters', async () => {
      const response = await request(app).get('/coffee?lat=abc&lon=def');
      expect(response.status).toBe(400);
      expect(response.body.error).toContain('Invalid');
    });

    it('should return nearby coffee spots sorted by distance', async () => {
      const response = await request(app).get('/coffee?lat=37.7749&lon=-122.4194&radiusM=5000');
      expect(response.status).toBe(200);
      expect(response.body.count).toBeGreaterThanOrEqual(0);
      expect(response.body.spots).toBeInstanceOf(Array);

      const { spots } = response.body;
      if (spots.length > 1) {
        for (let i = 1; i < spots.length; i++) {
          expect(spots[i].distance).toBeGreaterThanOrEqual(spots[i - 1].distance);
        }
      }

      spots.forEach(spot => {
        expect(spot.id).toBeDefined();
        expect(spot.name).toBeDefined();
        expect(spot.lat).toBeDefined();
        expect(spot.lon).toBeDefined();
        expect(spot.snippet).toBeDefined();
        expect(spot.rating).toBeDefined();
        expect(spot.distance).toBeLessThanOrEqual(5000);
      });
    });
  });
});
