import 'package:flutter/material.dart';

/// LoveLaundry strict five-colour design tokens.
///
/// Only the five base colours below (and opacity tints of them) are permitted.
/// The extra opaque greys are the light/dark semantic values required by the
/// design system; everything else in the app must resolve to one of these.
@immutable
class LLColors {
  const LLColors._();

  // The five permitted base colours.
  static const Color black = Color(0xFF000000);
  static const Color white = Color(0xFFFFFFFF);
  static const Color red = Color(0xFFFF0000);
  static const Color green = Color(0xFF008000);
  static const Color blue = Color(0xFF00008B);

  /// Fully transparent black — useful wherever Flutter needs "no colour".
  static const Color transparent = Color(0x00000000);

  // Semantic aliases.
  static const Color brand = blue;

  /// Blue mixed with black, the one explicitly allowed opaque shade.
  static const Color brandDark = Color(0xFF00005E);
  static const Color success = green;
  static const Color danger = red;

  // Light theme semantics.
  static const Color surface = white;
  static const Color canvas = Color(0xFFF2F2F2);
  static const Color textPrimary = black;
  static const Color textMuted = Color(0xFF767676);
  static const Color border = Color(0xFF242424);

  // Dark theme semantics.
  static const Color surfaceDark = Color(0xFF0A0A0A);
  static const Color canvasDark = black;
  static const Color textPrimaryDark = white;
  static const Color textMutedDark = Color(0xFFB3B3B3);
  static const Color borderDark = Color(0xFF3D3D3D);

  /// Resolve a semantic colour for the requested brightness.
  static Color forBrightness({
    required Brightness brightness,
    required Color light,
    required Color dark,
  }) =>
      brightness == Brightness.dark ? dark : light;

  // Opacity tints of the five bases. Kept as named constants so call sites
  // never invent a new hex value.
  static Color tint(Color base, double alpha) =>
      base.withValues(alpha: alpha);

  static const Color black02 = Color(0x05000000);
  static const Color black04 = Color(0x0A000000);
  static const Color black06 = Color(0x0F000000);
  static const Color black08 = Color(0x14000000);
  static const Color black10 = Color(0x1A000000);
  static const Color black16 = Color(0x29000000);
  static const Color black20 = Color(0x33000000);
  static const Color black30 = Color(0x4D000000);
  static const Color black40 = Color(0x66000000);
  static const Color black50 = Color(0x80000000);
  static const Color black60 = Color(0x99000000);
  static const Color black70 = Color(0xB3000000);
  static const Color black80 = Color(0xCC000000);
  static const Color black90 = Color(0xE6000000);
  static const Color white04 = Color(0x0AFFFFFF);
  static const Color white06 = Color(0x0FFFFFFF);
  static const Color white08 = Color(0x14FFFFFF);
  static const Color white10 = Color(0x1AFFFFFF);
  static const Color white16 = Color(0x29FFFFFF);
  static const Color white20 = Color(0x33FFFFFF);
  static const Color white30 = Color(0x4DFFFFFF);
  static const Color white40 = Color(0x66FFFFFF);
  static const Color white50 = Color(0x80FFFFFF);
  static const Color white70 = Color(0xB3FFFFFF);
  static const Color white80 = Color(0xCCFFFFFF);
  static const Color white90 = Color(0xE6FFFFFF);
  static const Color blue04 = Color(0x0D00008B);
  static const Color blue08 = Color(0x1400008B);
  static const Color blue12 = Color(0x1F00008B);
  static const Color blue20 = Color(0x3300008B);
  static const Color blue30 = Color(0x4D00008B);
  static const Color blue50 = Color(0x8000008B);
  static const Color red04 = Color(0x0DFF0000);
  static const Color red08 = Color(0x14FF0000);
  static const Color red20 = Color(0x33FF0000);
  static const Color red40 = Color(0x66FF0000);
  static const Color green04 = Color(0x0D008000);
  static const Color green08 = Color(0x14008000);
  static const Color green20 = Color(0x33008000);
  static const Color green40 = Color(0x66008000);
}

/// Canonical ThemeData objects built exclusively from the five colours.
///
/// Feature themes start from one of these and only overlay their semantic
/// [AppColors] extension and font-size-scaled text theme.
@immutable
class LLTheme {
  const LLTheme._();

  static const String fontFamily = 'Roboto';

