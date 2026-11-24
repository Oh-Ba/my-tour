import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../map/map_controller.dart';
import '../poi/poi_repository.dart';
import 'guide_page.dart';
import 'photo_picker.dart';

/// How many nearby place names are sent along with a photo.
const int nearbyNamesLimit = 8;

/// Names of the closest places, which help the guide recognise a photo.
List<String> nearestNames(List<Poi> sortedPois) {
  return sortedPois.take(nearbyNamesLimit).map((poi) => poi.name).toList();
}

/// Open the AI guide for a place, a photo, or a photo taken at a place.
Future<void> openGuide(
  BuildContext context,
  WidgetRef ref, {
  Poi? poi,
  PickedPhoto? photo,
  bool autoPlay = false,
}) {
  final position = ref.read(mapStateProvider).currentPosition;
  final nearby = nearestNames(ref.read(sortedPoisProvider));
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => GuidePage(
        poi: poi,
        initialPhoto: photo,
        lat: position?.latitude,
        lon: position?.longitude,
        nearby: nearby,
        autoPlay: autoPlay,
      ),
    ),
  );
}
