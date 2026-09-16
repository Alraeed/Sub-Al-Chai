import 'package:flutter/material.dart';

import 'app_palette.dart';

/// Typography + Material theme for صب الجاي.
/// Reem Kufi (display / Kufic-inspired, geometric) + Aref Ruqaa (accent).
abstract final class AppTypography {
  static const String appFont = 'Parastoo';
  static const String arefRuqaa = 'ArefRuqaa';

  /// Kufic-inspired display face declared in `pubspec.yaml`; used for the
  /// brand lockup, where the geometric letterforms carry the mark.
  static const String reemKufi = 'ReemKufi';
}

class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(Brightness.light);

  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: AppPalette.gold,
      brightness: brightness,
    ).copyWith(
      primary: AppPalette.gold,
      onPrimary: AppPalette.ground,
      secondary: AppPalette.brass,
      onSecondary: AppPalette.ivory,
      error: AppPalette.pomegranate,
      onError: AppPalette.ivory,
      surface: AppPalette.lapisMid,
      onSurface: AppPalette.ivory,
      surfaceContainerHighest: AppPalette.lapisHigh,
      outline: AppPalette.brass,
    );

    final ThemeData base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppPalette.ground,
      fontFamily: AppTypography.appFont,
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        displayLarge: _display(28, bold: true),
        displayMedium: _display(24, bold: true),
        headlineLarge: _display(22, bold: true),
        headlineMedium: _display(20, bold: true),
        headlineSmall: _display(18, bold: true),
        titleLarge: _display(17),
        titleMedium: _display(15),
        titleSmall: _display(13),
        bodyLarge: const TextStyle(
          fontFamily: AppTypography.appFont,
          fontSize: 16,
          height: 1.5,
          color: AppPalette.ivory,
        ),
        bodyMedium: const TextStyle(
          fontFamily: AppTypography.appFont,
          fontSize: 14,
          height: 1.5,
          color: AppPalette.ivory,
        ),
        bodySmall: const TextStyle(
          fontFamily: AppTypography.appFont,
          fontSize: 12,
          height: 1.4,
          color: AppPalette.ivoryDim,
        ),
        labelLarge: const TextStyle(
          fontFamily: AppTypography.appFont,
          fontSize: 14,
          letterSpacing: 0.2,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        foregroundColor: AppPalette.ivory,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: _goldButtonStyle(),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppPalette.gold,
          side: const BorderSide(color: AppPalette.brass, width: 1.2),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          textStyle: const TextStyle(
            fontFamily: AppTypography.appFont,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
      ),
      iconTheme: const IconThemeData(color: AppPalette.goldLight),
      dividerTheme: const DividerThemeData(
        color: AppPalette.dividerGold,
        thickness: 0.6,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppPalette.lapisMid,
        hintStyle: const TextStyle(color: AppPalette.ivoryDim),
        labelStyle: const TextStyle(color: AppPalette.goldLight),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppPalette.brass, width: 0.8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppPalette.gold, width: 1.1),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppPalette.pomegranate),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppPalette.pomegranate),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppPalette.lapisHigh,
        contentTextStyle: const TextStyle(
          fontFamily: AppTypography.appFont,
          color: AppPalette.ivory,
          fontSize: 14,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppPalette.dividerGold),
        ),
      ),
    );
  }

  static TextStyle _display(double size, {bool bold = false}) {
    return TextStyle(
      fontFamily: AppTypography.appFont,
      fontSize: size,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
      color: AppPalette.ivory,
    );
  }

  static ButtonStyle _goldButtonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: AppPalette.gold,
      foregroundColor: AppPalette.ground,
      disabledBackgroundColor: AppPalette.brass.withValues(alpha: 0.5),
      disabledForegroundColor: AppPalette.ivoryDim,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
      textStyle: const TextStyle(
        fontFamily: AppTypography.appFont,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    );
  }
}
