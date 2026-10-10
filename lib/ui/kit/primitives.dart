import 'package:flutter/material.dart';

import '../theme.dart';

enum AppButtonVariant {
  primary,
  secondary,
  ghost,
  outline,
  warning,
  danger,
  dangerGhost,
  link;

  static AppButtonVariant parse(String? raw) => switch (raw) {
        'primary' || 'default' => AppButtonVariant.primary,
        'secondary' => AppButtonVariant.secondary,
        'ghost' => AppButtonVariant.ghost,
        'outline' => AppButtonVariant.outline,
        'warning' => AppButtonVariant.warning,
        'danger' || 'destructive' => AppButtonVariant.danger,
        'danger-ghost' || 'dangerGhost' => AppButtonVariant.dangerGhost,
        'link' => AppButtonVariant.link,
        _ => AppButtonVariant.secondary,
      };
}

enum AppButtonSize {
  xs(28, 8, 12, 14),
  sm(32, 10, 12.5, 16),
  md(36, 14, 13, 16),
  lg(40, 16, 14, 16),
  icon(32, 0, 13, 16),
  iconSm(28, 0, 12, 14),
  iconLg(40, 0, 14, 18);

  const AppButtonSize(this.height, this.padX, this.fontSize, this.iconSize);
  final double height;
  final double padX;
  final double fontSize;
  final double iconSize;

  bool get isIconOnly =>
      this == AppButtonSize.icon ||
      this == AppButtonSize.iconSm ||
      this == AppButtonSize.iconLg;
}

