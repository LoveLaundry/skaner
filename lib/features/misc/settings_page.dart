import 'package:flutter/material.dart';

import '../../../config/api_config.dart';
import '../../../core/api/outbox_store.dart';
import '../../../core/utils/formatting.dart';
import '../../../state/app_scope.dart';
import '../../../state/theme_state.dart';
import '../../../ui/kit/data.dart';
import '../../../ui/kit/feedback.dart';
import '../../../ui/kit/inputs.dart';
import '../../../ui/kit/primitives.dart';
import '../../../ui/shell/app_shell.dart';
import '../../../ui/theme.dart';
import 'app_settings_store.dart';

/// Port of `features/quotations/pages/settings-page.tsx`, plus the operational
/// settings a mobile build needs that the web app gets from its env layer.
///
/// Appearance is the React screen one-for-one: nine theme presets, six font
/// sizes, and a live preview. After that come the four things a shipped APK
/// cannot get from a `.env` — backend URLs, the AI service key, device cache and
/// outbox maintenance, and signing out.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _urls = <String, TextEditingController>{};
  late final ThemeState _theme;
  late final TextEditingController _aiKey;
  bool _revealKey = false;
  int _outboxCount = 0;
  int _failedCount = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _theme = AppScope.read(context).theme;
    for (final service in ServiceNames.all) {
      _urls[service] = TextEditingController(text: AppSettingsStore.serviceUrl(service));
    }
    _aiKey = TextEditingController(text: AppSettingsStore.aiKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppSettingsStore.load().then((_) {
        if (!mounted) return;
        for (final service in ServiceNames.all) {
          _urls[service]!.text = AppSettingsStore.serviceUrl(service);
        }
        _aiKey.text = AppSettingsStore.aiKey;
        setState(() {});
      });
      _countOutbox();
    });
  }

  @override
  void dispose() {
    for (final c in _urls.values) {
      c.dispose();
    }
    _aiKey.dispose();
    super.dispose();
  }

  Future<void> _countOutbox() async {
    try {
      final outbox = AppScope.read(context).outbox;
      final all = await outbox.all();
      if (!mounted) return;
      setState(() {
        _outboxCount = all.where((r) => !r.isFailed).length;
        _failedCount = all.where((r) => r.isFailed).length;
      });
    } catch (_) {
      // Maintenance counters are informational; ignore an unavailable store.
    }
  }

  Future<void> _saveUrls() async {
    setState(() => _busy = true);
    final pending = {
      for (final service in ServiceNames.all)
        service: _urls[service]!.text.trim(),
    };
    for (final entry in pending.entries) {
      await AppSettingsStore.setServiceUrl(entry.key, entry.value);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    AppToast.success(context, 'Backend URLs updated');
  }

  Future<void> _saveKey() async {
    setState(() => _busy = true);
    await AppSettingsStore.setAiKey(_aiKey.text);
    if (!mounted) return;
    setState(() => _busy = false);
    AppToast.success(context, 'AI key saved');
  }

  Future<void> _resetUrls() async {
    final confirmed = await AppConfirmDialog.show(
      context,
      title: 'Reset server URLs?',
      message: 'All six services go back to their production defaults.',
      confirmLabel: 'Reset',
    );
    if (confirmed != true || !mounted) return;
    await AppSettingsStore.resetServiceUrls();
    if (!mounted) return;
    for (final service in ServiceNames.all) {
      _urls[service]!.text = AppSettingsStore.serviceUrl(service);
    }
    setState(() {});
    AppToast.info(context, 'Server URLs reset to defaults');
  }

  Future<void> _pruneCache() async {
    setState(() => _busy = true);
    await AppScope.read(context).cache.prune();
    if (!mounted) return;
    setState(() => _busy = false);
    AppToast.success(context, 'Stale cache entries removed');
  }

  Future<void> _clearCache() async {
    final confirmed = await AppConfirmDialog.show(
      context,
      title: 'Clear cached data?',
      message:
          'Cached lists are dropped from this device. Everything reloads from the '
          'server on the next visit.',
      confirmLabel: 'Clear cache',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    final cache = AppScope.read(context).cache;
    setState(() => _busy = true);
    await cache.clearAll();
    if (!mounted) return;
    setState(() => _busy = false);
    AppToast.success(context, 'Cached data cleared');
  }

  Future<void> _retryFailed() async {
    setState(() => _busy = true);
    final outbox = AppScope.read(context).outbox;
    final failed = await outbox.byStatus(OutboxStatus.failed);
    // Put them back in the queue rather than dropping the user's work.
    for (final row in failed) {
      await outbox.markPending(row.id ?? 0, error: null);
    }
    await outbox.refreshCounts();
    if (!mounted) return;
    setState(() => _busy = false);
    await _countOutbox();
    if (!mounted) return;
    AppToast.success(context,
        '${failed.length} item${failed.length == 1 ? '' : 's'} queued again');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    final theme = AppScope.of(context).theme;
    final user = AppScope.of(context).auth.user;

    return Column(
      children: [
        AppPageHeader(
          breadcrumb: const AppBreadcrumb(trail: ['Dashboard', 'Settings']),
          title: 'Settings',
          subtitle: 'Customize display, fonts and accessibility',
          busy: _busy,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              // Appearance listens to ThemeState directly: the shell does not
              // rebuild on a theme change, so the screen has to.
              AnimatedBuilder(
                animation: _theme,
                builder: (context, _) => Column(
                  children: [
              _sectionCard(
                title: 'Light themes',
                subtitle: 'Clean, bright themes for daytime use',
                icon: Icons.palette_outlined,
                iconBg: c.infoSoft,
                iconFg: c.info,
                iconBorder: c.infoBorder,
                themes: AppTheme.values.where((x) => !x.isDark).toList(),
              ),
              const SizedBox(height: 14),
              _sectionCard(
                title: 'Dark themes',
                subtitle: 'Easy on the eyes for nighttime and low-light use',
                icon: Icons.dark_mode_outlined,
                iconBg: c.brandSoft,
                iconFg: c.brand,
                iconBorder: c.brandBorder,
                themes: AppTheme.values.where((x) => x.isDark).toList(),
              ),
              const SizedBox(height: 14),
              AppCard(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.text_fields_rounded, size: 17, color: c.success),
                        const SizedBox(width: 8),
                        Text('Font size', style: t.titleSmall),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text('Controls text size across the entire application',
                        style: t.bodySmall?.copyWith(color: c.fgFaint)),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, box) {
                        final columns = box.maxWidth > 640 ? 6 : (box.maxWidth > 380 ? 3 : 2);
                        final width =
                            (box.maxWidth - (columns - 1) * 8) / columns;
                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final size in AppFontSize.values)
                              SizedBox(
                                width: width,
                                child: _option(
                                  selected: theme.fontSize == size,
                                  onTap: () => _theme.setFontSize(size),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(size.label,
                                          style: t.labelLarge?.copyWith(
                                              color:
                                                  theme.fontSize == size ? c.brandText : c.fg)),
                                      const SizedBox(height: 2),
                                      Text('${size.px.round()}px',
                                          style: t.labelSmall
                                              ?.copyWith(color: c.fgFaint)),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              AppCard(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.visibility_outlined, size: 17, color: c.warning),
                        const SizedBox(width: 8),
                        Text('Live preview', style: t.titleSmall),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text('How your text and colors look with current settings',
                        style: t.bodySmall?.copyWith(color: c.fgFaint)),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: c.surfaceSunken,
                        borderRadius: BorderRadius.circular(Radii.md),
                        border: Border.all(color: c.line),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Invoice #INV-20260811-0001', style: t.titleMedium),
                          const SizedBox(height: 6),
                          Text(
                            'This is secondary text — client details, dates and '
                            'descriptions appear in this color.',
                            style: t.bodySmall?.copyWith(color: c.fg2),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'This is tertiary text — labels, captions and metadata '
                            'appear here.',
                            style: t.bodySmall?.copyWith(color: c.fgMuted),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _previewTile('Client name', 'Hilton Colombo', c.fg),
                              _previewTile('Amount', Fmt.money(84500), c.fg),
                              _previewTile('Status', 'Paid', c.success),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Changes apply instantly and are saved automatically.',
                        style: t.labelSmall?.copyWith(color: c.fgFaint)),
                  ],
                ),
              ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              AppCard(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.dns_outlined, size: 17, color: c.info),
                        const SizedBox(width: 8),
                        Text('Backend services', style: t.titleSmall),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Point the app at a different deployment. Blank reverts that '
                      'service to its default.',
                      style: t.bodySmall?.copyWith(color: c.fgFaint),
                    ),
                    const SizedBox(height: 12),
                    for (final service in ServiceNames.all) ...[
                      AppField(
                        label: AppSettingsStore.labelFor(service),
                        child: AppTextInput(
                          controller: _urls[service],
                          hint: ApiConfig.baseFor(service),
                          keyboardType: TextInputType.url,
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: AppButton(
                            label: 'Save URLs',
                            icon: Icons.save_outlined,
                            variant: AppButtonVariant.primary,
                            block: true,
                            loading: _busy,
                            onPressed: _saveUrls,
                          ),
                        ),
                        const SizedBox(width: 10),
                        AppButton(
                          label: 'Reset',
                          icon: Icons.restart_alt,
                          onPressed: _resetUrls,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              AppCard(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.key_outlined, size: 17, color: c.brand),
                        const SizedBox(width: 8),
                        Text('AI service key', style: t.titleSmall),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Sent as X-API-Key when requesting AI insights.',
                      style: t.bodySmall?.copyWith(color: c.fgFaint),
                    ),
                    const SizedBox(height: 12),
                    AppTextInput(
                      controller: _aiKey,
                      obscureText: !_revealKey,
                      suffix: AppButton.icon(
                        icon: _revealKey
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        tooltip: _revealKey ? 'Hide' : 'Show',
                        onPressed: () => setState(() => _revealKey = !_revealKey),
                      ),
                    ),
                    const SizedBox(height: 10),
                    AppButton(
                      label: 'Save key',
                      icon: Icons.save_outlined,
                      variant: AppButtonVariant.primary,
                      block: true,
                      loading: _busy,
                      onPressed: _saveKey,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              AppCard(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.storage_outlined, size: 17, color: c.fg3),
                        const SizedBox(width: 8),
                        Text('This device', style: t.titleSmall),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Cached lists and queued writes live here. Removing them does '
                      'not affect the server.',
                      style: t.bodySmall?.copyWith(color: c.fgFaint),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _countTile('Queued writes', '$_outboxCount', c.fg2),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _countTile('Failed writes', '$_failedCount',
                              _failedCount > 0 ? c.danger : c.fg3),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        AppButton(
                          label: 'Remove stale cache',
                          icon: Icons.auto_delete_outlined,
                          onPressed: _pruneCache,
                        ),
                        AppButton(
                          label: 'Clear cache',
                          icon: Icons.delete_sweep_outlined,
                          onPressed: _clearCache,
                        ),
                        if (_failedCount > 0)
                          AppButton(
                            label: 'Retry failed',
                            icon: Icons.refresh,
                            variant: AppButtonVariant.primary,
                            onPressed: _retryFailed,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              AppCard(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.person_outline, size: 17, color: c.fg3),
                        const SizedBox(width: 8),
                        Text('Account', style: t.titleSmall),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      user == null
                          ? 'Not signed in'
                          : '${user.userName} · ${user.roleId.toUpperCase()}',
                      style: t.bodySmall?.copyWith(color: c.fgFaint),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: AppButton(
                            label: 'My profile',
                            icon: Icons.badge_outlined,
                            block: true,
                            onPressed: () =>
                                AppNavigatorPush.push(context, '/profile'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: AppButton(
                            label: 'Sign out',
                            icon: Icons.logout,
                            variant: AppButtonVariant.danger,
                            block: true,
                            onPressed: () async {
                              final services = AppScope.read(context);
                              final confirmed = await AppConfirmDialog.show(
                                context,
                                title: 'Sign out?',
                                message:
                                    'Queued writes for this account are discarded.',
                                confirmLabel: 'Sign out',
                                destructive: true,
                              );
                              if (confirmed != true) return;
                              await services.cache.clearAll();
                              await services.auth.logout();
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _previewTile(String label, String value, Color valueColor) {
    final c = context.c;
    final t = context.texts;
    return Container(
      width: 128,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: t.labelSmall?.copyWith(
                color: c.fgFaint, fontSize: 9.5, letterSpacing: 0.6),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: t.bodySmall?.copyWith(color: valueColor, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _countTile(String label, String value, Color valueColor) {
    final c = context.c;
    final t = context.texts;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: t.titleMedium?.copyWith(color: valueColor)),
          const SizedBox(height: 2),
          Text(label, style: t.labelSmall?.copyWith(color: c.fgFaint)),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconBg,
    required Color iconFg,
    required Color iconBorder,
    required List<AppTheme> themes,
  }) {
    final c = context.c;
    final t = context.texts;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(Radii.sm),
                  border: Border.all(color: iconBorder),
                ),
                child: Icon(icon, size: 16, color: iconFg),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.titleSmall),
                    Text(subtitle,
                        style: t.bodySmall?.copyWith(color: c.fgFaint)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, box) {
              final columns = box.maxWidth > 720 ? 3 : (box.maxWidth > 420 ? 2 : 1);
              final width = (box.maxWidth - (columns - 1) * 10) / columns;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final preset in themes)
                    SizedBox(
                      width: width,
                      child: _option(
                        selected: _theme.theme == preset,
                        onTap: () => _theme.setTheme(preset),
                        child: _themePreview(preset),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// Five swatches from the real palette, so the preview cannot drift from the
  /// theme it is previewing.
  Widget _themePreview(AppTheme preset) {
    final palette = AppThemeData.colorsFor(preset);
    final c = context.c;
    final t = context.texts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                preset.label,
                style: t.labelLarge?.copyWith(color: c.fg),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (preset.isDark)
              Icon(Icons.dark_mode_outlined, size: 13, color: c.fgFaint),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final swatch in [
              palette.canvas,
              palette.surface,
              palette.line2,
              palette.fg,
              palette.fgMuted,
            ])
              Container(
                width: 18,
                height: 18,
                margin: const EdgeInsets.only(right: 5),
                decoration: BoxDecoration(
                  color: swatch,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: palette.line2),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _option({
    required bool selected,
    required VoidCallback onTap,
    required Widget child,
  }) {
    final c = context.c;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: selected ? c.brandSoft : c.surface,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(
            color: selected ? c.brand : c.line,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Stack(
          children: [
            child,
            if (selected)
              Positioned(
                right: 0,
                top: 0,
                child: Icon(Icons.check_circle_rounded, size: 15, color: c.brand),
              ),
          ],
        ),
      ),
    );
  }
}
