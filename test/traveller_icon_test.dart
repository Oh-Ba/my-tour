import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_tour/src/features/map/traveller_icon.dart';

const int side = 200;

/// The drawing as raw RGBA pixels.
Future<ByteData> pixelsOf(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  return (await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
}

void main() {
  late Uint8List png;
  late ByteData pixels;

  /// The colour at a point given as fractions of the picture's side.
  Color at(double x, double y) {
    final offset = ((y * side).round() * side + (x * side).round()) * 4;
    return Color.fromARGB(
      pixels.getUint8(offset + 3),
      pixels.getUint8(offset),
      pixels.getUint8(offset + 1),
      pixels.getUint8(offset + 2),
    );
  }

  bool isBlue(Color c) => c.a > 0.8 && c.b > 0.6 && c.r < 0.35;
  bool isClear(Color c) => c.a < 0.05;

  setUpAll(() async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    await binding.runAsync(() async {
      png = await travellerIconPng(pixels: side);
      pixels = await pixelsOf(png);
    });
    // Saved so the drawing can be looked at: flutter test --dart-define=ICON_OUT=<file>
    const out = String.fromEnvironment('ICON_OUT');
    if (out.isNotEmpty) File(out).writeAsBytesSync(png);
  });

  test('is a PNG image', () {
    expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
  });

  test('is drawn in the traveller blue on a see-through background', () {
    expect(travellerColor, Colors.blue.shade700);
    expect(isClear(at(0.02, 0.02)), isTrue);
    expect(isClear(at(0.97, 0.5)), isTrue);
  });

  test('holds a walking staff that rises above the head', () {
    expect(isBlue(at(travellerStaffX, 0.20)), isTrue, reason: 'staff beside the hat');
    expect(isBlue(at(travellerStaffX, 0.70)), isTrue, reason: 'staff down to the ground');
    expect(isClear(at(0.40, 0.14)), isTrue, reason: 'a gap between staff and hat');
  });

  test('wears a pointed hat with a wide brim', () {
    expect(isBlue(at(0.60, 0.22)), isTrue, reason: 'the cone');
    expect(isBlue(at(0.42, 0.30)), isTrue, reason: 'brim to the left');
    expect(isBlue(at(0.78, 0.30)), isTrue, reason: 'brim to the right');
  });

  test('wears a long robe and reaches for the staff', () {
    expect(isBlue(at(0.60, 0.72)), isTrue, reason: 'the robe');
    expect(isBlue(at(0.40, 0.535)), isTrue, reason: 'the arm');
  });

  test('has a long pale beard over a narrow robe', () {
    final beard = at(0.60, 0.50);
    expect(beard.a > 0.8 && beard.b > 0.8 && beard.r > 0.45, isTrue, reason: 'pale blue beard');
    expect(isClear(at(0.40, 0.80)), isTrue, reason: 'the robe is narrow, not a wide skirt');
  });

  test('stands on the bottom edge, where the marker is anchored', () {
    expect(travellerAnchor.dx, 0.5);
    expect(travellerAnchor.dy, greaterThan(0.9));
    expect(isBlue(at(0.54, 0.90)), isTrue, reason: 'a foot');
  });
}