/// Port of `components/ui/button.tsx`.
///
/// The pending state keeps the label in place rather than swapping it for a
/// bare spinner, so the control does not change width mid-submit.
class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.secondary,
    this.size = AppButtonSize.md,
    this.icon,
    this.trailingIcon,
    this.loading = false,
    this.block = false,
    this.expand = false,
    this.dense = false,
    this.tooltip,
  });

  /// Icon-only convenience constructor; [label] becomes the tooltip.
  const AppButton.icon({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.variant = AppButtonVariant.ghost,
    this.size = AppButtonSize.icon,
    this.loading = false,
  })  : label = '',
        trailingIcon = null,
        block = false,
        expand = false,
        dense = false;

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool loading;
  final bool block;
  final bool expand;
  final bool dense;
  final String? tooltip;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final v = widget.variant;
    final s = widget.size;
    final scale = context.texts.bodyMedium!.fontSize! / 14;

    Color bg;
    Color fg;
    Color border;
    List<BoxShadow> shadow = const [];

    switch (v) {
      case AppButtonVariant.primary:
        bg = _pressed
            ? c.brandActive
            : _hovered
                ? c.brandHover
                : c.brand;
        fg = Colors.white;
        border = c.brand;
        shadow = Shadows.xs;
      case AppButtonVariant.secondary:
        bg = _hovered ? c.surfaceHover : c.surface;
        fg = _hovered ? c.fg : c.fg2;
        border = _hovered ? c.lineStrong : c.line2;
      case AppButtonVariant.ghost:
        bg = _hovered ? c.surfaceHover : Colors.transparent;
        fg = _hovered ? c.fg : c.fgMuted;
        border = Colors.transparent;
      case AppButtonVariant.outline:
        bg = _hovered ? c.brandBorder : c.brandSoft;
        fg = c.brandText;
        border = _hovered ? c.brand : c.brandBorder;
      case AppButtonVariant.warning:
        bg = _hovered ? Color.lerp(c.warning, Colors.black, 0.15)! : c.warning;
        fg = Colors.white;
        border = c.warning;
        shadow = Shadows.xs;
      case AppButtonVariant.danger:
        bg = _hovered ? Color.lerp(c.danger, Colors.black, 0.15)! : c.danger;
        fg = Colors.white;
        border = c.danger;
        shadow = Shadows.xs;
      case AppButtonVariant.dangerGhost:
        bg = _hovered ? c.dangerSoft : Colors.transparent;
        fg = c.danger;
        border = Colors.transparent;
      case AppButtonVariant.link:
        bg = Colors.transparent;
        fg = c.brandText;
        border = Colors.transparent;
    }

    final enabled = widget.onPressed != null && !widget.loading;
    final effectiveBg =
        enabled ? bg : (v == AppButtonVariant.link ? bg : c.surface3);
    final effectiveFg = enabled ? fg : c.fgFaint;
    final effectiveBorder = enabled ? border : c.line2;

    final child = Material(
      color: effectiveBg,
      borderRadius: BorderRadius.circular(Radii.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? widget.onPressed : null,
        onHighlightChanged: (p) => setState(() => _pressed = p),
        onHover: (h) => setState(() => _hovered = h),
        splashColor: v == AppButtonVariant.link
            ? Colors.transparent
            : fg.withValues(alpha: 0.10),
        highlightColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: effectiveBorder,
              width: v == AppButtonVariant.primary ||
                      v == AppButtonVariant.warning ||
                      v == AppButtonVariant.danger
                  ? 1
                  : 1,
            ),
            boxShadow: enabled ? shadow : const [],
          ),
          padding: v == AppButtonVariant.link
              ? EdgeInsets.zero
              : EdgeInsets.symmetric(horizontal: s.padX * scale),
          height: (s == AppButtonSize.lg && widget.dense
              ? s.height - 4
              : s.height) * scale,
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: widget.block || widget.expand
                ? MainAxisSize.max
                : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.loading)
                SizedBox(
                  width: s.iconSize * scale,
                  height: s.iconSize * scale,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: effectiveFg,
                  ),
                )
              else if (widget.icon != null)
                Icon(widget.icon, size: s.iconSize * scale, color: effectiveFg),
              if (widget.loading || widget.icon != null)
                SizedBox(width: widget.dense ? 4 : 6 * scale),
              if (widget.label.isNotEmpty)
                Flexible(
                  child: Text(
                    widget.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: s.fontSize * scale,
                      fontWeight: FontWeight.w600,
                      color: effectiveFg,
                      height: 1.2,
                      decoration: v == AppButtonVariant.link
                          ? TextDecoration.underline
                          : null,
                      decorationColor: c.brandHover,
                    ),
                  ),
                ),
              if (!widget.loading && widget.trailingIcon != null) ...[
                SizedBox(width: widget.dense ? 4 : 6 * scale),
                Icon(widget.trailingIcon,
                    size: s.iconSize * scale, color: effectiveFg),
              ],
            ],
          ),
        ),
      ),
    );

    final sized = SizedBox(
      width: widget.expand ? double.infinity : null,
      child: child,
    );
    return widget.tooltip == null
        ? sized
        : Tooltip(message: widget.tooltip!, child: sized);
  }
}

/// Port of `components/ui/badge.tsx`. Tone carries meaning, never decoration.
enum AppTone {
  neutral,
  brand,
  success,
  warning,
  danger,
  info;

  static AppTone parse(String? raw) => switch (raw?.toLowerCase()) {
        'brand' || 'primary' || 'red' => AppTone.brand,
        'success' || 'green' => AppTone.success,
        'warning' || 'amber' || 'orange' || 'yellow' => AppTone.warning,
        'danger' || 'red' || 'destructive' => AppTone.danger,
        'info' || 'blue' => AppTone.info,
        _ => AppTone.neutral,
      };

  (Color fg, Color bg, Color border) resolve(AppColors c) => switch (this) {
        AppTone.neutral => (c.fg3, c.surface2, c.line2),
        AppTone.brand => (c.brandText, c.brandSoft, c.brandBorder),
        AppTone.success => (c.success, c.successSoft, c.successBorder),
        AppTone.warning => (c.warning, c.warningSoft, c.warningBorder),
        AppTone.danger => (c.danger, c.dangerSoft, c.dangerBorder),
        AppTone.info => (c.info, c.infoSoft, c.infoBorder),
      };

