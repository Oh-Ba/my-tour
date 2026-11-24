# POI Feature - Setup and Usage Guide

This guide explains how to set up and use the new Points of Interest (POI) feature in the My Tour app.

## Overview

The POI feature allows users to:
- View nearby points of interest on the map based on their location and selected interests
- See POIs as color-coded markers on the map
- Browse POIs in a scrollable bottom sheet, sorted by distance
- Tap on POIs to view detailed information
- Navigate to POIs on the map

## Architecture

### Backend (Node.js + Express)
- **Location**: `server/`
- **Endpoint**: `GET /pois?lat=<lat>&lon=<lon>&radiusM=<radius>&interests=<categories>`
- **Features**:
  - Haversine distance calculation
  - Category filtering
  - Distance-based sorting
  - Mock data with 15 San Francisco POIs

### Flutter Client
- **State Management**: Riverpod
- **Key Components**:
  - `PoiService`: HTTP client for fetching POIs
  - `PoiRepository`: State management with Riverpod
  - `PoiListSheet`: Bottom sheet with scrollable POI list
  - `PoiDetailCard`: Detailed POI information modal
  - `MapViewController`: Map marker management

## Setup Instructions

### 1. Backend Setup

#### Option A: Run Locally with Node.js

```bash
# Navigate to server directory
cd server

# Install dependencies
npm install

# Start the server
npm start

# For development with auto-reload
npm run dev
```

The server will start on `http://localhost:1402`

#### Option B: Run with Docker

```bash
# Build the Docker image
cd server
docker build -t my-tour-poi-server .

# Run the container
docker run -p 1402:1402 my-tour-poi-server
```

#### Run Backend Tests

```bash
cd server
npm test
```

### 2. Flutter Client Setup

#### Update Backend URL

Before running the Flutter app, update the backend URL in the POI service provider:

**File**: `lib/src/features/poi/poi_repository.dart`

```dart
final poiServiceProvider = Provider<PoiService>((ref) {
  return PoiService(
    baseUrl: 'http://10.0.2.2:1402', // For Android emulator
    // For physical device, use: 'http://<YOUR_COMPUTER_IP>:1402'
    // For iOS simulator, use: 'http://localhost:1402'
  );
});
```

**Important**: Replace `<YOUR_COMPUTER_IP>` with your actual IP address when testing on a physical device.

To find your IP address:
- **Windows**: Run `ipconfig` in Command Prompt, look for IPv4 Address
- **macOS/Linux**: Run `ifconfig` or `ip addr`

#### Install Flutter Dependencies

The required dependencies are already in `pubspec.yaml`:
- `http: ^1.2.0` - HTTP client
- `freezed_annotation: ^2.4.1` - (optional) Code generation
- `json_annotation: ^4.8.1` - (optional) JSON serialization

**Note**: The POI models use simple Dart classes, not freezed, for easier setup.

### 3. Using the POI Feature

#### Starting a Trip

1. Open the app and grant location permissions
2. Tap **"Start Trip"** button
3. Select your interests (e.g., Museums, Restaurants, Parks)
4. Adjust the radius slider (default: 1 km)
5. Tap **"Start Trip"**

#### Viewing POIs

Once a trip is started:
- **Map View**: POIs appear as color-coded markers on the map
- **Bottom Sheet**: Swipe up to see the full list of nearby POIs
- **Distance**: All POIs show distance from your current location

#### Marker Colors by Category

- 🟣 **Purple**: Museums
- 🟠 **Orange**: Restaurants
- 🟢 **Green**: Parks & Nature
- 🔴 **Red**: Landmarks
- 🟡 **Yellow**: Shopping
- 🔵 **Cyan**: Viewpoints
- 🔵 **Blue**: Other

#### Interacting with POIs

- **Tap marker**: Highlights POI and centers map
- **Tap list item**: Centers map on POI
- **Tap info button (ⓘ)**: Opens detailed POI card
- **POI Detail Card**: Shows full information with action buttons

## API Reference

### Backend API

#### GET /pois

Retrieve Points of Interest based on location and filters.

