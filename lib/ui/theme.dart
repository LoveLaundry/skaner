import 'package:flutter/material.dart';

import '../design/ll_tokens.dart';

/// Love Laundry design tokens, ported one-to-one from the web app's
/// `index.css` `@theme` + `[data-theme]` blocks.
///
/// The contract is the same: colour carries meaning (status) and never
/// decoration, one radius scale, one shadow scale, and hairline borders
/// instead of shadows except on overlays.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.canvas,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.surfaceHover,
    required this.surfaceSunken,
    required this.line,
    required this.line2,
    required this.lineStrong,
    required this.fg,
    required this.fg2,
    required this.fg3,
    required this.fgMuted,
    required this.fgFaint,
    required this.fgPlaceholder,
    required this.brand,
    required this.brandHover,
    required this.brandActive,
    required this.brandSoft,
    required this.brandBorder,
    required this.brandText,
    required this.onBrand,
    required this.success,
    required this.successSoft,
    required this.successBorder,
    required this.warning,
    required this.warningSoft,
    required this.warningBorder,
    required this.danger,
    required this.dangerSoft,
    required this.dangerBorder,
    required this.info,
    required this.infoSoft,
    required this.infoBorder,
    required this.ring,
    required this.sidebarBg,
    required this.sidebarBorder,
    required this.sidebarText,
    required this.sidebarLabel,
    required this.sidebarActive,
    required this.sidebarHoverBg,
    required this.sidebarIndicator,
  });

  final Color canvas;
  final Color surface;
  final Color surface2;
  final Color surface3;
  final Color surfaceHover;
  final Color surfaceSunken;

  final Color line;
  final Color line2;
  final Color lineStrong;

  final Color fg;
  final Color fg2;
  final Color fg3;
  final Color fgMuted;
  final Color fgFaint;
  final Color fgPlaceholder;

  final Color brand;
  final Color brandHover;
  final Color brandActive;
  final Color brandSoft;
  final Color brandBorder;
  final Color brandText;
  final Color onBrand;

  final Color success;
  final Color successSoft;
  final Color successBorder;

  final Color warning;
  final Color warningSoft;
  final Color warningBorder;

  final Color danger;
  final Color dangerSoft;
  final Color dangerBorder;

  final Color info;
  final Color infoSoft;
  final Color infoBorder;

  final Color ring;

  final Color sidebarBg;
  final Color sidebarBorder;
  final Color sidebarText;
  final Color sidebarLabel;
  final Color sidebarActive;
  final Color sidebarHoverBg;
  final Color sidebarIndicator;

  /// Light palette. Every value is one of the five permitted base colours or
  /// an opacity tint of one of them; the neutral ramps are black/white steps.
  static const light = AppColors(
    canvas: LLColors.canvas,
    surface: LLColors.surface,
    surface2: LLColors.black02,
    surface3: LLColors.black04,
    surfaceHover: LLColors.black06,
    surfaceSunken: LLColors.white,
    line: LLColors.black10,
    line2: LLColors.black20,
    lineStrong: LLColors.black30,
    fg: LLColors.textPrimary,
    fg2: LLColors.black90,
    fg3: LLColors.black70,
    fgMuted: LLColors.textMuted,
    fgFaint: LLColors.black50,
    fgPlaceholder: LLColors.black30,
    brand: LLColors.brand,
    brandHover: LLColors.brandDark,
    brandActive: LLColors.brandDark,
    brandSoft: LLColors.blue08,
    brandBorder: LLColors.blue20,
    brandText: LLColors.brand,
    onBrand: LLColors.white,
    success: LLColors.success,
    successSoft: LLColors.green08,
    successBorder: LLColors.green20,
    warning: LLColors.danger,
    warningSoft: LLColors.red04,
    warningBorder: LLColors.red20,
    danger: LLColors.danger,
    dangerSoft: LLColors.red04,
    dangerBorder: LLColors.red20,
    info: LLColors.brand,
    infoSoft: LLColors.blue08,
    infoBorder: LLColors.blue20,
    ring: LLColors.brand,
    sidebarBg: LLColors.black,
    sidebarBorder: LLColors.white10,
    sidebarText: LLColors.white90,
    sidebarLabel: LLColors.white50,
    sidebarActive: LLColors.white,
    sidebarHoverBg: LLColors.white08,
    sidebarIndicator: LLColors.brand,
  );

  /// Dark palette, again restricted to the five bases and their tints.
  static const dark = AppColors(
    canvas: LLColors.canvasDark,
    surface: LLColors.surfaceDark,
    surface2: LLColors.white04,
    surface3: LLColors.white08,
    surfaceHover: LLColors.white06,
    surfaceSunken: LLColors.canvasDark,
    line: LLColors.white10,
    line2: LLColors.white20,
    lineStrong: LLColors.borderDark,
    fg: LLColors.textPrimaryDark,
    fg2: LLColors.white90,
    fg3: LLColors.white80,
    fgMuted: LLColors.textMutedDark,
    fgFaint: LLColors.white50,
    fgPlaceholder: LLColors.white40,
    brand: LLColors.brand,
    brandHover: LLColors.brand,
    brandActive: LLColors.brand,
    brandSoft: LLColors.blue20,
    brandBorder: LLColors.blue50,
    brandText: LLColors.white,
    onBrand: LLColors.white,
    success: LLColors.success,
    successSoft: LLColors.green20,
    successBorder: LLColors.green40,
    warning: LLColors.danger,
    warningSoft: LLColors.red20,
    warningBorder: LLColors.red40,
    danger: LLColors.danger,
    dangerSoft: LLColors.red20,
    dangerBorder: LLColors.red40,
    info: LLColors.brand,
    infoSoft: LLColors.blue20,
    infoBorder: LLColors.blue50,
    ring: LLColors.brand,
    sidebarBg: LLColors.black,
    sidebarBorder: LLColors.white10,
    sidebarText: LLColors.white90,
    sidebarLabel: LLColors.white50,
    sidebarActive: LLColors.white,
    sidebarHoverBg: LLColors.white08,
    sidebarIndicator: LLColors.danger,
  );

  /// The ocean / forest / sepia / slate / nightblue / contrast presets all
  /// reuse the structural tokens and only shift the accent + surface ramp.
  static AppColors withAccent(
    AppColors base, {
    required Color brand,
    required Color brandHover,
    required Color brandText,
    required Color brandSoft,
    required Color brandBorder,
    required Color canvas,
    required Color surface,
    required Color surface2,
    required Color surface3,
    required Color line,
    required Color line2,
    required Color fg,
    required Color fg2,
    required Color fg3,
    required Color fgMuted,
    required Color fgFaint,
    required Color fgPlaceholder,
    required Color info,
    required Color infoSoft,
    required Color infoBorder,
    required Color ring,
  }) =>
      AppColors(
        canvas: canvas,
        surface: surface,
        surface2: surface2,
        surface3: surface3,
        surfaceHover: base.surfaceHover,
        surfaceSunken: base.surfaceSunken,
        line: line,
        line2: line2,
        lineStrong: base.lineStrong,
        fg: fg,
        fg2: fg2,
        fg3: fg3,
        fgMuted: fgMuted,
        fgFaint: fgFaint,
        fgPlaceholder: fgPlaceholder,
        brand: brand,
        brandHover: brandHover,
        brandActive: base.brandActive,
        brandSoft: brandSoft,
        brandBorder: brandBorder,
        brandText: brandText,
        onBrand: base.onBrand,
        success: base.success,
        successSoft: base.successSoft,
        successBorder: base.successBorder,
        warning: base.warning,
        warningSoft: base.warningSoft,
        warningBorder: base.warningBorder,
        danger: base.danger,
        dangerSoft: base.dangerSoft,
        dangerBorder: base.dangerBorder,
        info: info,
        infoSoft: infoSoft,
        infoBorder: infoBorder,
        ring: ring,
        sidebarBg: base.sidebarBg,
        sidebarBorder: base.sidebarBorder,
        sidebarText: base.sidebarText,
        sidebarLabel: base.sidebarLabel,
        sidebarActive: base.sidebarActive,
        sidebarHoverBg: base.sidebarHoverBg,
        sidebarIndicator: brand,
      );

  @override
  AppColors copyWith({
    Color? canvas,
    Color? surface,
    Color? surface2,
    Color? surface3,
    Color? surfaceHover,
    Color? surfaceSunken,
    Color? line,
    Color? line2,
    Color? lineStrong,
    Color? fg,
    Color? fg2,
    Color? fg3,
    Color? fgMuted,
    Color? fgFaint,
    Color? fgPlaceholder,
    Color? brand,
    Color? brandHover,
    Color? brandActive,
    Color? brandSoft,
    Color? brandBorder,
    Color? brandText,
    Color? onBrand,
    Color? success,
    Color? successSoft,
    Color? successBorder,
    Color? warning,
    Color? warningSoft,
    Color? warningBorder,
    Color? danger,
    Color? dangerSoft,
    Color? dangerBorder,
    Color? info,
    Color? infoSoft,
    Color? infoBorder,
    Color? ring,
    Color? sidebarBg,
    Color? sidebarBorder,
    Color? sidebarText,
    Color? sidebarLabel,
    Color? sidebarActive,
    Color? sidebarHoverBg,
    Color? sidebarIndicator,
  }) =>
      AppColors(
        canvas: canvas ?? this.canvas,
        surface: surface ?? this.surface,
        surface2: surface2 ?? this.surface2,
        surface3: surface3 ?? this.surface3,
        surfaceHover: surfaceHover ?? this.surfaceHover,
        surfaceSunken: surfaceSunken ?? this.surfaceSunken,
        line: line ?? this.line,
        line2: line2 ?? this.line2,
        lineStrong: lineStrong ?? this.lineStrong,
        fg: fg ?? this.fg,
        fg2: fg2 ?? this.fg2,
        fg3: fg3 ?? this.fg3,
        fgMuted: fgMuted ?? this.fgMuted,
        fgFaint: fgFaint ?? this.fgFaint,
        fgPlaceholder: fgPlaceholder ?? this.fgPlaceholder,
        brand: brand ?? this.brand,
        brandHover: brandHover ?? this.brandHover,
        brandActive: brandActive ?? this.brandActive,
        brandSoft: brandSoft ?? this.brandSoft,
        brandBorder: brandBorder ?? this.brandBorder,
        brandText: brandText ?? this.brandText,
        onBrand: onBrand ?? this.onBrand,
        success: success ?? this.success,
        successSoft: successSoft ?? this.successSoft,
        successBorder: successBorder ?? this.successBorder,
        warning: warning ?? this.warning,
        warningSoft: warningSoft ?? this.warningSoft,
        warningBorder: warningBorder ?? this.warningBorder,
        danger: danger ?? this.danger,
        dangerSoft: dangerSoft ?? this.dangerSoft,
        dangerBorder: dangerBorder ?? this.dangerBorder,
        info: info ?? this.info,
        infoSoft: infoSoft ?? this.infoSoft,
        infoBorder: infoBorder ?? this.infoBorder,
        ring: ring ?? this.ring,
        sidebarBg: sidebarBg ?? this.sidebarBg,
        sidebarBorder: sidebarBorder ?? this.sidebarBorder,
        sidebarText: sidebarText ?? this.sidebarText,
        sidebarLabel: sidebarLabel ?? this.sidebarLabel,
        sidebarActive: sidebarActive ?? this.sidebarActive,
        sidebarHoverBg: sidebarHoverBg ?? this.sidebarHoverBg,
        sidebarIndicator: sidebarIndicator ?? this.sidebarIndicator,
      );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color c(Color a, Color b) => t < 0.5 ? a : b;
    return AppColors(
      canvas: c(canvas, other.canvas),
      surface: c(surface, other.surface),
      surface2: c(surface2, other.surface2),
      surface3: c(surface3, other.surface3),
      surfaceHover: c(surfaceHover, other.surfaceHover),
      surfaceSunken: c(surfaceSunken, other.surfaceSunken),
      line: c(line, other.line),
      line2: c(line2, other.line2),
      lineStrong: c(lineStrong, other.lineStrong),
      fg: c(fg, other.fg),
      fg2: c(fg2, other.fg2),
      fg3: c(fg3, other.fg3),
      fgMuted: c(fgMuted, other.fgMuted),
      fgFaint: c(fgFaint, other.fgFaint),
      fgPlaceholder: c(fgPlaceholder, other.fgPlaceholder),
      brand: c(brand, other.brand),
      brandHover: c(brandHover, other.brandHover),
      brandActive: c(brandActive, other.brandActive),
      brandSoft: c(brandSoft, other.brandSoft),
      brandBorder: c(brandBorder, other.brandBorder),
      brandText: c(brandText, other.brandText),
      onBrand: c(onBrand, other.onBrand),
      success: c(success, other.success),
      successSoft: c(successSoft, other.successSoft),
      successBorder: c(successBorder, other.successBorder),
      warning: c(warning, other.warning),
      warningSoft: c(warningSoft, other.warningSoft),
      warningBorder: c(warningBorder, other.warningBorder),
      danger: c(danger, other.danger),
      dangerSoft: c(dangerSoft, other.dangerSoft),
      dangerBorder: c(dangerBorder, other.dangerBorder),
      info: c(info, other.info),
      infoSoft: c(infoSoft, other.infoSoft),
      infoBorder: c(infoBorder, other.infoBorder),
      ring: c(ring, other.ring),
      sidebarBg: c(sidebarBg, other.sidebarBg),
      sidebarBorder: c(sidebarBorder, other.sidebarBorder),
      sidebarText: c(sidebarText, other.sidebarText),
      sidebarLabel: c(sidebarLabel, other.sidebarLabel),
      sidebarActive: c(sidebarActive, other.sidebarActive),
      sidebarHoverBg: c(sidebarHoverBg, other.sidebarHoverBg),
      sidebarIndicator: c(sidebarIndicator, other.sidebarIndicator),
    );
  }
}

