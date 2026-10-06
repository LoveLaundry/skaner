import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/query_cache.dart';
import '../../core/api/sync_engine.dart';
import '../../core/utils/formatting.dart';
import '../theme.dart';

/// Port of `components/ui/sync-status-bar.tsx`: a passive, always-visible line
/// that states where the data on screen came from. Tapping it explains why.
class AppSyncStatusBar extends StatelessWidget {
  const AppSyncStatusBar({
    super.key,
    required this.status,
    required this.label,
    this.updatedAt,
    this.onTap,
  });

  final CacheStatus status;
  final DateTime? updatedAt;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    final (dot, text, showSpinner) = switch (status) {
      CacheStatus.syncedFailed => (c.danger, 'Sync unavailable', false),
      CacheStatus.syncing => (c.brand, 'Updating…', true),
      CacheStatus.stale => (c.warning, Fmt.relative(updatedAt), false),
      CacheStatus.offline => (c.fgFaint, Fmt.relative(updatedAt), false),
      CacheStatus.fresh => (c.success, 'Just now', false),
    };
    final suffix = switch (status) {
      CacheStatus.stale => ' · Cached',
      CacheStatus.offline => ' · Offline',
      CacheStatus.syncedFailed => ' · Sync unavailable',
      _ => '',
    };

    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: c.surfaceSunken,
          border: Border(bottom: BorderSide(color: c.line)),
        ),
        child: Row(
          children: [
            if (showSpinner)
              SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(strokeWidth: 1.6, color: dot),
              )
            else
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
            const SizedBox(width: 7),
            Text('$label:',
                style: t.labelSmall?.copyWith(color: c.fgMuted)),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                '$text$suffix',
                style: t.labelSmall?.copyWith(color: c.fg2),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

}

/// Port of `components/ui/offline-sync-bar.tsx`. Passive indicator with an
/// optional retry; it never blocks the operator's work.
class AppOfflineSyncBar extends StatefulWidget {
  const AppOfflineSyncBar({super.key, this.engine});

  final SyncEngine? engine;

  @override
  State<AppOfflineSyncBar> createState() => _AppOfflineSyncBarState();
}

class _AppOfflineSyncBarState extends State<AppOfflineSyncBar> {
  SyncSnapshot? _snap;
  Timer? _timer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final e = widget.engine;
    if (e == null) return;
    _snap = e.snapshot;
    e.addListener(_onChange);
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) _onChange();
    });
  }

  @override
  void dispose() {
    widget.engine?.removeListener(_onChange);
    _timer?.cancel();
    super.dispose();
  }

  void _onChange() {
    final next = widget.engine?.snapshot;
    if (next == null) return;
    setState(() => _snap = next);
  }

  @override
  Widget build(BuildContext context) {
    final s = _snap;
    if (s == null) return const SizedBox.shrink();
    final queued = s.pending + (s.syncing ? 1 : 0);
    if (queued == 0 && s.failed == 0) return const SizedBox.shrink();

    return Material(
      color: s.failed > 0 ? context.c.dangerSoft : context.c.warningSoft,
      child: InkWell(
        onTap: s.failed > 0 && !_busy ? _retry : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Icon(
                s.failed > 0 ? Icons.error_outline : Icons.cloud_upload_outlined,
                size: 16,
                color: s.failed > 0 ? context.c.danger : context.c.warning,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.failed > 0
                      ? '${s.failed} change${s.failed == 1 ? '' : 's'} failed to sync · tap to retry'
                      : s.online
                          ? 'Syncing $queued queued change${queued == 1 ? '' : 's'}…'
                          : 'Offline · $queued change${queued == 1 ? '' : 's'} queued',
                  style: context.texts.labelMedium?.copyWith(
                    color: s.failed > 0 ? context.c.danger : context.c.warning,
                  ),
                ),
              ),
              if (_busy)
                const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(strokeWidth: 1.8))
              else if (s.failed > 0)
                Icon(Icons.refresh,
                    size: 16,
                    color: context.c.danger.withValues(alpha: 0.8)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _retry() async {
    setState(() => _busy = true);
    try {
      await widget.engine?.retryFailed();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// Port of `components/ui/pending-sync-indicators.tsx` — per-row state for
/// records that are still sitting in the outbox.
class PendingSyncIndicator extends StatelessWidget {
  const PendingSyncIndicator({super.key, required this.status, this.label});

  /// One of `VERIFIED`, `SYNCING`, `PENDING`, `FAILED`.
  final String? status;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final (text, fg, bg, border, icon) = switch (
        (status ?? 'PENDING').toUpperCase()) {
      'VERIFIED' => (
          label ?? 'Synced',
          context.c.success,
          context.c.successSoft,
          context.c.successBorder,
          Icons.cloud_done_outlined
        ),
      'SYNCING' => (
          label ?? 'Syncing',
          context.c.info,
          context.c.infoSoft,
          context.c.infoBorder,
          Icons.sync
        ),
      'FAILED' => (
          label ?? 'Failed',
          context.c.danger,
          context.c.dangerSoft,
          context.c.dangerBorder,
          Icons.cloud_off_outlined
        ),
      _ => (
          label ?? 'Queued',
          context.c.warning,
          context.c.warningSoft,
          context.c.warningBorder,
          Icons.cloud_queue_outlined
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10.5, color: fg),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600, color: fg),
          ),
        ],
      ),
    );
  }
}

