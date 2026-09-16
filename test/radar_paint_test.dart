import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spill_the_tea/models/peer.dart';
import 'package:spill_the_tea/screens/radar/radar_model.dart';
import 'package:spill_the_tea/widgets/mesh_orbit_painter.dart';

Peer _peer(String id) {
  return Peer(
    id: id,
    displayName: 'صاحب $id',
    signPublicKey: Uint8List(32),
    dhPublicKey: Uint8List(32),
    shortId: 'aabbccdd11223344',
    firstSeenAt: DateTime.fromMillisecondsSinceEpoch(1000),
    lastSeenAt: DateTime.fromMillisecondsSinceEpoch(2000),
  );
}

RadarSnapshot _snap({
  bool bleOn = true,
  bool scanning = true,
  bool relay = true,
  List<RadarPeer>? peers,
}) {
  return RadarSnapshot(
    bleOn: bleOn,
    scanning: scanning,
    advertising: true,
    relayEnabled: relay,
    peers: peers ?? <RadarPeer>[],
    maxHops: 3,
  );
}

/// Rasterises the painter at [size] px and returns raw RGBA bytes.
Future<Uint8List> _render(int size, RadarSnapshot snapshot,
    {double pulse = 0.5}) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  MeshOrbitPainter(snapshot: snapshot, pulse: pulse)
      .paint(canvas, Size.square(size.toDouble()));
  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = await picture.toImage(size, size);
  final ByteData? data =
      await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  expect(data, isNotNull);
  return data!.buffer.asUint8List();
}

/// Pixel offset for a point inside the painter's square, or null when outside.
int? _offsetAt(int size, double dx, double dy) {
  final int x = dx.floor();
  final int y = dy.floor();
  if (x < 0 || y < 0 || x >= size || y >= size) {
    return null;
  }
  return (y * size + x) * 4;
}

int _alphaAt(Uint8List pixels, int size, double dx, double dy) {
  final int? at = _offsetAt(size, dx, dy);
  return at == null ? 0 : pixels[at + 3];
}

/// Whether a pixel is clearly not background (any non-zero alpha).
bool _visible(Uint8List pixels, int size, double dx, double dy) =>
    _alphaAt(pixels, size, dx, dy) > 10;

/// Peak alpha within a small window (anti-aliased thin strokes).
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

// A peer lantern position for a pinned slot, computed the same way the
// painter does (bearings come from RadarLayout, then radius by ring).
Offset _slotCenter(int size, RadarSlot slot) {
  final double maxR = size * 0.42;
  final double radius = maxR * (slot.innerRing ? 0.55 : 0.78);
  return Offset(
    size / 2 + math.cos(slot.angle) * radius,
    size / 2 + math.sin(slot.angle) * radius,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const int size = 300;

  group('MeshOrbitPainter', () {
    test('asleep map draws only hairlines and a dim self', () async {
      final Uint8List pixels = await _render(
        size,
        _snap(bleOn: false, scanning: false),
      );
      // Centre self lantern is still visible but nothing else is claimed.
      expect(
          _peakAlpha(pixels, size, dx: size / 2, dy: size / 2), greaterThan(0));
      // No reach rings, no lanterns where a peer would sit.
      expect(
          _peakAlpha(pixels, size,
              dx: size / 2 + 100, dy: size / 2, radius: 2.0),
          lessThan(120));
      // The outermost ring (0.78 factor) sits well inside the canvas.
      expect(_visible(pixels, size, size / 2, size / 2 - size * 0.42 * 0.78),
          isTrue);
    });

    test('a linked peer lantern sits on the inner ring and links to centre',
        () async {
      final RadarPeer peer = RadarPeer(peer: _peer('linked'), linked: true);
      final Uint8List pixels =
          await _render(size, _snap(peers: <RadarPeer>[peer]));
      final RadarSlot slot = RadarLayout.arrange(<RadarPeer>[peer]).single;
      final Offset pos = _slotCenter(size, slot);
      // The lantern itself (filled disc) is strongly visible.
      expect(
          _peakAlpha(pixels, size, dx: pos.dx, dy: pos.dy), greaterThan(200));
      // The link line back to self crosses the inner ring region.
      final Offset mid =
          Offset((pos.dx + size / 2) / 2, (pos.dy + size / 2) / 2);
      expect(_peakAlpha(pixels, size, dx: mid.dx, dy: mid.dy), greaterThan(0));
    });

    test('an away peer sits on the outer ring, further from self', () async {
      final RadarPeer away = RadarPeer(peer: _peer('away'), linked: false);
      final Uint8List pixels =
          await _render(size, _snap(peers: <RadarPeer>[away]));
      final RadarSlot slot = RadarLayout.arrange(<RadarPeer>[away]).single;
      final Offset pos = _slotCenter(size, slot);
      expect(_peakAlpha(pixels, size, dx: pos.dx, dy: pos.dy), greaterThan(60));
    });

    test('reach rings stay inside the map edge', () async {
      final RadarPeer linked = RadarPeer(peer: _peer('r'), linked: true);
      final Uint8List pixels = await _render(
        size,
        _snap(relay: true, peers: <RadarPeer>[linked]),
      );
      // The outermost reach ring (hop 2 → factor 0.90+0.05 = 0.95) must sit
      // strictly inside the canvas: sample just inside the edge on the
      // horizontal axis at the reach ring radius.
      final double reachRadius = size * 0.42 * (0.90 + 0.05);
      expect(_visible(pixels, size, size / 2 + reachRadius, size / 2), isTrue);
      // And nothing is painted at the very corner — no overflow bleed.
      expect(_visible(pixels, size, 6, 6), isFalse);
      expect(_visible(pixels, size, size - 6, size - 6), isFalse);
    });

    test('a scanning, empty map shows the listening ping but no lanterns',
        () async {
      final Uint8List pixels =
          await _render(size, _snap(scanning: true, peers: <RadarPeer>[]));
      // The ping ring mid-flight (pulse 0.5 → radius 0.12+0.39 factors).
      final double pingRadius = size * 0.42 * (0.12 + 0.78 * 0.5);
      expect(
          _peakAlpha(pixels, size,
              dx: size / 2 + pingRadius, dy: size / 2, radius: 2.0),
          greaterThan(0));
      // The self lantern is awake at centre.
      expect(_peakAlpha(pixels, size, dx: size / 2, dy: size / 2),
          greaterThan(100));
    });
  });
}