/// Convenience accessors so widgets read `context.c.brand` rather than
/// repeating `Theme.of(context).extension<AppColors>()!`.
extension AppColorsContext on BuildContext {
  AppColors get c => Theme.of(this).extension<AppColors>()!;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  TextTheme get texts => Theme.of(this).textTheme;

  /// Scales a fixed UI font size with the active [AppFontSize] step, so
  /// hand-placed metadata sizes (badges, captions, table headers) grow with
  /// the Comfort setting instead of staying pinned. Print/PDF sheets must
  /// keep literal sizes and never use this.
  double fs(double size) {
    final base = texts.bodyMedium?.fontSize ?? 14;
    return size * base / 14;
  }
}

/// One radius scale, mirroring `--radius-xs … --radius-xl`. Soft/rounded:
/// controls sit at [md], cards at [lg], overlays at [xl], so a nested stack
/// always steps up by a fixed amount.
class Radii {
  Radii._();
  static const double xs = 6;
  static const double sm = 8;
  static const double md = 10;
  static const double lg = 12;
  static const double xl = 16;
  static const double pill = 999;
}

/// One shadow scale. Flutter draws shadows on the decoration, so each entry
/// is a ready-made `BoxShadow` list. Soft/rounded: low-opacity and wide so a
/// surface lifts without a hard edge.
class Shadows {
  Shadows._();

