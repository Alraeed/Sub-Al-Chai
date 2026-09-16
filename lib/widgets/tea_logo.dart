import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../theme/app_palette.dart';

/// The صب الجاي mark: a warm chat bubble that doubles as a cup of tea, with
/// three curls of steam rising off it.
///
/// The geometry is authored in a 64×64 design space (the same space as the
/// brand source) and scaled onto the widget, so the silhouette is faithful at
/// every size. Steam animates slowly and is frozen when the platform asks for
/// reduced motion.
class TeaLogo extends StatefulWidget {
  const TeaLogo({
    super.key,
    this.size = 128,
    this.steam = true,
    this.semanticLabel = AppStrings.appName,
  });

  /// Side length of the square the mark is painted into.
  final double size;

  /// Draw the three steam curls at all (off for tiny inline marks).
  final bool steam;

  /// Accessibility label; pass an empty string when the mark sits next to the
  /// app name and would only duplicate it for screen readers.
  final String semanticLabel;

  @override
  State<TeaLogo> createState() => _TeaLogoState();
}

class _TeaLogoState extends State<TeaLogo> with SingleTickerProviderStateMixin {
  /// One steam cycle — the CSS source staggers the three curls by 0.55 s
  /// inside a 2.6 s loop, which is the rhythm reproduced here.
  static const Duration _cycle = Duration(milliseconds: 2600);
  static const double _staggerFraction = 0.55 / 2.6;

  late final AnimationController _steam;
  bool _animate = false;

  @override
  void initState() {
    super.initState();
    _steam = AnimationController(vsync: this, duration: _cycle);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect the OS "reduce motion" setting: the mark still reads, it just
    // stops moving.
    final bool wantAnimation =
        widget.steam && !MediaQuery.disableAnimationsOf(context);
    if (wantAnimation == _animate) {
      return;
    }
    _animate = wantAnimation;
    if (_animate) {
      _steam.repeat();
    } else {
      _steam.stop();
      _steam.value = 0;
    }
  }

  @override
  void didUpdateWidget(covariant TeaLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.steam != widget.steam) {
      final bool wantAnimation =
          widget.steam && !MediaQuery.disableAnimationsOf(context);
      _animate = wantAnimation;
      if (_animate) {
        _steam.repeat();
      } else {
        _steam.stop();
        _steam.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _steam.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget mark = SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _steam,
        builder: (BuildContext context, Widget? _) {
          return CustomPaint(
            size: Size.square(widget.size),
            painter: TeaLogoPainter(
              steamPhase: _animate ? _steam.value : null,
              steam: widget.steam,
              stagger: _staggerFraction,
            ),
          );
        },
      ),
    );

    if (widget.semanticLabel.isEmpty) {
      return ExcludeSemantics(child: mark);
    }
    return Semantics(
      image: true,
      label: widget.semanticLabel,
      child: mark,
    );
  }
}

/// Paints the mark in its native 64×64 design space and scales it onto the
/// widget, so the silhouette is exact at any size.
///
/// [steamPhase] is `null` to freeze the curls at rest; otherwise it is a 0..1
/// position inside the steam loop.
class TeaLogoPainter extends CustomPainter {
  TeaLogoPainter({
    required this.steamPhase,
    this.steam = true,
    this.stagger = 0.55 / 2.6,
  });

  final double? steamPhase;
  final bool steam;
  final double stagger;

  /// Side of the design grid the geometry is authored against.
  static const double designSide = 64;

  // ------------------------------------------------------------- geometry
  // Every number here comes straight from the brand source: a 64×64 grid,
  // 3-unit strokes, round caps and joins.

  /// Cup + chat-bubble silhouette (open tail included) as one closed path, so
  /// no seam is stroked across the mouth of the tail.
  static final Path _cup = Path()
    ..moveTo(10, 24)
    ..lineTo(42, 24)
    ..arcToPoint(const Offset(46, 28), radius: const Radius.circular(4))
    ..lineTo(46, 41)
    ..arcToPoint(const Offset(37, 50), radius: const Radius.circular(9))
    ..lineTo(23, 50)
    ..lineTo(14, 58)
    ..lineTo(14, 50)
    ..lineTo(12, 50)
    ..arcToPoint(const Offset(8, 46), radius: const Radius.circular(4))
    ..lineTo(8, 28)
    ..arcToPoint(const Offset(10, 24), radius: const Radius.circular(4))
    ..close();

  /// Handle loop on the right side of the cup.
  static final Path _handle = Path()
    ..moveTo(46, 30)
    ..cubicTo(52.5, 30.6, 54.5, 33.2, 54.5, 36.4)
    ..cubicTo(54.5, 39.6, 52.5, 43.6, 46, 44);

  /// The tea line across the cup mouth.
  static final Path _liquid = Path()
    ..moveTo(14, 32)
    ..lineTo(42, 32);

  /// Three steam curls, each starting seven units above the rim.
  static final List<Path> _curls = List<Path>.generate(3, (int i) {
    final double x = 20 + i * 8;
    return Path()
      ..moveTo(x, 17)
      ..cubicTo(x - 3.2, 14.4, x + 2.6, 12.6, x - 0.6, 9.6);
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double side = size.shortestSide;
    if (side <= 0) {
      return;
    }
    canvas.save();
    canvas.scale(side / designSide);

    if (steam) {
      _paintSteam(canvas);
    }

    final Paint gold = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = AppPalette.gold;

    // Lapis fill keeps the mark legible on the dark ground; the gold hairline
    // then draws the outline, the handle, and the tea line on top.
    canvas.drawPath(_cup, Paint()..color = AppPalette.lapisHigh);
    canvas.drawPath(_cup, gold);
    canvas.drawPath(_handle, gold);
    canvas.drawPath(
      _liquid,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = AppPalette.goldLight.withValues(alpha: 0.55),
    );

    canvas.restore();
  }

  /// Curls rise and fade on a stagger, matching the source's 2.6 s loop.
  void _paintSteam(Canvas canvas) {
    final double? phase = steamPhase;
    for (int i = 0; i < _curls.length; i++) {
      final Path curl = _curls[i];
      if (phase == null) {
        canvas.drawPath(curl, _steamPaint(0.5));
        continue;
      }
      final double t = (phase + i * stagger) % 1.0;
      final double rise = Curves.easeOut.transform(t) * 3.6;
      final double fade = t < 0.08 ? t / 0.08 : 1 - (t - 0.08) / 0.92;
      final double alpha = 0.75 * fade.clamp(0.0, 1.0);
      if (alpha <= 0.01) {
        continue;
      }
      canvas.save();
      canvas.translate(0, -rise);
      canvas.drawPath(curl, _steamPaint(alpha));
      canvas.restore();
    }
  }

  Paint _steamPaint(double alpha) {
    return Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color = AppPalette.goldLight.withValues(alpha: alpha);
  }

  @override
  bool shouldRepaint(covariant TeaLogoPainter oldDelegate) {
    return oldDelegate.steamPhase != steamPhase ||
        oldDelegate.steam != steam ||
        oldDelegate.stagger != stagger;
  }
}
