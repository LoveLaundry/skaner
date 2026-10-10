import 'package:flutter/material.dart';

import '../theme.dart';
import 'primitives.dart';

/// Port of `components/ui/loading-spinner.tsx` + `LoveLoader.tsx`.
class AppSpinner extends StatelessWidget {
  const AppSpinner({super.key, this.size = 18, this.color, this.strokeWidth = 2});

  final double size;
  final Color? color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          strokeWidth: strokeWidth,
          color: color ?? context.c.brand,
        ),
      );
}

/// Full-bleed centred loader used while a page resolves its first payload.
class AppLoader extends StatelessWidget {
  const AppLoader({super.key, this.label, this.compact = false});

  final String? label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Center(
      child: compact
          ? AppSpinner(size: 20)
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppSpinner(size: 26),
                if (label != null) ...[
                  const SizedBox(height: 12),
                  Text(label!, style: context.texts.bodySmall?.copyWith(color: c.fgMuted)),
                ],
              ],
            ),
    );
  }
}

/// Port of `components/ui/skeleton.tsx`. Shimmer sweep on a hairline block.
class AppSkeleton extends StatefulWidget {
  const AppSkeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = Radii.sm,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<AppSkeleton> createState() => _AppSkeletonState();
}

class _AppSkeletonState extends State<AppSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1250),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final base = context.isDark ? c.surface3 : const Color(0xFFEEF0F4);
    final via = c.line;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1.6 + t * 3.2, 0),
              end: Alignment(-0.6 + t * 3.2, 0),
              colors: [base, via, base],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}

/// Convenience skeleton set for list rows and card bodies.
class AppSkeletonList extends StatelessWidget {
  const AppSkeletonList({super.key, this.count = 6, this.lines = 2});

  final int count;
  final int lines;

  @override
  Widget build(BuildContext context) => ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, _) => AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppSkeleton(width: 140, height: 14),
              const SizedBox(height: 10),
              for (var i = 0; i < lines; i++) ...[
                AppSkeleton(height: 11, width: i == lines - 1 ? 180 : null),
                if (i < lines - 1) const SizedBox(height: 7),
              ],
            ],
          ),
        ),
      );
}

/// Port of `components/ui/empty-state.tsx`.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
    this.secondaryAction,
    this.compact = false,
  });

  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;
  final Widget? secondaryAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: 24, vertical: compact ? 24 : 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: compact ? 40 : 52,
              height: compact ? 40 : 52,
              decoration: BoxDecoration(
                color: c.surface2,
                shape: BoxShape.circle,
                border: Border.all(color: c.line),
              ),
              child: Icon(icon, size: compact ? 19 : 24, color: c.fgFaint),
            ),
            SizedBox(height: compact ? 12 : 16),
            Text(title,
                style: t.titleSmall, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                style: t.bodySmall?.copyWith(color: c.fgMuted),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              SizedBox(height: compact ? 14 : 20),
              action!,
            ],
            if (secondaryAction != null) ...[
              const SizedBox(height: 8),
              secondaryAction!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Port of `components/ui/error-state.tsx`. Retry is the default second slot.
class AppErrorState extends StatelessWidget {
  const AppErrorState({
    super.key,
    this.message,
    this.onRetry,
    this.title = 'Something went wrong',
    this.icon = Icons.error_outline,
    this.offline = false,
  });

  final String? message;
  final VoidCallback? onRetry;
  final String title;
  final IconData icon;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: offline ? c.warningSoft : c.dangerSoft,
                shape: BoxShape.circle,
                border: Border.all(
                    color: offline ? c.warningBorder : c.dangerBorder),
              ),
              child: Icon(offline ? Icons.cloud_off_outlined : icon,
                  size: 24, color: offline ? c.warning : c.danger),
            ),
            const SizedBox(height: 16),
            Text(title, style: context.texts.titleSmall),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                style: context.texts.bodySmall?.copyWith(color: c.fgMuted),
                textAlign: TextAlign.center,
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              AppButton(
                label: 'Retry',
                variant: AppButtonVariant.secondary,
                icon: Icons.refresh,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Port of `components/ui/notice.tsx`.
class AppNotice extends StatelessWidget {
  const AppNotice({
    super.key,
    required this.message,
    this.tone = AppTone.neutral,
    this.title,
    this.onClose,
    this.action,
  });

  final String message;
  final AppTone tone;
  final String? title;
  final VoidCallback? onClose;
  final Widget? action;

  static IconData iconFor(AppTone tone) => switch (tone) {
        AppTone.neutral => Icons.info_outline,
        AppTone.brand => Icons.star_outline,
        AppTone.success => Icons.check_circle_outline,
        AppTone.warning => Icons.warning_amber_outlined,
        AppTone.danger => Icons.error_outline,
        AppTone.info => Icons.lightbulb_outline,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    final (fg, bg, border) = tone.resolve(c);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(iconFor(tone), size: 17, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(title!,
                        style: t.labelLarge?.copyWith(color: fg)),
                  ),
                Text(message,
                    style: t.bodySmall?.copyWith(color: fg.withValues(alpha: 0.95))),
              ],
            ),
          ),
          if (action != null) action!,
          if (onClose != null)
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              onPressed: onClose,
              visualDensity: VisualDensity.compact,
              color: fg,
              tooltip: 'Dismiss',
            ),
        ],
      ),
    );
  }
}