  static const ColorScheme _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: LLColors.brand,
    onPrimary: LLColors.white,
    primaryContainer: LLColors.blue08,
    onPrimaryContainer: LLColors.brandDark,
    primaryFixed: LLColors.blue04,
    primaryFixedDim: LLColors.blue12,
    onPrimaryFixed: LLColors.brandDark,
    onPrimaryFixedVariant: LLColors.brandDark,
    secondary: LLColors.brandDark,
    onSecondary: LLColors.white,
    secondaryContainer: LLColors.blue08,
    onSecondaryContainer: LLColors.brandDark,
    secondaryFixed: LLColors.blue04,
    secondaryFixedDim: LLColors.blue12,
    onSecondaryFixed: LLColors.brandDark,
    onSecondaryFixedVariant: LLColors.brandDark,
    tertiary: LLColors.success,
    onTertiary: LLColors.white,
    tertiaryContainer: LLColors.green08,
    onTertiaryContainer: LLColors.green,
    tertiaryFixed: LLColors.green04,
    tertiaryFixedDim: LLColors.green20,
    onTertiaryFixed: LLColors.green,
    onTertiaryFixedVariant: LLColors.green,
    error: LLColors.danger,
    onError: LLColors.white,
    errorContainer: LLColors.red04,
    onErrorContainer: LLColors.red,
    surface: LLColors.surface,
    onSurface: LLColors.textPrimary,
    surfaceDim: LLColors.canvas,
    surfaceBright: LLColors.white,
    surfaceContainerLowest: LLColors.white,
    surfaceContainerLow: LLColors.canvas,
    surfaceContainer: LLColors.canvas,
    surfaceContainerHigh: LLColors.canvas,
    surfaceContainerHighest: LLColors.canvas,
    onSurfaceVariant: LLColors.textMuted,
    outline: LLColors.border,
    outlineVariant: LLColors.black20,
    shadow: LLColors.black,
    scrim: LLColors.black,
    inverseSurface: LLColors.black,
    onInverseSurface: LLColors.white,
    inversePrimary: LLColors.white,
    surfaceTint: LLColors.brand,
  );

  static const ColorScheme _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: LLColors.brand,
    onPrimary: LLColors.white,
    primaryContainer: LLColors.blue20,
    onPrimaryContainer: LLColors.white,
    primaryFixed: LLColors.blue20,
    primaryFixedDim: LLColors.blue30,
    onPrimaryFixed: LLColors.white,
    onPrimaryFixedVariant: LLColors.white,
    secondary: LLColors.brandDark,
    onSecondary: LLColors.white,
    secondaryContainer: LLColors.blue20,
    onSecondaryContainer: LLColors.white,
    secondaryFixed: LLColors.blue20,
    secondaryFixedDim: LLColors.blue30,
    onSecondaryFixed: LLColors.white,
    onSecondaryFixedVariant: LLColors.white,
    tertiary: LLColors.success,
    onTertiary: LLColors.white,
    tertiaryContainer: LLColors.green20,
    onTertiaryContainer: LLColors.white,
    tertiaryFixed: LLColors.green20,
    tertiaryFixedDim: LLColors.green40,
    onTertiaryFixed: LLColors.white,
    onTertiaryFixedVariant: LLColors.white,
    error: LLColors.danger,
    onError: LLColors.white,
    errorContainer: LLColors.red20,
    onErrorContainer: LLColors.white,
    surface: LLColors.surfaceDark,
    onSurface: LLColors.textPrimaryDark,
    surfaceDim: LLColors.canvasDark,
    surfaceBright: LLColors.surfaceDark,
    surfaceContainerLowest: LLColors.canvasDark,
    surfaceContainerLow: LLColors.surfaceDark,
    surfaceContainer: LLColors.surfaceDark,
    surfaceContainerHigh: LLColors.surfaceDark,
    surfaceContainerHighest: LLColors.surfaceDark,
    onSurfaceVariant: LLColors.textMutedDark,
    outline: LLColors.borderDark,
    outlineVariant: LLColors.white20,
    shadow: LLColors.black,
    scrim: LLColors.black,
    inverseSurface: LLColors.white,
    onInverseSurface: LLColors.black,
    inversePrimary: LLColors.white,
    surfaceTint: LLColors.brand,
  );

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        fontFamily: fontFamily,
        colorScheme: _lightScheme,
        scaffoldBackgroundColor: LLColors.canvas,
        canvasColor: LLColors.canvas,
        cardColor: LLColors.white,
        dividerColor: LLColors.black20,
        primaryColor: LLColors.brand,
        hintColor: LLColors.textMuted,
        splashColor: LLColors.black10,
        highlightColor: LLColors.black04,
        hoverColor: LLColors.black04,
        focusColor: LLColors.black08,
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: fontFamily,
        colorScheme: _darkScheme,
        scaffoldBackgroundColor: LLColors.canvasDark,
        canvasColor: LLColors.canvasDark,
        cardColor: LLColors.surfaceDark,
        dividerColor: LLColors.white20,
        primaryColor: LLColors.brand,
        hintColor: LLColors.textMutedDark,
        splashColor: LLColors.white10,
        highlightColor: LLColors.white04,
        hoverColor: LLColors.white04,
        focusColor: LLColors.white08,
      );
}
