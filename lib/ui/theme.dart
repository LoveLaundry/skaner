import 'package:flutter/material.dart';

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

  static const light = AppColors(
    canvas: Color(0xFFF6F7F9),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF7F8FA),
    surface3: Color(0xFFF0F2F5),
    surfaceHover: Color(0xFFF2F4F7),
    surfaceSunken: Color(0xFFFAFBFC),
    line: Color(0xFFE3E7ED),
    line2: Color(0xFFD3D9E1),
    lineStrong: Color(0xFFB8C1CD),
    fg: Color(0xFF0F172A),
    fg2: Color(0xFF26313F),
    fg3: Color(0xFF475467),
    fgMuted: Color(0xFF5B6879),
    fgFaint: Color(0xFF8592A3),
    fgPlaceholder: Color(0xFFA3AEBD),
    brand: Color(0xFFD92D20),
    brandHover: Color(0xFFB42318),
    brandActive: Color(0xFF912018),
    brandSoft: Color(0xFFFEF3F2),
    brandBorder: Color(0xFFFECDC9),
    brandText: Color(0xFFB42318),
    onBrand: Color(0xFFFFFFFF),
    success: Color(0xFF067647),
    successSoft: Color(0xFFECFDF3),
    successBorder: Color(0xFFA9E5C3),
    warning: Color(0xFFB54708),
    warningSoft: Color(0xFFFFFAEB),
    warningBorder: Color(0xFFFEDF89),
    danger: Color(0xFFB42318),
    dangerSoft: Color(0xFFFEF3F2),
    dangerBorder: Color(0xFFFECDC9),
    info: Color(0xFF175CD3),
    infoSoft: Color(0xFFEFF8FF),
    infoBorder: Color(0xFFB2DDFF),
    ring: Color(0xFF2563EB),
    sidebarBg: Color(0xFF101828),
    sidebarBorder: Color(0xFF1D2939),
    sidebarText: Color(0xFFC3CBD6),
    sidebarLabel: Color(0xFF7C8AA0),
    sidebarActive: Color(0xFFFFFFFF),
    sidebarHoverBg: Color(0xFF1D2939),
    sidebarIndicator: Color(0xFFF04438),
  );

  static const dark = AppColors(
    canvas: Color(0xFF0D1016),
    surface: Color(0xFF151A22),
    surface2: Color(0xFF1A2029),
    surface3: Color(0xFF212934),
    surfaceHover: Color(0xFF1F2731),
    surfaceSunken: Color(0xFF11161D),
    line: Color(0xFF262E3A),
    line2: Color(0xFF333D4C),
    lineStrong: Color(0xFF435064),
    fg: Color(0xFFF2F5F9),
    fg2: Color(0xFFD3DAE4),
    fg3: Color(0xFFB0BAC8),
    fgMuted: Color(0xFF8C98A8),
    fgFaint: Color(0xFF6F7C8D),
    fgPlaceholder: Color(0xFF5D6979),
    brand: Color(0xFFF04438),
    brandHover: Color(0xFFF97066),
    brandActive: Color(0xFFFDA29B),
    brandSoft: Color(0xFF2A1518),
    brandBorder: Color(0xFF4A2022),
    brandText: Color(0xFFF97066),
    onBrand: Color(0xFFFFFFFF),
    success: Color(0xFF6CE9A6),
    successSoft: Color(0xFF0D2019),
    successBorder: Color(0xFF1E4436),
    warning: Color(0xFFFEC84B),
    warningSoft: Color(0xFF241C0A),
    warningBorder: Color(0xFF4A3410),
    danger: Color(0xFFFDA29B),
    dangerSoft: Color(0xFF2A1518),
    dangerBorder: Color(0xFF4A2022),
    info: Color(0xFF84CAFF),
    infoSoft: Color(0xFF0B1B2C),
    infoBorder: Color(0xFF194A6B),
    ring: Color(0xFF84CAFF),
    sidebarBg: Color(0xFF0A0D12),
    sidebarBorder: Color(0xFF1A222C),
    sidebarText: Color(0xFFB6C0CC),
    sidebarLabel: Color(0xFF6B7889),
    sidebarActive: Color(0xFFFFFFFF),
    sidebarHoverBg: Color(0xFF182029),
    sidebarIndicator: Color(0xFFF04438),
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
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
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
}

