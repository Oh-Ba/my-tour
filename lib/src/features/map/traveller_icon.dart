import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// The traveller on the map: a tiny stick figure of a wanderer in a pointed,
/// wide-brimmed hat and a long robe, holding a walking staff taller than
/// himself, with a long beard. All positions below are fractions of the picture's side.

final Color travellerColor = Colors.blue.shade700;

final Color travellerBeardColor = Colors.blue.shade100;

/// Width of the traveller on the map, in logical pixels.
const double travellerMarkerWidth = 44;

/// Where the figure touches the ground; the marker is pinned to the map here.
const Offset travellerAnchor = Offset(0.5, 0.94);

/// The staff stands to the figure's left.
const double travellerStaffX = 0.26;

const double _line = 0.055;
const double _ground = 0.94;

Path _polygon(List<Offset> points) => Path()..addPolygon(points, true);

/// Shapes that are filled in: the staff's knob, the hat's cone, the head and
/// the robe.
Path _solidParts() {
  return Path()
    ..addOval(Rect.fromCircle(center: const Offset(travellerStaffX, 0.09), radius: 0.04))
    ..addPath(_polygon(const [Offset(0.45, 0.30), Offset(0.60, 0.04), Offset(0.75, 0.30)]), Offset.zero)
    ..addOval(Rect.fromCircle(center: const Offset(0.60, 0.385), radius: 0.075))
    ..addPath(_polygon(const [Offset(0.60, 0.44), Offset(0.47, 0.86), Offset(0.73, 0.86)]), Offset.zero);
}

/// The beard, from the chin down over the chest.
Path _beard() => _polygon(const [Offset(0.54, 0.41), Offset(0.66, 0.41), Offset(0.60, 0.61)]);

Path _line2(Offset from, Offset to) => Path()
  ..moveTo(from.dx, from.dy)
  ..lineTo(to.dx, to.dy);

/// Shapes that are drawn as lines: the staff, the hat's brim, the arm
/// reaching for the staff, and the two feet.
Path _lineParts() {
  return Path()
    ..addPath(_line2(const Offset(travellerStaffX, 0.09), const Offset(travellerStaffX, _ground)), Offset.zero)
    ..addPath(_line2(const Offset(0.38, 0.30), const Offset(0.82, 0.30)), Offset.zero)
    ..addPath(_line2(const Offset(0.56, 0.56), const Offset(travellerStaffX, 0.52)), Offset.zero)
    ..addPath(_line2(const Offset(0.54, 0.86), const Offset(0.54, _ground)), Offset.zero)
    ..addPath(_line2(const Offset(0.66, 0.86), const Offset(0.66, _ground)), Offset.zero);
}

Paint _stroke(Color color, double width) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..isAntiAlias = true;

/// Draw the figure in [color]; [grow] thickens every part, for the outline.
void _paintFigure(Canvas canvas, Color color, {double grow = 0}) {
  final solid = _solidParts();
  canvas.drawPath(_lineParts(), _stroke(color, _line + grow));
  canvas.drawPath(solid, Paint()..color = color);
  if (grow > 0) canvas.drawPath(solid, _stroke(color, grow));
}

/// The traveller on a transparent background, on a canvas [size] wide. A thin
/// white outline keeps the figure readable on any map colour.
void paintTraveller(Canvas canvas, double size) {
  canvas
    ..save()
    ..scale(size);
  _paintFigure(canvas, Colors.white, grow: 0.07);
  _paintFigure(canvas, travellerColor);
  canvas.drawPath(_beard(), Paint()..color = travellerBeardColor);
  canvas.restore();
}

/// The traveller drawn as a square PNG, [pixels] on each side.
Future<Uint8List> travellerIconPng({int pixels = 176}) async {
  final recorder = ui.PictureRecorder();
  paintTraveller(Canvas(recorder), pixels.toDouble());

  final image = await recorder.endRecording().toImage(pixels, pixels);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// The traveller as a map marker icon, drawn once and then reused.
final travellerIconProvider = FutureProvider<BitmapDescriptor>((ref) async {
  return BitmapDescriptor.bytes(await travellerIconPng(), width: travellerMarkerWidth);
});