  static const List<BoxShadow> xs = [
    BoxShadow(color: LLColors.black04, blurRadius: 3, offset: Offset(0, 1)),
  ];
  static const List<BoxShadow> sm = [
    BoxShadow(color: LLColors.black08, blurRadius: 6, offset: Offset(0, 2)),
    BoxShadow(color: LLColors.black04, blurRadius: 2, offset: Offset(0, 1)),
  ];
  static const List<BoxShadow> md = [
    BoxShadow(color: LLColors.black10, blurRadius: 16, offset: Offset(0, 6)),
    BoxShadow(color: LLColors.black10, blurRadius: 6, offset: Offset(0, 2)),
  ];
  static const List<BoxShadow> lg = [
    BoxShadow(color: LLColors.black16, blurRadius: 32, offset: Offset(0, 18)),
    BoxShadow(color: LLColors.black10, blurRadius: 12, offset: Offset(0, 6)),
  ];
  static const List<BoxShadow> pop = [
    BoxShadow(color: LLColors.black20, blurRadius: 40, offset: Offset(0, 16)),
    BoxShadow(color: LLColors.black08, blurRadius: 10, offset: Offset(0, 4)),
  ];
}

/// The six body sizes from the web app's `FONT_SIZE_MAP`, plus the shared
/// Comfort step (web `xxxl`) for elders and low-vision operators.
enum AppFontSize {
  xs(12, 0.85),
  sm(13, 0.92),
  md(14, 1.0),
  lg(15, 1.08),
  xl(17, 1.18),
  xxl(19, 1.30),
  xxxl(22, 1.50);

