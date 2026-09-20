import 'package:flutter/material.dart';

final class ExampleTheme {
  ExampleTheme._();

  static const Color background = Color(0xFFFFF8E8);
  static const Color primary = Color(0xFF35675C);
  static const Color foreground = Colors.white;
  static const Color textPrimary = Color(0xFF45433F);
  static const Color textSecondary = Color(0xFF625F59);
  static const Color textHint = Color(0xFF716E67);
  static const Color brandText = Color(0xFF514F4A);
  static const Color videoBackground = Color(0xFF252525);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF3EEDF);
  static const Color sectionSurface = Color(0xFFF6F1E6);
  static const Color controlSurface = Color(0xE61B2523);
  static const Color inputSurface = surface;
  static const Color inputBorder = Color(0xFFE1DBCF);
  static const double inputControlHeight = 56;
  static const double radiusSmall = 8;
  static const double radiusMedium = 12;
  static const double radiusLarge = 16;
  static const double space4 = 4;
  static const double space8 = 8;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space24 = 24;
  static const double compactBreakpoint = 600;
  static const double formWideBreakpoint = 840;
  static const double materialTargetSize = 48;
  static const double appleTargetSize = 44;
  static const double inputRadius = radiusMedium;
  static const TextStyle inputTextStyle = TextStyle(fontSize: 13);
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
        headlineLarge: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: textPrimary, letterSpacing: 0),
        headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: textPrimary),
        titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary),
        bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: textPrimary),
        bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: textSecondary),
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
        hintStyle: const TextStyle(color: textSecondary, fontSize: 12, height: 1.35),
        labelStyle: const TextStyle(color: textSecondary, fontSize: 14, height: 1.0, fontWeight: FontWeight.w500),
        floatingLabelStyle: const TextStyle(
          color: textSecondary,
          fontSize: 14,
          height: 1.0,
          fontWeight: FontWeight.w500,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(radiusMedium), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: const BorderSide(color: inputBorder),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: BorderSide(color: inputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: const BorderSide(color: primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: const BorderSide(color: failure),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: const BorderSide(color: failure, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: foreground,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMedium)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          backgroundColor: foreground.withAlpha(230),
          side: BorderSide(color: primary.withAlpha(46)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMedium)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: textPrimary,
        contentTextStyle: const TextStyle(color: foreground),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSmall)),
      ),
    );
  }

  static BoxDecoration get surfaceDecoration => BoxDecoration(
    color: surface.withAlpha(224),
    borderRadius: BorderRadius.circular(radiusLarge),
    border: Border.all(color: primary.withAlpha(31)),
    boxShadow: <BoxShadow>[BoxShadow(color: primary.withAlpha(18), blurRadius: 18, offset: const Offset(0, 10))],
  );

  static BoxDecoration get formSectionDecoration => BoxDecoration(
    color: sectionSurface,
    borderRadius: BorderRadius.circular(radiusLarge),
    boxShadow: <BoxShadow>[BoxShadow(color: primary.withAlpha(12), blurRadius: 12, offset: const Offset(0, 4))],
  );

  static BoxDecoration get pageBackgroundDecoration => const BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[Color(0xFFFFF8E8), Color(0xFFFBF4E5), Color(0xFFFFF8E8)],
    ),
  );

  static BoxDecoration get videoPanelDecoration => BoxDecoration(
    color: Colors.black.withAlpha(117),
    borderRadius: BorderRadius.circular(radiusLarge),
    border: Border.all(color: Colors.white.withAlpha(20)),
  );

  static bool isAppleProfile(BuildContext context) {
    final TargetPlatform platform = Theme.of(context).platform;
    return platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
  }

  static double minimumTargetSize(BuildContext context) =>
      isAppleProfile(context) ? appleTargetSize : materialTargetSize;
}
