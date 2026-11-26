# My Tour - Flutter Location-Based Trip Planner

A Flutter application that helps you plan trips based on your interests and location. The app shows your location on a map, allows you to select interests and search radius, and saves your trip preferences locally.

## Features

- **Location Tracking**: Real-time location tracking with blue dot on map
- **Permission Handling**: Robust permission flow for location services
- **Trip Planning**: Select interests and radius for your trip
- **Map Integration**: Google Maps integration with recenter functionality
- **Offline Storage**: Trip preferences saved locally using SharedPreferences
- **Material Design 3**: Modern UI with Material 3 components

## Screenshots

The app includes:
- Interactive Google Maps view with user location
- Permission rationale screens for denied/disabled location
- Bottom sheet for trip configuration with interest chips and radius slider
- Floating action buttons for recentering and starting trips

## Prerequisites

- Flutter SDK (3.9.2 or higher)
- Dart SDK (included with Flutter)
- Android Studio / VS Code with Flutter extensions
- Xcode (for iOS development on macOS)
- Google Maps API Key (see setup instructions below)

## Getting Started

### 1. Clone the Repository

```bash
git clone <your-repository-url>
cd my_tour
```

### 2. Install Dependencies

```bash
flutter pub get
```

### 3. Get Google Maps API Key

You need a Google Maps API key for both Android and iOS:

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select an existing one
3. Enable the following APIs:
   - Maps SDK for Android
   - Maps SDK for iOS
4. Create credentials (API Key)
5. (Optional) Restrict your API key to prevent unauthorized use

### 4. Configure API Keys

#### Android Configuration

1. Open `android/app/src/main/AndroidManifest.xml`
2. Find the line with `YOUR_GOOGLE_MAPS_API_KEY_HERE`
3. Replace it with your actual API key:

```xml
<meta-data
    android:name="com.google.android.geo.API_KEY"
    android:value="YOUR_ACTUAL_API_KEY_HERE"/>
```

#### iOS Configuration

1. Open `ios/Runner/AppDelegate.swift`
2. Find the line with `YOUR_GOOGLE_MAPS_API_KEY_HERE`
3. Replace it with your actual API key:

```swift
GMSServices.provideAPIKey("YOUR_ACTUAL_API_KEY_HERE")
```

### 5. Run the App

#### Android

```bash
flutter run
```

Or with a specific device:
```bash
flutter devices  # List available devices
flutter run -d <device-id>
```

#### iOS (macOS only)

```bash
# Install iOS dependencies
cd ios
pod install
cd ..

# Run the app
flutter run -d <ios-device-id>
```

## AI Tour Guide Setup

The guide's stories, photo explanations and free-text interests are written by Claude on the backend.

```bash
cd server
npm install
cp .env.example .env      # then put your ANTHROPIC_API_KEY in .env
npm start
```

Point the app at the server:

```bash
flutter run --dart-define=API_BASE_URL=http://<your-computer-ip>:1402
```

Without an API key the map and place recommendations still work; opening the guide shows "AI guide is not configured".

Places come from OpenStreetMap, so the app works anywhere in the world. Set `POI_PROVIDER=fixtures` in `.env` to use the bundled San Francisco sample data instead.

### Running the tests

```bash
flutter test          # app: unit and widget tests
cd server && npm test # backend
```

## Project Structure

```
lib/
├── main.dart                          # App entry point with Riverpod setup
├── src/
    ├── app.dart                       # Main app widget with theme
    ├── features/
    │   ├── map/
    │   │   ├── map_page.dart         # Main map screen
    │   │   └── map_controller.dart   # Map state management
    │   └── trip_start/
    │       ├── trip_sheet.dart       # Bottom sheet for trip config
    │       └── trip_state.dart       # Trip state with Riverpod
    ├── services/
    │   └── location_service.dart     # Location & permission handling
    └── widgets/
        └── permission_rationale.dart # Permission UI components
```

## Key Dependencies