  const AppFontSize(this.px, this.zoom);
  final double px;
  final double zoom;

  String get label => switch (this) {
        AppFontSize.xs => 'Extra small',
        AppFontSize.sm => 'Small',
        AppFontSize.md => 'Default',
        AppFontSize.lg => 'Large',
        AppFontSize.xl => 'Extra large',
        AppFontSize.xxl => 'XXL',
        AppFontSize.xxxl => 'Comfort',
      };

  /// Comfort mode is the largest step, meant for elders.
  bool get isComfort => this == AppFontSize.xxxl;
}

/// The nine selectable theme presets, matching the web app's list.
enum AppTheme {
  light('Light', false),
  contrast('High contrast', false),
  dark('Dark', true),
  ocean('Ocean', false),
  forest('Forest', false),
  sepia('Sepia', false),
  slate('Slate', false),
  nightblue('Night blue', true),
  contrastDark('High contrast dark', true);

  const AppTheme(this.label, this.isDark);
  final String label;
  final bool isDark;
}

class AppThemeData {
  AppThemeData._();

  /// The nine presets collapse onto the two canonical themes: dark, nightblue
  /// and contrastDark use [LLTheme.dark], all others use [LLTheme.light].
  static AppColors colorsFor(AppTheme theme) =>
      theme.isDark ? AppColors.dark : AppColors.light;

