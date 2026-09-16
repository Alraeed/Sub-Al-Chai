import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../screens/radar/radar_model.dart';
import '../theme/app_palette.dart';

/// The neighborhood map — warm, human, and honest about what it knows.
///
/// It draws four things and nothing else:
///  * the self lantern at the centre,
///  * a lantern per peer: inner ring when we hold a live link, outer ring when
///    we only know the peer from before,
///  * one dashed ring per extra hop of *potential* broadcast reach, and only
///    while relaying is on — always inside the map's edge, never beyond it,
///  * while discovery is running, a faint rotating sweep, plus an expanding
///    "listening" ping when nobody is home yet — a quiet map that is still
///    awake reads as active, not broken.
///
/// Bearings come from [RadarLayout], so lanterns keep their place while peers
/// come and go. With the radio off the map is drawn asleep: hairlines only.
class MeshOrbitPainter extends CustomPainter {
  MeshOrbitPainter({required this.snapshot, required this.pulse});

  final RadarSnapshot snapshot;

  /// 0..1 breathing position; ignored while the radio is off.
  final double pulse;

  static const double _selfRadius = 17;
  static const double _linkedRadiusFactor = 0.55;
  static const double _awayRadiusFactor = 0.78;

  /// Reach rings live between the "away" ring and the map edge, so the outer
  /// bound reads as the horizon of *possible* reach — never a measured place.
  static const double _reachStartFactor = 0.90;
  static const double _reachStepFactor = 0.05;

  @override
  void paint(Canvas canvas, Size size) {
    final double side = size.shortestSide;
    if (side <= 0) {
      return;
    }
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double maxR = side * 0.42;
    final bool live = snapshot.bleOn;
    final double breath = live ? pulse : 0;

    final Paint hairline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = AppPalette.dividerGold;
    final Paint dormantHairline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = AppPalette.dividerGold.withValues(alpha: 0.12);

    canvas.drawCircle(
      center,
      maxR * _linkedRadiusFactor,
      live ? hairline : dormantHairline,
    );
    canvas.drawCircle(
      center,
      maxR * _awayRadiusFactor,
      live ? hairline : dormantHairline,
    );

    if (!live) {
      // Asleep: the centre stays, nothing else is claimed.
      _paintSelf(canvas, center, breath, dim: true);
      return;
    }

    // While discovery runs, show that we are listening. The sweep is one
    // gentle rotation per pulse cycle; the ping only appears when the map is
    // empty so an empty-but-awake radar does not read as dead.
    if (snapshot.scanning) {
      _paintSweep(canvas, center, maxR, breath);
      if (!snapshot.anyPeer) {
        _paintListeningPing(canvas, center, maxR, breath);
      }
    }

    if (snapshot.anyPeer) {
      canvas.drawCircle(
        center,
        maxR * (0.5 + 0.08 * breath),
        Paint()
          ..color = AppPalette.gold.withValues(alpha: 0.04 + 0.07 * breath),
      );
    }

    final int extraHops = snapshot.reachHops - 1;
    if (extraHops > 0) {
      final Paint reach = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = AppPalette.gold.withValues(alpha: 0.22);
      for (int hop = 1; hop <= extraHops; hop++) {
        _dashedCircle(
          canvas,
          center,
          maxR * (_reachStartFactor + _reachStepFactor * (hop - 1)),
          reach,
        );
      }
    }

    for (final RadarSlot slot in RadarLayout.arrange(snapshot.peers)) {
      _paintLantern(canvas, center, maxR, slot, breath);
    }

    _paintSelf(canvas, center, breath, dim: false);
  }

  /// A faint arc rotating once per pulse cycle — "we are listening".
  void _paintSweep(Canvas canvas, Offset center, double maxR, double t) {
    // Two laps per pulse cycle so the sweep never visibly snaps back: the
    // cycle restarts at 0 but the arc keeps turning the other way.
    final double angle = -math.pi / 2 + t * 4 * math.pi;
    const double sweep = 0.55;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: maxR * _reachStartFactor),
      angle - sweep / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..strokeCap = StrokeCap.round
        ..color = AppPalette.turquoise.withValues(alpha: 0.16),
    );
  }

  /// An expanding ring from the centre that fades out — nobody here yet, but
  /// the radio is reaching out.
  void _paintListeningPing(
      Canvas canvas, Offset center, double maxR, double t) {
    final double radius = maxR * (0.12 + 0.78 * t);
    final double alpha = 0.12 * (1 - t);
    if (alpha <= 0.01) {
      return;
    }
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = AppPalette.gold.withValues(alpha: alpha),
    );
  }

  void _paintLantern(
    Canvas canvas,
    Offset center,
    double maxR,
    RadarSlot slot,
    double breath,
  ) {
    final double radius =
        maxR * (slot.innerRing ? _linkedRadiusFactor : _awayRadiusFactor);
    final Offset pos = center +
        Offset(
          math.cos(slot.angle) * radius,
          math.sin(slot.angle) * radius,
        );

    // Link line back to us — solid for a live link, faint for a memory.
    canvas.drawLine(
      pos,
      center,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = slot.innerRing ? 0.9 : 0.6
        ..color = slot.innerRing
            ? AppPalette.turquoise.withValues(alpha: 0.45)
            : AppPalette.brass.withValues(alpha: 0.30),
    );

    final double dot =
        (slot.innerRing ? 8.5 : 6.5) + (slot.innerRing ? breath * 1.2 : 0);
    final Paint fill = Paint()
      ..color = slot.innerRing
          ? AppPalette.turquoise
          : AppPalette.brass.withValues(alpha: 0.65);
    canvas.drawCircle(pos, dot, fill);
    canvas.drawCircle(
      pos,
      dot,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = slot.innerRing ? 1.6 : 1.2
        ..color = slot.innerRing
            ? AppPalette.goldLight.withValues(alpha: 0.85)
            : AppPalette.goldLight.withValues(alpha: 0.30),
    );
  }

  void _paintSelf(
    Canvas canvas,
    Offset center,
    double breath, {
    required bool dim,
  }) {
    final double r = _selfRadius + 2 * breath;
    final double alpha = dim ? 0.45 : 1.0;
    canvas.drawCircle(
      center,
      r,
      Paint()..color = AppPalette.lapisMid.withValues(alpha: alpha),
    );
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..color = AppPalette.gold.withValues(alpha: alpha),
    );
    canvas.drawCircle(
      center,
      5,
      Paint()..color = AppPalette.goldLight.withValues(alpha: alpha),
    );
  }

  /// A circle drawn as short arcs, so reach reads as a bound rather than a
  /// measured distance.
  void _dashedCircle(Canvas canvas, Offset center, double radius, Paint paint) {
    const int segments = 18;
    final Rect bounds = Rect.fromCircle(center: center, radius: radius);
    const double sweep = (2 * math.pi) / segments;
    for (int i = 0; i < segments; i++) {
      canvas.drawArc(bounds, i * sweep, sweep * 0.45, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant MeshOrbitPainter oldDelegate) {
    return oldDelegate.snapshot != snapshot || oldDelegate.pulse != pulse;
  }
}
