import 'package:flutter/material.dart';

/// صب الجاي — "Ishtar Lapis" palette.
/// Cool lapis stone, antique gold leaf, warm lantern highlights.
abstract final class AppPalette {
  // Ground — deep royal lapis lazuli.
  static const Color ground = Color(0xFF0a1120);

  // Layered stone surfaces.
  static const Color lapisMid = Color(0xFF0f1a2e);
  static const Color lapisHigh = Color(0xFF16243c);

  // Antique gold leaf (primary accent).
  static const Color gold = Color(0xFFc9a44c);
  // Gold light — warm shimmer highlights.
  static const Color goldLight = Color(0xFFe6d3a3);
  // Burnished brass (secondary).
  static const Color brass = Color(0xFF9a7b45);

  // Glazed ceramic turquoise — success.
  static const Color turquoise = Color(0xFF3f9c93);
  // Pomegranate — error / accent.
  static const Color pomegranate = Color(0xFF9d2b3f);

  // Carved alabaster ivory — body text.
  static const Color ivory = Color(0xFFefe6d6);

  static const Color ivoryDim = Color(0xFFb9ae99);
  static const Color dividerGold = Color(0x33c9a44c);

  /// Ambient lapis-to-lapis radial gradient used behind screens;
  /// warm lantern node in the centre, never a cheap glow halo.
  static const RadialGradient ambientGradient = RadialGradient(
    center: Alignment(0.0, -0.35),
    radius: 1.3,
    stops: [0.0, 0.55, 1.0],
    colors: [lapisHigh, lapisMid, ground],
  );
}