  static ThemeData build(AppTheme theme, AppFontSize fontSize) {
    final colors = colorsFor(theme);
    final base = fontSize.px;
    final canonical = theme.isDark ? LLTheme.dark : LLTheme.light;
    final scheme = canonical.colorScheme.copyWith(
      primary: colors.brand,
      onPrimary: colors.onBrand,
      secondary: colors.brandHover,
      onSecondary: colors.onBrand,
      secondaryContainer: colors.brandSoft,
      onSecondaryContainer: colors.brandText,
      tertiary: colors.success,
      onTertiary: colors.onBrand,
      surface: colors.surface,
      onSurface: colors.fg,
      surfaceContainer: colors.surface2,
      surfaceContainerLow: colors.surfaceSunken,
      surfaceContainerHigh: colors.surface3,
      surfaceTint: LLColors.transparent,
      error: colors.danger,
      onError: colors.onBrand,
      outline: colors.line2,
    );

    final fontFamily = LLTheme.fontFamily;
    TextStyle t(double size, FontWeight weight, {double? height, Color? color}) =>
        TextStyle(
          fontSize: size,
          fontWeight: weight,
          height: height,
          color: color ?? colors.fg,
          fontFamily: fontFamily,
        );

    final textTheme = TextTheme(
      displayLarge: t(base * 2.6, FontWeight.w700, height: 1.15),
      displayMedium: t(base * 2.1, FontWeight.w700, height: 1.18),
      displaySmall: t(base * 1.75, FontWeight.w600, height: 1.2),
      headlineLarge: t(base * 1.5, FontWeight.w600, height: 1.24),
      headlineMedium: t(base * 1.3, FontWeight.w600, height: 1.26),
      headlineSmall: t(base * 1.15, FontWeight.w600, height: 1.3),
      titleLarge: t(base * 1.06, FontWeight.w600, height: 1.32, color: colors.fg),
      titleMedium: t(base * 0.98, FontWeight.w600, height: 1.36, color: colors.fg),
      titleSmall: t(base * 0.9, FontWeight.w600, height: 1.4, color: colors.fg),
      bodyLarge: t(base, FontWeight.w400, height: 1.45),
      bodyMedium: t(base * 0.94, FontWeight.w400, height: 1.45),
      bodySmall: t(base * 0.86, FontWeight.w400, height: 1.45, color: colors.fg3),
      labelLarge: t(base * 0.94, FontWeight.w600, height: 1.2),
      labelMedium: t(base * 0.86, FontWeight.w600, height: 1.2),
      labelSmall: t(base * 0.78, FontWeight.w600, height: 1.2),
    );

    return canonical.copyWith(
      colorScheme: scheme,
      brightness: theme.isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: colors.canvas,
      canvasColor: colors.canvas,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      extensions: [colors],
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        foregroundColor: colors.fg,
        surfaceTintColor: LLColors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(color: colors.fg),
        iconTheme: IconThemeData(color: colors.fg3),
        shape: Border(bottom: BorderSide(color: colors.line)),
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        surfaceTintColor: LLColors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
          side: BorderSide(color: colors.line),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.line,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surface2,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        hintStyle: TextStyle(color: colors.fgPlaceholder, fontSize: base * 0.94),
        labelStyle: TextStyle(color: colors.fg3, fontSize: base * 0.9),
        floatingLabelStyle: TextStyle(color: colors.brand, fontSize: base * 0.86),
        prefixIconColor: colors.fgFaint,
        suffixIconColor: colors.fgFaint,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: colors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: colors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: colors.brand, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: colors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: colors.danger, width: 1.6),
        ),
        errorStyle: TextStyle(color: colors.danger, fontSize: base * 0.8),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.brand,
          foregroundColor: LLColors.white,
          disabledBackgroundColor: colors.line2,
          disabledForegroundColor: colors.fgFaint,
          minimumSize: const Size(0, 42),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.fg2,
          minimumSize: const Size(0, 42),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          textStyle: textTheme.labelLarge,
          side: BorderSide(color: colors.line2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.brand,
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: colors.fg3,
          minimumSize: const Size(40, 40),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surface2,
        selectedColor: colors.brandSoft,
        side: BorderSide(color: colors.line),
        labelStyle: textTheme.labelMedium!.copyWith(color: colors.fg2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: colors.surface,
        selectedItemColor: colors.brand,
        unselectedItemColor: colors.fgFaint,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: textTheme.labelSmall?.copyWith(
          color: colors.brand,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle:
            textTheme.labelSmall?.copyWith(color: colors.fgFaint),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: LLColors.transparent,
        indicatorColor: colors.brandSoft,
        elevation: 0,
        height: 62,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelSmall!.copyWith(
            color: selected ? colors.brand : colors.fgFaint,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? colors.brand
                  : colors.fgFaint,
              size: 22,
            )),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: LLColors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.xl),
          side: BorderSide(color: colors.line),
        ),
        titleTextStyle: textTheme.titleMedium,
        contentTextStyle: textTheme.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: LLColors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl)),
        ),
        showDragHandle: true,
        dragHandleColor: colors.line2,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.fg,
        contentTextStyle: TextStyle(color: colors.surface, fontSize: base * 0.94),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.fg,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        textStyle: TextStyle(color: colors.surface, fontSize: base * 0.82),
        waitDuration: const Duration(milliseconds: 500),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.brand,
        linearTrackColor: colors.surface3,
        circularTrackColor: LLColors.transparent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? LLColors.white : colors.surface),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? colors.brand : colors.surface3),
        trackOutlineColor: WidgetStatePropertyAll(colors.line2),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? colors.brand : LLColors.transparent),
        checkColor: const WidgetStatePropertyAll(LLColors.white),
        side: BorderSide(color: colors.line2, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.xs)),
      ),
      listTileTheme: ListTileThemeData(
        titleTextStyle: textTheme.bodyLarge,
        subtitleTextStyle: textTheme.bodySmall,
        iconColor: colors.fg3,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: colors.brand,
        unselectedLabelColor: colors.fg3,
        indicatorColor: colors.brand,
        dividerColor: colors.line,
        labelStyle: textTheme.labelLarge,
        unselectedLabelStyle: textTheme.labelLarge,
      ),
      expansionTileTheme: ExpansionTileThemeData(
        iconColor: colors.fgFaint,
        collapsedIconColor: colors.fgFaint,
        textColor: colors.fg,
        shape: const Border(),
        collapsedShape: const Border(),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
