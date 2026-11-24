import 'package:flutter_test/flutter_test.dart';
import 'package:my_tour/src/features/place/place_url.dart';
import 'package:my_tour/src/features/poi/poi_model.dart';

Poi place({String name = 'Villa Cerami', String? website, String? wikipedia}) {
  return Poi(
    id: 'p',
    name: name,
    categories: const ['landmark'],
    lat: 37.5,
    lon: 15.08,
    snippet: '',
    distance: 100,
    website: website,
    wikipedia: wikipedia,
  );
}

void main() {
  test('prefers the place\'s own website', () {
    final url = placeUrl(place(website: 'https://villa.example/visit', wikipedia: 'it:Villa Cerami'));
    expect(url.toString(), 'https://villa.example/visit');
  });

  test('upgrades plain http, which phones refuse to load', () {
    expect(placeUrl(place(website: 'http://villa.example')).toString(), 'https://villa.example');
  });

  test('falls back to the Wikipedia article in its own language', () {
    final url = placeUrl(place(wikipedia: 'it:Villa Cerami'));
    expect(url.toString(), 'https://it.m.wikipedia.org/wiki/Villa_Cerami');
  });

  test('encodes article titles with special characters', () {
    final url = placeUrl(place(wikipedia: "fr:Musée d'Orsay?"));
    expect(url.host, 'fr.m.wikipedia.org');
    expect(url.pathSegments.last, "Musée_d'Orsay?");
  });

  test('searches the web when the place has neither', () {
    final url = placeUrl(place(name: 'Novecento & Co'));
    expect(url.host, 'www.google.com');
    expect(url.queryParameters['q'], 'Novecento & Co');
  });

  test('ignores a malformed website or article reference', () {
    expect(placeUrl(place(website: 'not a url')).host, 'www.google.com');
    expect(placeUrl(place(wikipedia: 'Villa Cerami')).host, 'www.google.com');
  });
}
