import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// The صب الجاي logo: a warm chat bubble that doubles as a cup of tea,
/// steam rising from it. Painted layers:
///   1. oversized steam curl (ivory, translucent),
///   2. cup/chatbox body (lapis), gold hairline seam,
///   3. gold plinth under the cup.
class TeaLogo extends StatelessWidget {
  const TeaLogo({super.key, this.size = 128});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _TeaLogoPainter(),
    );
  }
}

class _TeaLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.shortestSide;
    final Offset center = Offset(size.width / 2, size.height / 2);

    final Paint steamPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.045
      ..color = AppPalette.goldLight.withValues(alpha: 0.55)
      ..strokeCap = StrokeCap.round;

    final Paint bodyPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = AppPalette.lapisHigh;

    final Paint goldPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.035
      ..color = AppPalette.gold;

    // Steam — two graceful curls above the cup.
    final Path steamPath = Path();
    final double steamX = center.dx - s * 0.10;
    final double steamBaseY = center.dy - s * 0.34;
    steamPath.moveTo(steamX, steamBaseY);
    steamPath.quadraticBezierTo(
      steamX - s * 0.12,
      steamBaseY - s * 0.14,
      steamX + s * 0.02,
      steamBaseY - s * 0.24,
    );
    steamPath.quadraticBezierTo(
      steamX + s * 0.14,
      steamBaseY - s * 0.34,
      steamX + s * 0.02,
      steamBaseY - s * 0.46,
    );
    canvas.drawPath(steamPath, steamPaint);

    // Cup = rounded chat bubble with a tail on the lower-left.
    final double cupW = s * 0.62;
    final double cupH = s * 0.46;
    final Rect cupRect = Rect.fromCenter(
      center: center.translate(0, s * 0.16),
      width: cupW,
      height: cupH,
    );
    final RRect cup = RRect.fromRectAndCorners(
      cupRect,
      topLeft: Radius.circular(s * 0.16),
      topRight: Radius.circular(s * 0.16),
      bottomLeft: Radius.circular(s * 0.12),
      bottomRight: Radius.circular(s * 0.16),
    );
    canvas.drawRRect(cup, bodyPaint);
    canvas.drawRRect(cup, goldPaint);

    // Bubble tail — small speech pointer.
    final Path tail = Path();
    final double tailX = cupRect.left + s * 0.10;
    final double tailY = cupRect.bottom - s * 0.02;
    tail.moveTo(tailX, tailY);
    tail.lineTo(tailX - s * 0.06, tailY + s * 0.10);
    tail.lineTo(tailX + s * 0.12, tailY + s * 0.01);
    tail.close();
    canvas.drawPath(tail, bodyPaint);
    canvas.drawPath(tail, goldPaint);

    // A saucer/gold line across the cup mouth + vertical tea line.
    canvas.drawLine(
      Offset(cupRect.left + s * 0.06, cupRect.top + s * 0.16),
      Offset(cupRect.left + s * 0.06, cupRect.bottom - s * 0.08),
      goldPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}