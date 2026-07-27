import 'package:flutter/material.dart';

final class ExampleTheme {
  ExampleTheme._();

  static const Color background = Color(0xFFFFF8E8);
  static const Color primary = Color(0xFF659287);
  static const Color foreground = Colors.white;
  static const Color textPrimary = Color(0xFF666666);
  static const Color textSecondary = Color(0xFF848282);
  static const Color textHint = Color(0xFFB3B3B3);
  static const Color brandText = Color(0xFF767676);
  static const Color videoBackground = Color(0xFF252525);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color inputSurface = surface;
  static const Color inputBorder = Color(0xFFE1DBCF);
  static const Color overlayGlow = Color(0x14659287);
  static const Color overlayShadow = Color(0x0DE7D9B7);
  static const Color failure = Color(0xFFB42318);

  static ThemeData build() {
    const ColorScheme colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: primary,
      onPrimary: foreground,
      secondary: primary,
      onSecondary: foreground,
      error: failure,
      onError: foreground,
      surface: background,
      onSurface: textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: 0,
        ),
        headlineSmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          height: 1.5,
          color: textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          height: 1.5,
          color: textSecondary,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: primary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputSurface,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        hintStyle: const TextStyle(
          color: textSecondary,
          fontSize: 12,
          height: 1.35,
        ),
        labelStyle: const TextStyle(
          color: textSecondary,
          fontSize: 14,
          height: 1.0,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: const TextStyle(
          color: textSecondary,
          fontSize: 14,
          height: 1.0,
          fontWeight: FontWeight.w500,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: failure),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: failure, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: foreground,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          backgroundColor: foreground.withAlpha(230),
          side: BorderSide(color: primary.withAlpha(46)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: textPrimary,
        contentTextStyle: const TextStyle(color: foreground),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }

  static BoxDecoration get surfaceDecoration => BoxDecoration(
        color: surface.withAlpha(224),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: primary.withAlpha(31)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: primary.withAlpha(18),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      );

  static BoxDecoration get pageBackgroundDecoration => const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0xFFFFF8E8),
            Color(0xFFFBF4E5),
            Color(0xFFFFF8E8),
          ],
        ),
      );

  static BoxDecoration get videoPanelDecoration => BoxDecoration(
        color: Colors.black.withAlpha(117),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withAlpha(20)),
      );
}
