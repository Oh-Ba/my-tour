# My Tour POI Server

A lightweight Node.js Express backend for serving Points of Interest (POIs) to the My Tour mobile app.

## Features

- RESTful API endpoint for retrieving POIs based on location and radius
- Filter POIs by categories/interests
- Distance calculation using Haversine formula
- Results sorted by distance from user location
- Docker support for easy deployment

## Installation

```bash
npm install
```

## Running Locally

```bash
npm start
```

For development with auto-reload:

```bash
npm run dev
```

The server will start on `http://localhost:1402`

## Running with Docker

Build the image:

```bash
docker build -t my-tour-poi-server .
```

Run the container:

```bash
docker run -p 1402:1402 my-tour-poi-server
```

## API Endpoints

### GET /pois

Retrieve Points of Interest based on location and filters.

**Query Parameters:**

- `lat` (required): User's latitude (number)
- `lon` (required): User's longitude (number)
- `radiusM` (optional): Search radius in meters (default: 1000)
- `interests` (optional): Comma-separated categories to filter by

**Example Request:**

```
GET /pois?lat=37.7749&lon=-122.4194&radiusM=2000&interests=landmark,museum
```

**Example Response:**

```json
{
  "count": 5,
  "radius": 2000,
  "pois": [
    {
      "id": "poi_001",
      "name": "Golden Gate Bridge",
      "categories": ["landmark", "viewpoint"],
      "lat": 37.8199,
      "lon": -122.4783,
      "snippet": "Iconic suspension bridge spanning the Golden Gate strait",
      "distance": 8453
    }
  ]
}
```

### GET /health

Health check endpoint.

**Example Response:**

```json
{
  "status": "ok",
  "timestamp": "2025-11-22T10:30:00.000Z"
}
```

## Testing

```bash
npm test
```

## Data

POI data is stored in `fixtures/pois.json`. The current dataset includes sample POIs from San Francisco.

For production, integrate with real POI providers like Google Places API, Mapbox, or Foursquare.