/// One searchable destination for the command palette.
class AppCommandItem {
  const AppCommandItem({
    required this.label,
    required this.route,
    this.icon,
    this.group = 'Navigate',
    this.keywords = const [],
  });

  final String label;
  final String route;
  final IconData? icon;
  final String group;
  final List<String> keywords;
}

/// Port of `components/ui/command-search.tsx` — the operator's ⌘K path to any
/// permission-gated destination or quick action.
class AppCommandSearch extends StatefulWidget {
  const AppCommandSearch({
    super.key,
    required this.items,
    this.placeholder = 'Search or jump to…',
    this.onNavigate,
  });

  final List<AppCommandItem> items;
  final String placeholder;
  final void Function(String route)? onNavigate;

  static Future<void> show(
    BuildContext context, {
    required List<AppCommandItem> items,
    String placeholder = 'Search or jump to…',
    void Function(String route)? onNavigate,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => AppCommandSearch(
          items: items,
          placeholder: placeholder,
          onNavigate: onNavigate,
        ),
      );

  @override
  State<AppCommandSearch> createState() => _AppCommandSearchState();
}

class _AppCommandSearchState extends State<AppCommandSearch> {
  final _q = TextEditingController();
  final _focus = FocusNode();
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _q.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<AppCommandItem> get _filtered {
    final q = _q.text.trim().toLowerCase();
    if (q.isEmpty) return widget.items;
    return widget.items.where((i) {
      return i.label.toLowerCase().contains(q) ||
          i.group.toLowerCase().contains(q) ||
          i.keywords.any((k) => k.toLowerCase().contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    final results = _filtered;
    final grouped = <String, List<AppCommandItem>>{};
    for (final r in results) {
      grouped.putIfAbsent(r.group, () => []).add(r);
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.72,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: TextField(
                  controller: _q,
                  focusNode: _focus,
                  onChanged: (_) => setState(() => _index = 0),
                  onSubmitted: (_) => _activate(results),
                  textInputAction: TextInputAction.go,
                  decoration: InputDecoration(
                    hintText: widget.placeholder,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _q.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () => setState(() {
                              _q.clear();
                              _index = 0;
                            }),
                          ),
                  ),
                ),
              ),
              Divider(height: 1, color: c.line),
              Expanded(
                child: results.isEmpty
                    ? Center(
                        child: Text('No matching screens or actions',
                            style: t.bodySmall?.copyWith(color: c.fgFaint)),
                      )
                    : ListView(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        children: [
                          for (final entry in grouped.entries) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 12, 16, 6),
                              child: Text(
                                entry.key.toUpperCase(),
                                style: t.labelSmall?.copyWith(
                                    color: c.fgFaint, fontSize: 10),
                              ),
                            ),
                            for (final item in entry.value)
                              _CommandRow(
                                item: item,
                                selected: identical(
                                    results[_indexOf(results, item)], results[_index])
                                    ? _indexOf(results, item) == _index
                                    : false,
                                onTap: () => _go(item),
                              ),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _indexOf(List<AppCommandItem> list, AppCommandItem item) {
    for (var i = 0; i < list.length; i++) {
      if (identical(list[i], item)) return i;
    }
    return -1;
  }

  void _activate(List<AppCommandItem> results) {
    if (results.isEmpty) return;
    _go(results[_index.clamp(0, results.length - 1)]);
  }

  void _go(AppCommandItem item) {
    Navigator.of(context).pop();
    widget.onNavigate?.call(item.route);
  }
}

class _CommandRow extends StatelessWidget {
  const _CommandRow({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final AppCommandItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? c.surfaceHover : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            Icon(item.icon ?? Icons.chevron_right,
                size: 17, color: selected ? c.brand : c.fgFaint),
            const SizedBox(width: 12),
            Expanded(
              child: Text(item.label, style: context.texts.bodyLarge),
            ),
            Icon(Icons.north_west, size: 13, color: c.fgFaint),
          ],
        ),
      ),
    );
  }
}
