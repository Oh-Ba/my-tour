import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';

/// The kinds of place that are pleasant to sit at.
enum RestSpotKind {
  garden('garden', 'Garden', Icons.park),
  cafe('cafe', 'Coffee shop', Icons.local_cafe),
  viewpoint('viewpoint', 'Viewpoint', Icons.landscape);

  const RestSpotKind(this.wireName, this.label, this.icon);

  /// Name used by the API.
  final String wireName;
  final String label;
  final IconData icon;

  static RestSpotKind fromWire(Object? value) {
    return values.firstWhere((kind) => kind.wireName == value, orElse: () => garden);
  }
}

/// A nearby place to sit down and listen to the guide.
@immutable
class RestSpot {
  final String id;
  final String name;
  final RestSpotKind kind;
  final double lat;
  final double lon;

  /// Meters from where the search was made.
  final int distance;

  const RestSpot({
    required this.id,
    required this.name,
    required this.kind,
    required this.lat,
    required this.lon,
    required this.distance,
  });

  factory RestSpot.fromJson(Map<String, dynamic> json) {
    return RestSpot(
      id: json['id'] as String,
      name: json['name'] as String,
      kind: RestSpotKind.fromWire(json['kind']),
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      distance: (json['distance'] as num).round(),
    );
  }
}

/// Walking directions to a spot, for the phone's maps app.
Uri directionsUrl(RestSpot spot) {
  return Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': '${spot.lat},${spot.lon}',
    'travelmode': 'walking',
  });
}

/// Finds places to sit around a position.
abstract class RestSpotService {
  /// Never throws: with no connection or no answer there is simply no offer.
  Future<List<RestSpot>> find({required double lat, required double lon});
}

/// [RestSpotService] backed by the app's server.
class HttpRestSpotService implements RestSpotService {
  HttpRestSpotService({required this.baseUrl, required http.Client client})
      : _client = client;

  final String baseUrl;
  final http.Client _client;

  /// A seat is a nicety; the story must not wait long for it.
  static const Duration timeout = Duration(seconds: 12);

  @override
  Future<List<RestSpot>> find({required double lat, required double lon}) async {
    final uri = Uri.parse('$baseUrl/rest-spots').replace(
      queryParameters: {'lat': '$lat', 'lon': '$lon'},
    );
    try {
      final response = await _client.get(uri).timeout(timeout);
      final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      return (body['spots'] as List<dynamic>)
          .map((spot) => RestSpot.fromJson(spot as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}

final restSpotServiceProvider = Provider<RestSpotService>((ref) {
  return HttpRestSpotService(
    baseUrl: ref.watch(apiBaseUrlProvider),
    client: ref.watch(httpClientProvider),
  );
});

/// Opens a link outside the app, e.g. directions in the maps app.
typedef LinkLauncher = Future<void> Function(Uri url);

final directionsLauncherProvider = Provider<LinkLauncher>((ref) {
  return (url) => launchUrl(url, mode: LaunchMode.externalApplication);
});