  Color dot(AppColors c) => switch (this) {
        AppTone.neutral => c.fgFaint,
        AppTone.brand => c.brand,
        AppTone.success => c.success,
        AppTone.warning => c.warning,
        AppTone.danger => c.danger,
        AppTone.info => c.info,
      };
}

class AppBadge extends StatelessWidget {
  const AppBadge(
    this.label, {
    super.key,
    this.tone = AppTone.neutral,
    this.icon,
    this.solid = false,
    this.compact = false,
  });

  final String label;
  final AppTone tone;
  final IconData? icon;
  final bool solid;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (fg, bg, border) = tone.resolve(c);
    final fgOut = solid ? Colors.white : fg;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8, vertical: compact ? 1.5 : 3),
      decoration: BoxDecoration(
        color: solid ? tone.dot(c) : bg,
        border: Border.all(color: solid ? tone.dot(c) : border),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: context.fs(compact ? 10 : 12), color: fgOut),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: context.fs(compact ? 10.5 : 11.5),
              fontWeight: FontWeight.w600,
              color: fgOut,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

/// Port of `components/ui/avatar.tsx`.
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    this.name,
    this.imageUrl,
    this.size = 36,
    this.icon,
  });

  final String? name;
  final String? imageUrl;
  final double size;
  final IconData? icon;

  String get _initials {
    final n = (name ?? '').trim();
    if (n.isEmpty) return '?';
    final parts = n.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length == 1) {
      return parts.first.substring(0, parts.first.length >= 2 ? 2 : 1)
          .toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fg = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : c.brandText;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c.brandSoft,
        border: Border.all(color: c.brandBorder),
      ),
      child: imageUrl != null && imageUrl!.isNotEmpty
          ? Image.network(
              imageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _fallback(fg, size),
            )
          : _fallback(fg, size),
    );
  }

  Widget _fallback(Color fg, double size) => Center(
        child: icon != null
            ? Icon(icon, size: size * 0.5, color: fg)
            : Text(
                _initials,
                style: TextStyle(
                  fontSize: size * 0.38,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
      );
}

/// Port of `components/ui/card.tsx`. Hairline border, shadow only on overlays.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    this.child,
    this.title,
    this.subtitle,
    this.trailing,
    this.leading,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.selected = false,
    this.accent = false,
  });

  final Widget? child;
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? leading;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool selected;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    final header = (title != null || trailing != null)
        ? Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 0),
            child: Row(
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 10)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title != null)
                        Text(title!, style: t.titleSmall),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(subtitle!,
                              style: t.bodySmall?.copyWith(color: c.fgMuted)),
                        ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing!,
                ],
              ],
            ),
          )
        : null;

    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(Radii.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.lg),
            border: Border.all(
              color: selected ? c.brand : c.line,
              width: selected ? 1.6 : 1,
            ),
          ),
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (header != null) header,
              if (child != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    leading != null || title != null ? 0 : 16,
                    12,
                    trailing != null ? 0 : 16,
                    16,
                  ),
                  child: child,
                )
              else
                const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}

/// Port of `components/ui/filter-chip.tsx`.
class AppFilterChip extends StatelessWidget {
  const AppFilterChip({
    super.key,
    required this.label,
    required this.selected,
    this.count,
    this.icon,
    this.onTap,
  });

  final String label;
  final bool selected;
  final int? count;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    return Material(
      color: selected ? c.brand : c.surface,
      borderRadius: BorderRadius.circular(Radii.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.pill),
            border: Border.all(color: selected ? c.brand : c.line2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 14,
                    color: selected ? Colors.white : c.fgMuted),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: t.labelMedium
                    ?.copyWith(color: selected ? Colors.white : c.fg2),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.22)
                        : c.surface3,
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                  child: Text(
                    '$count',
                    style: t.labelSmall
                        ?.copyWith(color: selected ? Colors.white : c.fg3),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