/// One radius scale, mirroring `--radius-xs … --radius-xl`.
class Radii {
  Radii._();
  static const double xs = 3;
  static const double sm = 4;
  static const double md = 6;
  static const double lg = 8;
  static const double xl = 12;
  static const double pill = 999;
}

/// One shadow scale. Flutter draws shadows on the decoration, so each entry
/// is a ready-made `BoxShadow` list.
class Shadows {
  Shadows._();

  static const List<BoxShadow> xs = [
    BoxShadow(color: Color(0x0D101828), blurRadius: 2, offset: Offset(0, 1)),
  ];
  static const List<BoxShadow> sm = [
    BoxShadow(color: Color(0x14101828), blurRadius: 3, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0F101828), blurRadius: 2, offset: Offset(0, 1)),
  ];
  static const List<BoxShadow> md = [
    BoxShadow(color: Color(0x14101828), blurRadius: 8, offset: Offset(0, 4)),
    BoxShadow(color: Color(0x0D101828), blurRadius: 4, offset: Offset(0, 2)),
  ];
  static const List<BoxShadow> lg = [
    BoxShadow(color: Color(0x1F101828), blurRadius: 24, offset: Offset(0, 14)),
    BoxShadow(color: Color(0x0F101828), blurRadius: 8, offset: Offset(0, 4)),
  ];
  static const List<BoxShadow> pop = [
    BoxShadow(color: Color(0x2E101828), blurRadius: 32, offset: Offset(0, 10)),
    BoxShadow(color: Color(0x14101828), blurRadius: 6, offset: Offset(0, 2)),
  ];
}

/// The six body sizes from the web app's `FONT_SIZE_MAP`.
enum AppFontSize {
  xs(12, 0.85),
  sm(13, 0.92),
  md(14, 1.0),
  lg(15, 1.08),
  xl(17, 1.18),
  xxl(19, 1.30);

  const AppFontSize(this.px, this.zoom);
  final double px;
  final double zoom;

  String get label => switch (this) {
        AppFontSize.xs => 'Extra small',
        AppFontSize.sm => 'Small',
        AppFontSize.md => 'Default',
        AppFontSize.lg => 'Large',
        AppFontSize.xl => 'Extra large',
        AppFontSize.xxl => 'Largest',
      };
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