- `google_maps_flutter: ^2.5.0` - Google Maps integration
- `geolocator: ^10.1.0` - Location services
- `permission_handler: ^11.1.0` - Runtime permissions
- `flutter_riverpod: ^2.4.9` - State management
- `shared_preferences: ^2.2.2` - Local data persistence
- `flutter_local_notifications: ^16.3.0` - Notifications (future use)
- `intl: ^0.19.0` - Internationalization

## Permissions

### Android

The app requests the following permissions:
- `ACCESS_FINE_LOCATION` - Precise location access
- `ACCESS_COARSE_LOCATION` - Approximate location access
- `INTERNET` - For map tiles and data
- `POST_NOTIFICATIONS` - For future notification features

### iOS

The app includes usage descriptions for:
- `NSLocationWhenInUseUsageDescription` - Location access while using app
- `NSLocationAlwaysUsageDescription` - Background location access
- `NSLocationAlwaysAndWhenInUseUsageDescription` - Combined permission

## Testing

### Manual Testing

1. **Permission Denied Flow**:
   - Deny location permission on first launch
   - Verify permission rationale screen appears
   - Tap "Open Settings" to verify redirection works

2. **Permission Granted Flow**:
   - Allow location permission
   - Verify blue dot appears on map
   - Verify map centers on your location

3. **Location Updates**:
   - Use Android emulator location simulator (Extended controls > Location)
   - Change location and verify map updates
   - Test recenter button functionality

4. **Trip Configuration**:
   - Tap "Start Trip" button
   - Select multiple interest chips
   - Adjust radius slider
   - Verify trip saves successfully
   - Restart app to verify persistence

### Automated Testing

Run widget tests:
```bash
flutter test
```

## Troubleshooting

### Common Issues

**Issue: Map shows blank/gray tiles**
- Solution: Verify your Google Maps API key is correctly configured
- Ensure Maps SDK is enabled in Google Cloud Console
- Check logcat/console for API errors

**Issue: Location permission denied**
- Solution: Go to device Settings > Apps > My Tour > Permissions > Enable Location

**Issue: App crashes on iOS**
- Solution: Ensure `pod install` was run in the ios directory
- Clean build: `flutter clean && flutter pub get`

**Issue: Build fails on Android**
- Solution: Ensure minSdk is set to 21 in `android/app/build.gradle.kts`

### Debug Commands

```bash
# Clean build
flutter clean
flutter pub get

# Run with verbose logging
flutter run -v

# Check for issues
flutter doctor -v

# View logs
# Android:
adb logcat | grep flutter

# iOS:
flutter logs
```

## Available Interests

The app currently supports the following interest categories:
- Restaurants
- Museums
- Parks
- Shopping
- Nightlife
- Art Galleries
- Historical Sites
- Cafes
- Theater
- Sports

You can customize these in `lib/src/features/trip_start/trip_state.dart`.

## Future Enhancements

- Geofencing for location-based notifications
- Integration with Places API for POI suggestions
- Route planning between multiple points
- Trip history and favorites
- Social sharing features
- Multi-language support using intl package

## Platform Support

- ✅ Android (API 21+)
- ✅ iOS (13.0+)
- ⚠️ Web (limited - location services may vary)
- ❌ Desktop (not configured)

## Development

### Code Style

This project follows Flutter style guidelines:
```bash
# Format code
flutter format .

# Analyze code
flutter analyze
```

### State Management

The app uses Riverpod for state management:
- `tripStateProvider` - Manages trip configuration
- `locationServiceProvider` - Provides location service instance
- `mapStateProvider` - Manages map state and controller

### Adding New Features

1. Create feature directory under `lib/src/features/`
2. Implement UI components
3. Create Riverpod providers for state management
4. Update navigation if needed
5. Add tests

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues and questions:
- Create an issue in the GitHub repository
- Check existing issues for solutions
- Review Flutter documentation: https://flutter.dev/docs

## Acknowledgments

- Google Maps Flutter Plugin
- Flutter team for excellent documentation
- Riverpod for state management solution
# my-tour
