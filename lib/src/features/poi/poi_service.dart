import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/config.dart';
import 'poi_model.dart';
import 'poi_query.dart';

/// Exception thrown when POI service encounters an error
class PoiServiceException implements Exception {
  final String message;
  final int? statusCode;

  PoiServiceException(this.message, [this.statusCode]);

  /// Shown to the traveller, so it is the message alone.
  @override
  String toString() => message;
}

/// The `/pois` request for a position and a tour query.
Uri buildPoisUri(
  String baseUrl, {
  required double lat,
  required double lon,
  required PoiQuery query,
}) {
  return Uri.parse('$baseUrl/pois').replace(
    queryParameters: {
      'lat': lat.toString(),
      'lon': lon.toString(),
      'radiusM': query.radiusM.toString(),
      if (query.interests.isNotEmpty) 'interests': query.interests.join(','),
      'classics': query.classics.toString(),
      if (query.learned.isNotEmpty) 'learned': query.learned.join(','),
    },
  );
}

/// The `error` field of a JSON error body, if there is one.
String? serverErrorMessage(String body) {
  try {
    return (jsonDecode(body) as Map<String, dynamic>)['error'] as String?;
  } catch (_) {
    return null;
  }
}

/// Service for fetching Points of Interest from the backend
class PoiService {
  final String baseUrl;
  final http.Client _client;

  /// Looking up real places can take a while on a slow connection.
  static const Duration timeout = Duration(seconds: 45);

  PoiService({required this.baseUrl, required http.Client client})
      : _client = client;

  /// Places around a position for a tour [query].
  ///
  /// Throws [PoiServiceException] if the request fails.
  Future<PoiResponse> fetchPois({
    required double lat,
    required double lon,
    required PoiQuery query,
  }) async {
    final uri = buildPoisUri(baseUrl, lat: lat, lon: lon, query: query);
    final http.Response response;
    try {
      response = await _client.get(uri).timeout(timeout);
    } catch (_) {
      throw PoiServiceException(
        'Could not reach the tour server. Check that it is running and the phone is connected.',
      );
    }

    if (response.statusCode != 200) {
      throw PoiServiceException(
        serverErrorMessage(response.body) ?? 'Failed to fetch POIs',
        response.statusCode,
      );
    }
    return PoiResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}

final poiServiceProvider = Provider<PoiService>((ref) {
  return PoiService(
    baseUrl: ref.watch(apiBaseUrlProvider),
    client: ref.watch(httpClientProvider),
  );
});
