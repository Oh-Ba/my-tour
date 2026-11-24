/// Why a place is shown on the tour.
enum PoiReason {
  /// Matches something the traveller asked for.
  interest('interest'),

  /// A tourist classic: museum, archaeology, history, landmark.
  classic('classic'),

  /// Matches what the app has learned the traveller likes.
  forYou('for_you');

  const PoiReason(this.wireName);

  /// Name used by the API.
  final String wireName;

  static PoiReason fromWire(Object? value) {
    return values.firstWhere(
      (reason) => reason.wireName == value,
      orElse: () => PoiReason.interest,
    );
  }
}

/// Point of Interest model
class Poi {
  final String id;
  final String name;
  final List<String> categories;
  final double lat;
  final double lon;
  final String snippet;
  final int distance; // Distance in meters from user
  final PoiReason reason;

  /// True for a "for you" recommendation beyond the tour radius.
  final bool outsideRadius;

  /// Wikipedia article, e.g. `en:Colosseum`, when the place has one.
  final String? wikipedia;

  /// The place's own website, when it has one.
  final String? website;

  const Poi({
    required this.id,
    required this.name,
    required this.categories,
    required this.lat,
    required this.lon,
    required this.snippet,
    required this.distance,
    this.reason = PoiReason.interest,
    this.outsideRadius = false,
    this.wikipedia,
    this.website,
  });

  factory Poi.fromJson(Map<String, dynamic> json) {
    return Poi(
      id: json['id'] as String,
      name: json['name'] as String,
      categories: (json['categories'] as List<dynamic>).cast<String>(),
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      snippet: json['snippet'] as String? ?? '',
      distance: (json['distance'] as num).round(),
      reason: PoiReason.fromWire(json['reason']),
      outsideRadius: json['outsideRadius'] as bool? ?? false,
      wikipedia: json['wikipedia'] as String?,
      website: json['website'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'categories': categories,
      'lat': lat,
      'lon': lon,
      'snippet': snippet,
      'distance': distance,
      'reason': reason.wireName,
      'outsideRadius': outsideRadius,
      if (wikipedia != null) 'wikipedia': wikipedia,
      if (website != null) 'website': website,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Poi && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

/// Response from the POI API
class PoiResponse {
  final int count;
  final int radius;
  final List<Poi> pois;

  const PoiResponse({
    required this.count,
    required this.radius,
    required this.pois,
  });

  factory PoiResponse.fromJson(Map<String, dynamic> json) {
    return PoiResponse(
      count: (json['count'] as num).round(),
      radius: (json['radius'] as num).round(),
      pois: (json['pois'] as List<dynamic>)
          .map((e) => Poi.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