  static AppColors colorsFor(AppTheme theme) => switch (theme) {
        AppTheme.light => AppColors.light,
        AppTheme.dark => AppColors.dark,
        AppTheme.contrast => AppColors.withAccent(
            AppColors.light,
            brand: const Color(0xFF0B3DA8),
            brandHover: const Color(0xFF072C7E),
            brandText: const Color(0xFF072C7E),
            brandSoft: const Color(0xFFEDF3FE),
            brandBorder: const Color(0xFFB9CEF5),
            canvas: const Color(0xFFFFFFFF),
            surface: const Color(0xFFFFFFFF),
            surface2: const Color(0xFFF2F5FA),
            surface3: const Color(0xFFE8EEF7),
            line: const Color(0xFFCBD5E1),
            line2: const Color(0xFF9FAEC2),
            fg: const Color(0xFF000000),
            fg2: const Color(0xFF111827),
            fg3: const Color(0xFF1F2937),
            fgMuted: const Color(0xFF334155),
            fgFaint: const Color(0xFF475569),
            fgPlaceholder: const Color(0xFF64748B),
            info: const Color(0xFF0B3DA8),
            infoSoft: const Color(0xFFEDF3FE),
            infoBorder: const Color(0xFFB9CEF5),
            ring: const Color(0xFF0B3DA8),
          ),
        AppTheme.ocean => AppColors.withAccent(
            AppColors.light,
            brand: const Color(0xFF0E7490),
            brandHover: const Color(0xFF0A5A70),
            brandText: const Color(0xFF0A5A70),
            brandSoft: const Color(0xFFECFEFF),
            brandBorder: const Color(0xFFA5E8F5),
            canvas: const Color(0xFFF3F8FA),
            surface: const Color(0xFFFFFFFF),
            surface2: const Color(0xFFF0F6F9),
            surface3: const Color(0xFFE6F0F4),
            line: const Color(0xFFD7E6EC),
            line2: const Color(0xFFB9D2DB),
            fg: const Color(0xFF0B2530),
            fg2: const Color(0xFF14323F),
            fg3: const Color(0xFF234A57),
            fgMuted: const Color(0xFF335C69),
            fgFaint: const Color(0xFF4C7A87),
            fgPlaceholder: const Color(0xFF6B97A3),
            info: const Color(0xFF0369A1),
            infoSoft: const Color(0xFFF0F9FF),
            infoBorder: const Color(0xFFBAE6FD),
            ring: const Color(0xFF0E7490),
          ),
        AppTheme.forest => AppColors.withAccent(
            AppColors.light,
            brand: const Color(0xFF15803D),
            brandHover: const Color(0xFF11632F),
            brandText: const Color(0xFF11632F),
            brandSoft: const Color(0xFFF0FDF4),
            brandBorder: const Color(0xFFBBF7D0),
            canvas: const Color(0xFFF4F8F4),
            surface: const Color(0xFFFFFFFF),
            surface2: const Color(0xFFF2F7F2),
            surface3: const Color(0xFFE8F1E8),
            line: const Color(0xFFD9E7D9),
            line2: const Color(0xFFBBD5BB),
            fg: const Color(0xFF0D1F0D),
            fg2: const Color(0xFF152E15),
            fg3: const Color(0xFF1E4420),
            fgMuted: const Color(0xFF2C5C2F),
            fgFaint: const Color(0xFF437A46),
            fgPlaceholder: const Color(0xFF5F9A62),
            info: const Color(0xFF166534),
            infoSoft: const Color(0xFFF0FDF4),
            infoBorder: const Color(0xFFBBF7D0),
            ring: const Color(0xFF15803D),
          ),
        AppTheme.sepia => AppColors.withAccent(
            AppColors.light,
            brand: const Color(0xFFA16207),
            brandHover: const Color(0xFF854D0A),
            brandText: const Color(0xFF854D0A),
            brandSoft: const Color(0xFFFFFBEB),
            brandBorder: const Color(0xFFFDE68A),
            canvas: const Color(0xFFFAF7F0),
            surface: const Color(0xFFFFFCF6),
            surface2: const Color(0xFFF7F2E8),
            surface3: const Color(0xFFF0E9DB),
            line: const Color(0xFFE6DCC9),
            line2: const Color(0xFFD3C5AB),
            fg: const Color(0xFF261F14),
            fg2: const Color(0xFF3A2F1F),
            fg3: const Color(0xFF4E402C),
            fgMuted: const Color(0xFF6B5A40),
            fgFaint: const Color(0xFF8C7A5C),
            fgPlaceholder: const Color(0xFFA89578),
            info: const Color(0xFF92400E),
            infoSoft: const Color(0xFFFFFBEB),
            infoBorder: const Color(0xFFFDE68A),
            ring: const Color(0xFFA16207),
          ),
        AppTheme.slate => AppColors.withAccent(
            AppColors.light,
            brand: const Color(0xFF475569),
            brandHover: const Color(0xFF334155),
            brandText: const Color(0xFF334155),
            brandSoft: const Color(0xFFF1F5F9),
            brandBorder: const Color(0xFFCBD5E1),
            canvas: const Color(0xFFF1F5F9),
            surface: const Color(0xFFFFFFFF),
            surface2: const Color(0xFFF5F7FA),
            surface3: const Color(0xFFEBEFF4),
            line: const Color(0xFFDCE2E9),
            line2: const Color(0xFFC2CBD6),
            fg: const Color(0xFF0F172A),
            fg2: const Color(0xFF1E293B),
            fg3: const Color(0xFF334155),
            fgMuted: const Color(0xFF475569),
            fgFaint: const Color(0xFF64748B),
            fgPlaceholder: const Color(0xFF94A3B8),
            info: const Color(0xFF0369A1),
            infoSoft: const Color(0xFFF0F9FF),
            infoBorder: const Color(0xFFBAE6FD),
            ring: const Color(0xFF475569),
          ),
        AppTheme.nightblue => AppColors.withAccent(
            AppColors.dark,
            brand: const Color(0xFF4D8BF8),
            brandHover: const Color(0xFF7BAAFB),
            brandText: const Color(0xFF7BAAFB),
            brandSoft: const Color(0xFF101C33),
            brandBorder: const Color(0xFF1E3157),
            canvas: const Color(0xFF0A1020),
            surface: const Color(0xFF111827),
            surface2: const Color(0xFF161F30),
            surface3: const Color(0xFF1D2840),
            line: const Color(0xFF1E2A44),
            line2: const Color(0xFF2A3A5C),
            fg: const Color(0xFFF1F5F9),
            fg2: const Color(0xFFD6DEEA),
            fg3: const Color(0xFFB4C0D2),
            fgMuted: const Color(0xFF93A1B7),
            fgFaint: const Color(0xFF76849B),
            fgPlaceholder: const Color(0xFF64748B),
            info: const Color(0xFF7BAAFB),
            infoSoft: const Color(0xFF101C33),
            infoBorder: const Color(0xFF1E3157),
            ring: const Color(0xFF4D8BF8),
          ),
        AppTheme.contrastDark => AppColors.withAccent(
            AppColors.dark,
            brand: const Color(0xFF6EA8FF),
            brandHover: const Color(0xFF9CC4FF),
            brandText: const Color(0xFF9CC4FF),
            brandSoft: const Color(0xFF0E2038),
            brandBorder: const Color(0xFF24507F),
            canvas: const Color(0xFF000000),
            surface: const Color(0xFF0A0A0A),
            surface2: const Color(0xFF141414),
            surface3: const Color(0xFF1F1F1F),
            line: const Color(0xFF3D3D3D),
            line2: const Color(0xFF5A5A5A),
            fg: const Color(0xFFFFFFFF),
            fg2: const Color(0xFFF0F0F0),
            fg3: const Color(0xFFE0E0E0),
            fgMuted: const Color(0xFFCCCCCC),
            fgFaint: const Color(0xFFAAAAAA),
            fgPlaceholder: const Color(0xFF8C8C8C),
            info: const Color(0xFF9CC4FF),
            infoSoft: const Color(0xFF0E2038),
            infoBorder: const Color(0xFF24507F),
            ring: const Color(0xFF6EA8FF),
          ),
      };

