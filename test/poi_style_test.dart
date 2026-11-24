import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_tour/src/features/poi/poi_model.dart';
import 'package:my_tour/src/features/poi/poi_style.dart';

import 'helpers/fakes.dart';

void main() {
  test('formats distances for walking', () {
    expect(formatDistance(0), '0 m');
    expect(formatDistance(999), '999 m');
    expect(formatDistance(1000), '1.0 km');
    expect(formatDistance(12345), '12.3 km');
  });

  test('styles a place by its first known category', () {
    expect(styleFor(['museum', 'landmark']).icon, Icons.museum);
    expect(styleFor(['unknown', 'park']).icon, Icons.park);
    expect(styleFor(['second_hand']).icon, Icons.storefront);
    expect(styleFor(['something_else']).icon, Icons.place);
    expect(styleFor([]).color, Colors.blue);
  });

  test('explains why a place is recommended', () {
    expect(reasonLabel(samplePoi()), isNull);
    expect(reasonLabel(samplePoi(reason: PoiReason.classic)), 'Classic');
    expect(reasonLabel(samplePoi(reason: PoiReason.forYou)), 'For you');
    expect(
      reasonLabel(samplePoi(reason: PoiReason.forYou, outsideRadius: true)),
      'For you · beyond your radius',
    );
  });

  test('shows category keys as readable labels', () {
    expect(categoryLabel('second_hand'), 'Second hand');
    expect(categoryLabel('museum'), 'Museum');
  });
}
