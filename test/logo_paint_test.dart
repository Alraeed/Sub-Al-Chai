import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spill_the_tea/theme/app_palette.dart';
import 'package:spill_the_tea/widgets/tea_logo.dart';

/// Rasterises the mark at [size] px and returns raw RGBA bytes.
Future<Uint8List> _render(
  int size, {
  bool steam = true,
  double? phase,
}) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  TeaLogoPainter(steamPhase: phase, steam: steam)
      .paint(canvas, Size.square(size.toDouble()));
  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = await picture.toImage(size, size);
  final ByteData? data =
      await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  expect(data, isNotNull);
  return data!.buffer.asUint8List();
}

/// Pixel offset addressed in the painter's own 64-unit design space, or null
/// when the coordinate falls outside the raster.
int? _offsetAt(int size, double dx, double dy) {
  final int x = (dx / TeaLogoPainter.designSide * size).floor();
  final int y = (dy / TeaLogoPainter.designSide * size).floor();
  if (x < 0 || y < 0 || x >= size || y >= size) {
    return null;
  }
  return (y * size + x) * 4;
}

int _alphaAt(Uint8List pixels, int size, double dx, double dy) {
  final int? at = _offsetAt(size, dx, dy);
  return at == null ? 0 : pixels[at + 3];
}

List<int> _rgb(Uint8List pixels, int size, double dx, double dy) {
  final int at = _offsetAt(size, dx, dy)!;
  return <int>[pixels[at], pixels[at + 1], pixels[at + 2]];
}

int _distance(List<int> rgb, Color target) {
  final int r = (target.r * 255).round();
  final int g = (target.g * 255).round();
  final int b = (target.b * 255).round();
  return (rgb[0] - r).abs() + (rgb[1] - g).abs() + (rgb[2] - b).abs();
}

/// Whether a pixel reads as the lapis fill rather than a gold hairline.
bool _isFill(List<int> rgb) =>
    _distance(rgb, AppPalette.lapisHigh) < _distance(rgb, AppPalette.gold);

/// Highest alpha inside a small window, so anti-aliased 3-unit strokes are
/// detected regardless of sub-pixel placement.
int _peakAlpha(
  Uint8List pixels,
  int size, {
  required double dx,
  required double dy,
  double radius = 1.5,
}) {
  int peak = 0;
  for (double ox = -radius; ox <= radius; ox += 0.25) {
    for (double oy = -radius; oy <= radius; oy += 0.25) {
      final int a = _alphaAt(pixels, size, dx + ox, dy + oy);
      if (a > peak) {
        peak = a;
      }
    }
  }
  return peak;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const int size = 256;

  group('TeaLogo mark geometry', () {
    test('the cup body is filled and outlined where the design says', () async {
      final Uint8List pixels = await _render(size, steam: false);

      // Inside the cup (design 30,40) the lapis fill is opaque lapis.
      expect(_alphaAt(pixels, size, 30, 40), 255);
      expect(_isFill(_rgb(pixels, size, 30, 40)), isTrue);

      // The top rim (design y = 24) carries the gold hairline.
      expect(
        _distance(_rgb(pixels, size, 30, 24), AppPalette.gold),
        lessThan(120),
      );

      // The rounded bottom-right corner (radius 9) is still inside the mark,
      // and the open tail reaches down to its (14,58) tip.
      expect(_peakAlpha(pixels, size, dx: 44, dy: 48), greaterThan(0));
      expect(_peakAlpha(pixels, size, dx: 15, dy: 56), greaterThan(60));

      // No gold is drawn across the mouth of the tail (design y = 50): that
      // seam is exactly what one-path authoring avoids, so those pixels must
      // still read as fill.
      expect(_isFill(_rgb(pixels, size, 18.5, 50)), isTrue);
      expect(_isFill(_rgb(pixels, size, 16.5, 50)), isTrue);
    });

    test('the handle loop and tea line are drawn', () async {
      final Uint8List pixels = await _render(size, steam: false);
      // Handle bulge, right of the cup wall.
      expect(_peakAlpha(pixels, size, dx: 54.5, dy: 36.4), greaterThan(120));
      // Tea line just below the rim.
      expect(_peakAlpha(pixels, size, dx: 28, dy: 32), greaterThan(60));
    });

    test('steam curls appear above the rim only when enabled', () async {
      final Uint8List withSteam = await _render(size, steam: true, phase: 0.5);
      final Uint8List without = await _render(size, steam: false);

      // Sample the first curl's mid-point (design ≈19.7,13.45).
      expect(
        _peakAlpha(withSteam, size, dx: 19.7, dy: 13.45, radius: 2),
        greaterThan(0),
      );
      expect(
        _peakAlpha(without, size, dx: 19.7, dy: 13.45, radius: 2),
        0,
      );
    });

    test('nothing is painted outside the mark', () async {
      final Uint8List pixels = await _render(size);
      expect(_alphaAt(pixels, size, 2, 2), 0);
      expect(_alphaAt(pixels, size, 62, 62), 0);
    });

    test('every steam phase renders without throwing', () async {
      for (final double phase in <double>[0, 0.1, 0.33, 0.5, 0.75, 0.99]) {
        final Uint8List pixels = await _render(size, phase: phase);
        expect(pixels.length, size * size * 4);
      }
    });
  });
}