  static ThemeData build(AppTheme theme, AppFontSize fontSize) {
    final colors = colorsFor(theme);
    final base = fontSize.px;
    final scheme =
        ColorScheme.fromSeed(seedColor: colors.brand, brightness: Brightness.light)
            .copyWith(
              primary: colors.brand,
              onPrimary: colors.onBrand,
              secondary: colors.brandHover,
              onSecondary: colors.onBrand,
              secondaryContainer: colors.brandSoft,
              onSecondaryContainer: colors.brandHover,
              surface: colors.surface,
              onSurface: colors.fg,
              surfaceContainer: colors.surface2,
              surfaceContainerLow: colors.surfaceSunken,
              surfaceContainerHigh: colors.surface3,
              surfaceTint: Colors.transparent,
              error: colors.danger,
              onError: colors.onBrand,
              outline: colors.line2,
            )
            .copyWith(brightness: theme.isDark ? Brightness.dark : Brightness.light);

    final fontFamily = 'Roboto';
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

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: theme.isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: colors.canvas,
      canvasColor: colors.canvas,
      textTheme: textTheme,
      fontFamily: fontFamily,
      splashFactory: InkSparkle.splashFactory,
      extensions: [colors],
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        foregroundColor: colors.fg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(color: colors.fg),
        iconTheme: IconThemeData(color: colors.fg3),
        shape: Border(bottom: BorderSide(color: colors.line)),
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
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
          foregroundColor: Colors.white,
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
        surfaceTintColor: Colors.transparent,
        indicatorColor: colors.brandSoft,
        elevation: 0,
        height: 62,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          // A colorless plain style would pre-empt M3's onSurface fallback and
          // lose the selected/unselected distinction entirely; carry colour +
          // weight explicitly so the active tab reads at a glance.
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
        surfaceTintColor: Colors.transparent,
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
        surfaceTintColor: Colors.transparent,
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
        circularTrackColor: Colors.transparent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? Colors.white : colors.surface),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? colors.brand : colors.surface3),
        trackOutlineColor: WidgetStatePropertyAll(colors.line2),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? colors.brand : Colors.transparent),
        checkColor: const WidgetStatePropertyAll(Colors.white),
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
