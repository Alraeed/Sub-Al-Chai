import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import 'avatars.dart';
import 'tea_logo.dart';

/// The صب الجاي lockup: cup mark, Arabic name, a gold seam, and the Latin
/// brand line beneath it.
///
/// The vertical rhythm lives here rather than in call-site padding, so the
/// Arabic and English lines always read as one intentional mark — the Arabic
/// run stays right-to-left and the Latin run stays left-to-right no matter
/// which direction the surrounding app is laid out in.
class TeaWordmark extends StatelessWidget {
  const TeaWordmark({
    super.key,
    this.markSize = 96,
    this.arabicName = AppStrings.appName,
    this.latinName = AppStrings.appNameLatin,
    this.tagline,
    this.steam = true,
  });

  /// Side length of the cup mark.
  final double markSize;

  /// Display name — always laid out right-to-left.
  final String arabicName;

  /// Latin brand line — always laid out left-to-right.
  final String latinName;

  /// Optional Arabic tagline beneath the Latin line.
  final String? tagline;

  /// Animate the steam curls where the platform allows it.
  final bool steam;

  // ---------------------------------------------------------------- rhythm
  /// Mark → Arabic name.
  static const double markGap = 14;

  /// Arabic name → gold seam.
  static const double arabicToSeam = 16;

  /// The seam's own height (the divider's default height, pinned).
  static const double seamHeight = 16;

  /// Gold seam → Latin line.
  static const double seamToLatin = 14;

  /// Latin line → Arabic tagline.
  static const double latinToTagline = 14;

  /// Total vertical space the lockup gives the Arabic→English step. This is
  /// the relationship the lockup is built around: one deliberate step, not
  /// two accidental paddings.
  static const double arabicToLatin = arabicToSeam + seamHeight + seamToLatin;

  @override
  Widget build(BuildContext context) {
    final String? sub = tagline;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        // The name sits immediately beside the mark, so the mark itself stays
        // silent for screen readers instead of announcing the name twice.
        TeaLogo(size: markSize, steam: steam, semanticLabel: ''),
        const SizedBox(height: markGap),
        Text(
          arabicName,
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
          style: const TextStyle(
            fontFamily: AppTypography.reemKufi,
            fontSize: 34,
            height: 1.15,
            color: AppPalette.goldLight,
          ),
        ),
        const SizedBox(height: arabicToSeam),
        const SizedBox(
          height: seamHeight,
          child: GoldRuleDivider(),
        ),
        const SizedBox(height: seamToLatin),
        Text(
          latinName,
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
          style: const TextStyle(
            fontFamily: AppTypography.appFont,
            fontSize: 13,
            height: 1.2,
            letterSpacing: 2.6,
            color: AppPalette.ivoryDim,
          ),
        ),
        if (sub != null && sub.isNotEmpty) ...<Widget>[
          const SizedBox(height: latinToTagline),
          Text(
            sub,
            textAlign: TextAlign.center,
            // Follow the active language, so an English tagline reads LTR.
            textDirection:
                AppStrings.isArabic ? TextDirection.rtl : TextDirection.ltr,
            style: const TextStyle(
              fontFamily: AppTypography.appFont,
              fontSize: 14,
              height: 1.35,
              color: AppPalette.ivory,
            ),
          ),
        ],
      ],
    );
  }
}
