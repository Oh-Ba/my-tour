import '../poi/poi_model.dart';

/// The place's own website, if it has a usable one. Plain `http` is upgraded
/// to `https`, because phones refuse to load unencrypted pages.
Uri? _ownWebsite(Poi poi) {
  final url = Uri.tryParse(poi.website ?? '');
  if (url == null || url.host.isEmpty || !url.scheme.startsWith('http')) return null;
  return url.replace(scheme: 'https');
}

/// The mobile Wikipedia article for a reference such as `it:Villa Cerami`.
Uri? _wikipediaArticle(Poi poi) {
  final match = RegExp(r'^([a-z-]+):(.+)$').firstMatch(poi.wikipedia ?? '');
  if (match == null) return null;
  return Uri(
    scheme: 'https',
    host: '${match.group(1)}.m.wikipedia.org',
    pathSegments: ['wiki', match.group(2)!.replaceAll(' ', '_')],
  );
}

Uri _webSearch(Poi poi) => Uri.https('www.google.com', '/search', {'q': poi.name});

/// The web page to show for a place: its own website, else its Wikipedia
/// article, else a web search for its name.
Uri placeUrl(Poi poi) => _ownWebsite(poi) ?? _wikipediaArticle(poi) ?? _webSearch(poi);
