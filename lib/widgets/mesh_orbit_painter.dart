import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// Warm, human mesh radar — not a diagnostic console.
/// Concentric lapis rings with a slow gold pulse in the center and soft
/// turquoise "lantern" nodes for each online peer.
class MeshOrbitPainter extends CustomPainter {
  MeshOrbitPainter({
    required this.peerCount,
    required this.pulse,
  });

  final int peerCount;
  final double pulse; // 0..1 from the animation controller

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.shortestSide;
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double maxR = s * 0.44;

    // Outer hairlines.
    final Paint ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = AppPalette.dividerGold;
    for (final double r in <double>[maxR * 0.45, maxR * 0.72, maxR]) {
      canvas.drawCircle(center, r, ringPaint);
    }

    // A soft "lantern glow" that slowly breathes — warm, not neon.
    final Paint haloPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = AppPalette.gold.withValues(alpha: 0.05 + 0.08 * pulse);
    canvas.drawCircle(center, maxR * (0.5 + 0.1 * pulse), haloPaint);

    // Self node: gold ring with a minute pulse band.
    final Paint selfRing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..color = AppPalette.gold;
    canvas.drawCircle(center, 18 + 2 * pulse, selfRing);
    final Paint selfFill = Paint()..color = AppPalette.lapisMid;
    canvas.drawCircle(center, 18 + 2 * pulse, selfFill);
    final Paint selfCore = Paint()..color = AppPalette.goldLight;
    canvas.drawCircle(center, 5, selfCore);

    if (peerCount <= 0) {
      return;
    }

    // Peers as even-spaced turquoise lanterns around the center.
    final Paint nodePaint = Paint()..color = AppPalette.turquoise;
    final Paint nodeRing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = AppPalette.goldLight.withValues(alpha: 0.8);
    final double baseAngle = -math.pi / 2;
    final double pad = math.pi * 2 * 0.08;
    final double count = peerCount.toDouble();
    final double step = count > 1 ? (math.pi * 2 - pad) / count : 0;
    for (int i = 0; i < peerCount; i++) {
      final double angle = baseAngle + step * i;
      final double radius = maxR * 0.62 + 6 * math.sin(pulse * math.pi + i);
      final Offset pos = center +
          Offset(math.cos(angle) * radius, math.sin(angle) * radius);
      canvas.drawCircle(pos, 9, nodePaint);
      canvas.drawCircle(pos, 9, nodeRing);
      // Sparkle line toward center (lattice-weave feel).
      final Paint linkPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7
        ..color = AppPalette.turquoise.withValues(alpha: 0.45);
      canvas.drawLine(pos, center, linkPaint);
    }
  }

  @override
  bool shouldRepaint(covariant MeshOrbitPainter oldDelegate) {
    return oldDelegate.peerCount != peerCount || oldDelegate.pulse != pulse;
  }
}