**Query Parameters**:
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| lat | number | Yes | - | User's latitude |
| lon | number | Yes | - | User's longitude |
| radiusM | number | No | 1000 | Search radius in meters |
| interests | string | No | - | Comma-separated categories |

**Example**:
```
GET /pois?lat=37.7749&lon=-122.4194&radiusM=2000&interests=museum,landmark
```

**Response**:
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

#### GET /health

Health check endpoint.

**Response**:
```json
{
  "status": "ok",
  "timestamp": "2025-11-22T10:30:00.000Z"
}
```

## File Structure

### Backend Files
```
server/
├── index.js                    # Express server and API endpoints
├── package.json                # Node.js dependencies
├── Dockerfile                  # Docker configuration
├── fixtures/
│   └── pois.json              # Mock POI data
├── tests/
│   └── pois.test.js           # API tests with Jest
└── README.md                   # Backend documentation
```

### Flutter Client Files
```
lib/src/features/poi/
├── poi_model.dart              # POI and PoiResponse data models
├── poi_service.dart            # HTTP service for fetching POIs
├── poi_repository.dart         # Riverpod state management
├── poi_list_sheet.dart         # Bottom sheet with POI list
└── poi_detail_card.dart        # Detailed POI information card
```

## Customization

### Adding More POIs

Edit `server/fixtures/pois.json` and add more POI objects:

```json
{
  "id": "poi_016",
  "name": "Your POI Name",
  "categories": ["museum", "art"],
  "lat": 37.7749,
  "lon": -122.4194,
  "snippet": "Description of the POI"
}
```

### Category Mapping

The app automatically maps trip interests to backend categories:

| Trip Interest | Backend Category |
|--------------|------------------|
| Restaurants | restaurant |
| Museums | museum |
| Parks | park, nature |
| Shopping | shopping |
| Historical Sites | landmark |

Categories are case-insensitive in the backend.

### Adjusting Fetch Behavior

In `lib/src/features/poi/poi_repository.dart`:

```dart
/// Minimum distance in meters to trigger a new fetch
static const double minDistanceForRefetch = 100;
```

Change this value to control how often POIs are refreshed as the user moves.

## Troubleshooting

### POIs Not Showing

1. **Check backend is running**: Visit `http://localhost:1402/health` in browser
2. **Check backend URL**: Ensure correct IP/port in `poi_repository.dart`
3. **Start a trip**: POIs only fetch after selecting interests
4. **Check console**: Look for errors in backend and Flutter logs

### Empty POI List

- **Wrong location**: Mock data uses San Francisco coordinates (37.7749, -122.4194)
- **Radius too small**: Increase radius in trip settings
- **No matching interests**: Try selecting different categories

### Network Errors

- **Android Emulator**: Use `http://10.0.2.2:1402`
- **iOS Simulator**: Use `http://localhost:1402`
- **Physical Device**:
  - Ensure phone and computer are on same WiFi
  - Use computer's IP address: `http://192.168.x.x:1402`
  - Check firewall settings

### Backend Connection Refused

- Verify backend is running: `curl http://localhost:1402/health`
- Check if port 1402 is already in use
- Try a different port and update client configuration

## Next Steps

### Future Enhancements

1. **Real POI Provider Integration**
   - Google Places API
   - Mapbox POI data
   - Foursquare/Yelp integration

2. **Advanced Features**
   - POI favorites/bookmarks
   - Turn-by-turn navigation
   - User reviews and ratings
   - Photo galleries
   - Offline POI caching

3. **Performance Optimizations**
   - Marker clustering for dense areas
   - Pagination for large result sets
   - POI caching strategy
   - Custom marker icons from assets

## Testing

### Backend Tests

```bash
cd server
npm test
```

Tests cover:
- Health check endpoint
- Parameter validation
- Distance calculation
- Category filtering
- Response format

### Flutter Tests

Client tests are planned but not yet implemented. See `test/widget_test.dart` for examples.

## Support

For issues or questions:
- Check the server logs for backend errors
- Use Flutter DevTools for client debugging
- Review the code comments in each file
- Check network traffic with tools like Charles Proxy or Postman

## License

This feature is part of the My Tour application.