/// Port of `components/ui/dialog.tsx`.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    this.body,
    this.actions = const [],
    this.icon,
    this.maxWidth = 460,
  });

  final String title;
  final Widget? body;
  final List<Widget> actions;
  final IconData? icon;
  final double maxWidth;

  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    Widget? body,
    List<Widget> actions = const [],
    IconData? icon,
    bool barrierDismissible = true,
    double maxWidth = 460,
  }) =>
      showDialog<T>(
        context: context,
        barrierDismissible: barrierDismissible,
        builder: (_) => AppDialog(
          title: title,
          body: body,
          actions: actions,
          icon: icon,
          maxWidth: maxWidth,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 18, color: c.fg3),
                      const SizedBox(width: 8),
                    ],
                    Expanded(child: Text(title, style: t.titleMedium)),
                  ],
                ),
                if (body != null) ...[
                  const SizedBox(height: 12),
                  Flexible(child: SingleChildScrollView(child: body)),
                ],
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      for (final a in actions)
                        Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: a),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Port of `components/ui/confirm-dialog.tsx`.
class AppConfirmDialog extends StatelessWidget {
  const AppConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmLabel = 'Confirm',
    this.cancelLabel = 'Cancel',
    this.destructive = false,
    this.icon,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;
  final IconData? icon;

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool destructive = false,
    IconData? icon,
  }) async {
    final result = await AppDialog.show<bool>(
      context,
      title: title,
      icon: icon ??
          (destructive ? Icons.warning_amber_outlined : Icons.help_outline),
      body: Text(message, style: context.texts.bodyMedium),
      actions: [
        AppButton(
          label: cancelLabel,
          variant: AppButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: confirmLabel,
          variant: destructive
              ? AppButtonVariant.danger
              : AppButtonVariant.primary,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) => throw UnimplementedError();
}

/// Toast helpers — Flutter's SnackBar with the app's success/danger mapping.
class AppToast {
  AppToast._();

  static void success(BuildContext context, String message) =>
      _show(context, message, AppTone.success);

  static void error(BuildContext context, String message) =>
      _show(context, message, AppTone.danger);

  static void info(BuildContext context, String message) =>
      _show(context, message, AppTone.info);

  static void warning(BuildContext context, String message) =>
      _show(context, message, AppTone.warning);

  static void _show(BuildContext context, String message, AppTone tone) {
    final c = context.c;
    final (fg, bg, _) = tone.resolve(c);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(AppNotice.iconFor(tone), size: 17, color: fg),
              const SizedBox(width: 10),
              Expanded(
                child: Text(message,
                    style: TextStyle(color: c.surface, fontSize: context.fs(13.5))),
              ),
            ],
          ),
          backgroundColor: c.fg,
          duration: const Duration(seconds: 3),
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        ),
      );
  }
}

/// Port of `components/ui/dropdown-menu.tsx` as a sheet-friendly menu surface.
class AppMenuButton extends StatelessWidget {
  const AppMenuButton({
    super.key,
    required this.label,
    required this.items,
    this.icon,
    this.variant = AppButtonVariant.secondary,
  });

  final String label;
  final List<AppMenuItem> items;
  final IconData? icon;
  final AppButtonVariant variant;

  @override
  Widget build(BuildContext context) => AppButton(
        label: label,
        icon: icon,
        variant: variant,
        trailingIcon: Icons.expand_more,
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          builder: (sheetCtx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final item in items)
                  ListTile(
                    leading: item.icon == null ? null : Icon(item.icon),
                    title: Text(item.label),
                    subtitle:
                        item.subtitle == null ? null : Text(item.subtitle!),
                    enabled: item.enabled,
                    trailing: item.trailing,
                    onTap: item.enabled && item.onTap != null
                        ? () {
                            Navigator.of(sheetCtx).pop();
                            item.onTap!();
                          }
                        : null,
                  ),
              ],
            ),
          ),
        ),
      );
}

class AppMenuItem {
  const AppMenuItem({
    required this.label,
    this.onTap,
    this.icon,
    this.subtitle,
    this.enabled = true,
    this.trailing,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final String? subtitle;
  final bool enabled;
  final Widget? trailing;
}
