import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/config.dart';

/// Exception thrown when coffee service encounters an error
class CoffeeServiceException implements Exception {
  final String message;
  final int? statusCode;

  CoffeeServiceException(this.message, [this.statusCode]);

  @override
  String toString() => 'CoffeeServiceException: $message'
      '${statusCode != null ? ' (HTTP $statusCode)' : ''}';
}

/// Representation of a coffee shop near the user
class CoffeeSpot {
  final String id;
  final String name;
  final double lat;
  final double lon;
  final String snippet;
  final double rating;
  final int distance;

  const CoffeeSpot({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    required this.snippet,
    required this.rating,
    required this.distance,
  });

  factory CoffeeSpot.fromJson(Map<String, dynamic> json) {
    return CoffeeSpot(
      id: json['id'] as String,
      name: json['name'] as String,
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      snippet: json['snippet'] as String,
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      distance: (json['distance'] as num?)?.round() ?? 0,
    );
  }
}

/// Response wrapper for coffee endpoint
class CoffeeResponse {
  final int count;
  final int radius;
  final List<CoffeeSpot> spots;

  const CoffeeResponse({
    required this.count,
    required this.radius,
    required this.spots,
  });

  factory CoffeeResponse.fromJson(Map<String, dynamic> json) {
    return CoffeeResponse(
      count: json['count'] as int,
      radius: json['radius'] as int,
      spots: (json['spots'] as List<dynamic>)
          .map((e) => CoffeeSpot.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Service responsible for retrieving coffee recommendations
class CoffeeService {
  final String baseUrl;
  final http.Client _client;

  CoffeeService({
    required this.baseUrl,
    http.Client? client,
  }) : _client = client ?? http.Client();

  Future<CoffeeResponse> fetchCoffee({
    required double lat,
    required double lon,
    int radiusM = 800,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/coffee').replace(
        queryParameters: {
          'lat': lat.toString(),
          'lon': lon.toString(),
          'radiusM': radiusM.toString(),
        },
      );

      final response = await _client.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return CoffeeResponse.fromJson(data);
      }

      final body = response.body.isNotEmpty
          ? jsonDecode(response.body) as Map<String, dynamic>
          : null;

      throw CoffeeServiceException(
        body?['error'] as String? ?? 'Failed to fetch coffee spots',
        response.statusCode,
      );
    } on CoffeeServiceException {
      rethrow;
    } catch (err) {
      throw CoffeeServiceException('Network error: $err');
    }
  }

  void dispose() {
    _client.close();
  }
}

/// Provider for reusing a single CoffeeService instance
final coffeeServiceProvider = Provider<CoffeeService>((ref) {
  return CoffeeService(
    baseUrl: ref.watch(apiBaseUrlProvider),
    client: ref.watch(httpClientProvider),
  );
});
