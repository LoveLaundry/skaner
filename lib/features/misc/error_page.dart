import 'package:flutter/material.dart';

import '../../ui/kit/primitives.dart';
import '../../ui/theme.dart';

/// Port of `features/quotations/pages/error-page.tsx`.
///
/// The web version recovers the status from the router's thrown error. Flutter
/// has no equivalent, so the values arrive as optional arguments and the screen
/// falls back to the generic 500 the route layer would have produced.
class ErrorPage extends StatelessWidget {
  const ErrorPage({
    super.key,
    this.status = 500,
    this.title,
    this.description,
    this.path,
    this.onRetry,
  });

  final int status;
  final String? title;
  final String? description;
  final String? path;
  final VoidCallback? onRetry;

  String get _title => title ?? switch (status) {
        404 => 'Page not found',
        401 => 'Unauthorised',
        403 => 'Forbidden',
        _ => 'Unexpected error',
      };

  String get _description => description ?? switch (status) {
        404 => "The page you're looking for doesn't exist or has been moved.",
        401 => 'You need to sign in to access this page.',
        403 => "You don't have permission to view this page.",
        _ => 'An unexpected error occurred. Go back and try again.',
      };

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    final notFound = status == 404;
    final (icon, iconFg, iconBg, iconBorder) = notFound
        ? (
            Icons.link_off_rounded,
            c.info,
            c.infoSoft,
            c.infoBorder,
          )
        : (
            Icons.warning_amber_rounded,
            c.danger,
            c.dangerSoft,
            c.dangerBorder,
          );

    return Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(Radii.xl),
                border: Border.all(color: c.line),
                boxShadow: Shadows.md,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: iconBg,
                      shape: BoxShape.circle,
                      border: Border.all(color: iconBorder),
                    ),
                    child: Icon(icon, size: 26, color: iconFg),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'ERROR $status',
                    style: t.labelSmall?.copyWith(
                      color: c.fgFaint,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(_title, style: t.titleLarge, textAlign: TextAlign.center),
                  const SizedBox(height: 6),
                  Text(
                    _description,
                    style: t.bodySmall?.copyWith(color: c.fgMuted),
                    textAlign: TextAlign.center,
                  ),
                  // Which screen blew up is the single most useful thing to know
                  // in a bug report, and it was the one thing missing.
                  if (path != null && path!.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: c.surface2,
                        borderRadius: BorderRadius.circular(Radii.md),
                        border: Border.all(color: c.line),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PAGE',
                            style: t.labelSmall?.copyWith(
                              color: c.fgFaint,
                              fontSize: 10,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            path!,
                            style: t.bodySmall
                                ?.copyWith(color: c.fg2, fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          label: 'Go back',
                          icon: Icons.arrow_back,
                          variant: AppButtonVariant.secondary,
                          block: true,
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AppButton(
                          label: 'Reload',
                          icon: Icons.refresh,
                          variant: AppButtonVariant.primary,
                          block: true,
                          onPressed: onRetry ??
                              () => Navigator.of(context).maybePop(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
