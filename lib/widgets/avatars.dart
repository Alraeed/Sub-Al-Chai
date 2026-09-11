import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// A peer avatar: carved-stone disc, gold hairline ring, one initial glyph.
class PeerAvatar extends StatelessWidget {
  const PeerAvatar({super.key, required this.label, this.radius = 22});

  final String label;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final String initial = label.trim().isEmpty
        ? '؟'
        : String.fromCharCode(label.trim().runes.first);
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[AppPalette.lapisHigh, AppPalette.lapisMid],
        ),
        border: Border.all(
          color: AppPalette.gold.withValues(alpha: 0.85),
          width: 1.2,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          fontFamily: 'Parastoo',
          fontSize: radius * 0.9,
          color: AppPalette.goldLight,
        ),
      ),
    );
  }
}

/// A hairline "rule-gold" divider with two corner ticks — the antique-gold
/// visual seam used between sections.
class GoldRuleDivider extends StatelessWidget {
  const GoldRuleDivider({super.key, this.thickness = 0.8, this.margin = 4});

  final double thickness;
  final double margin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: margin),
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Divider(thickness: thickness, color: AppPalette.dividerGold),
          // tiny gold diamond at the middle of the rule
          Transform.rotate(
            angle: 0.7854,
            child: Container(
              width: 5,
              height: 5,
              color: AppPalette.gold,
            ),
          ),
        ],
      ),
    );
  }
}
