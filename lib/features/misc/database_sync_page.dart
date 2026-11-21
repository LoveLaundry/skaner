import 'package:flutter/material.dart';

import '../../../config/api_config.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/utils/formatting.dart';
import '../../../data/resource_controller.dart';
import '../../../state/app_scope.dart';
import '../../../ui/kit/data.dart';
import '../../../ui/kit/feedback.dart';
import '../../../ui/kit/primitives.dart';
import '../../../ui/theme.dart';

/// Port of `features/quotations/pages/database-sync-page.tsx`.
///
/// Admin-only: the three database roles behind the bill service and the two
/// triggers that move rows between them. Both triggers are sent with
/// `allowQueueing: false` — a queued "sync now" would report success while
/// doing nothing, and the operator would be looking at a stale status card.
class DatabaseSyncPage extends StatefulWidget {
  const DatabaseSyncPage({super.key});

  @override
  State<DatabaseSyncPage> createState() => _DatabaseSyncPageState();
}

class _DatabaseSyncPageState extends State<DatabaseSyncPage> {
  late final ResourceController<Map<String, dynamic>> _status;
  Map<String, dynamic>? _report;
  bool _syncingLocal = false;
  bool _syncingSecondary = false;

  @override
  void initState() {
    super.initState();
    _status = ResourceController<Map<String, dynamic>>(
      key: 'database.status',
      cache: AppScope.read(context).cache,
      fetcher: _fetchStatus,
    )..addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => _status.load(force: true));
  }

  @override
  void dispose() {
    _status.removeListener(_onChanged);
    _status.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<Map<String, dynamic>> _fetchStatus() async {
    final s = AppScope.read(context);
    final payload =
        await s.api.get(ServiceNames.bills, '/admin/database/status');
    if (payload is Map) return Map<String, dynamic>.from(payload);
    return const {};
  }

  Future<void> _syncLocal() async {
    setState(() => _syncingLocal = true);
    final s = AppScope.read(context);
    try {
      final result = await s.api.write(
        ServiceNames.bills,
        'POST',
        '/admin/database/sync-local',
        allowQueueing: false,
      );
      if (!mounted) return;
      if (result is Map) {
        setState(() => _report = Map<String, dynamic>.from(result));
        if (str(_report!, ['status']) == 'SUCCESS') {
          AppToast.success(context, 'Local database synchronized');
        } else {
          AppToast.warning(context, 'Local sync completed with errors');
        }
      } else {
        AppToast.success(context, 'Local database synchronized');
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Synchronization failed: ${extractErrorMessage(e)}');
    } finally {
      if (mounted) setState(() => _syncingLocal = false);
    }
    await _status.refresh();
  }

  Future<void> _syncSecondary() async {
    setState(() => _syncingSecondary = true);
    final s = AppScope.read(context);
    try {
      final result = await s.api.write(
        ServiceNames.bills,
        'POST',
        '/admin/database/sync-secondary',
        allowQueueing: false,
      );
      if (!mounted) return;
      final processed =
          result is Map ? intOf(Map<String, dynamic>.from(result), ['jobs_processed']) : 0;
      AppToast.success(
          context, 'Secondary sync triggered — $processed job${processed == 1 ? '' : 's'} processed');
    } catch (e) {
      if (!mounted) return;
      AppToast.error(
          context, 'Failed to trigger secondary sync: ${extractErrorMessage(e)}');
    } finally {
      if (mounted) setState(() => _syncingSecondary = false);
    }
    await _status.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    final status = _status.data;
    final loading = _status.isLoading && !_status.hasData;
    final failed = _status.phase == LoadPhase.failed && !_status.hasData;

    return Column(
      children: [
        AppPageHeader(
          title: 'Database Synchronization',
          subtitle: 'Monitor and manage Main, Secondary, and Local database sync',
          busy: loading,
          actions: [
            AppButton(
              label: 'Refresh Status',
              icon: Icons.refresh_rounded,
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.sm,
              onPressed: () => _status.load(force: true),
            ),
          ],
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _status.load(force: true),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                if (loading)
                  const AppSkeletonList(count: 3, lines: 2)
                else if (failed)
                  AppErrorState(
                    title: 'Failed to load database status',
                    message: 'Could not reach the bill service. Check that the '
                        'service is running and that the signing secret matches '
                        'between the user and bill services.'
                        '${_status.error == null ? '' : '\n$_status.error'}',
                    onRetry: () => _status.load(force: true),
                  )
                else ...[
                  Row(
                    children: [
                      Expanded(
                        child: _statusCard(
                          title: 'Main Database',
                          icon: Icons.storage_outlined,
                          color: c.info,
                          role: str(status ?? const {}, ['main_status']),
                          online: _isOnline(status, 'main'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _statusCard(
                          title: 'Secondary Database',
                          icon: Icons.sync_rounded,
                          color: c.success,
                          role: _secondarySyncStatus(status),
                          online: _isOnline(status, 'secondary'),
                          action: AppButton(
                            label: _syncingSecondary ? 'Syncing…' : 'Sync Now',
                            icon: Icons.sync_rounded,
                            variant: AppButtonVariant.secondary,
                            size: AppButtonSize.xs,
                            loading: _syncingSecondary,
                            onPressed: _syncSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _statusCard(
                          title: 'Local Database',
                          icon: Icons.schedule_rounded,
                          color: c.warning,
                          role: 'Last synced: ${_lastSync(status)}',
                          online: _isOnline(status, 'local'),
                          action: AppButton(
                            label: _syncingLocal
                                ? 'Synchronizing…'
                                : 'Sync Local',
                            icon: Icons.storage_rounded,
                            size: AppButtonSize.xs,
                            loading: _syncingLocal,
                            onPressed: _syncingLocal ? null : _syncLocal,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Only an administrator can read or trigger these actions; '
                    'the server rejects anything else.',
                    style: t.labelSmall?.copyWith(color: c.fgFaint),
                  ),
                  if (_report != null) ...[
                    const SizedBox(height: 16),
                    _reportCard(_report!),
                  ],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  static bool _isOnline(Map<String, dynamic>? status, String role) {
    if (status == null) return false;
    final block = status[role];
    if (block is Map) {
      return str(Map<String, dynamic>.from(block), ['status']).toUpperCase() ==
          'ONLINE';
    }
    return false;
  }

  static String _secondarySyncStatus(Map<String, dynamic>? status) {
    if (status == null) return 'Sync: UNKNOWN';
    final block = status['secondary'];
    if (block is! Map) return 'Sync: UNKNOWN';
    final value = str(Map<String, dynamic>.from(block), ['sync_status'], 'UNKNOWN');
    return 'Sync: $value';
  }

  static String _lastSync(Map<String, dynamic>? status) {
    if (status == null) return 'Never';
    final block = status['local'];
    if (block is! Map) return 'Never';
    final value = pick(Map<String, dynamic>.from(block), ['last_sync']);
    if (value == null) return 'Never';
    final parsed = asDate(value);
    return parsed == null ? '$value' : Fmt.dateTime(parsed);
  }

  Widget _statusCard({
    required String title,
    required IconData icon,
    required Color color,
    required String role,
    required bool online,
    Widget? action,
  }) {
    final c = context.c;
    final t = context.texts;
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(title,
                    style: t.labelLarge?.copyWith(color: c.fg),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: online ? c.success : c.danger,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                online ? 'Online' : 'Offline',
                style: t.labelSmall?.copyWith(color: c.fgMuted),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            role,
            style: t.labelSmall?.copyWith(color: c.fgFaint),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (action != null) ...[
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: action),
          ],
        ],
      ),
    );
  }

  Widget _reportCard(Map<String, dynamic> report) {
    final c = context.c;
    final t = context.texts;
    final stats = _map(report, 'stats');
    final success = str(report, ['status']).toUpperCase() == 'SUCCESS';
    final duration = numOf(report, ['duration_seconds']);
    final entities = asRows(pick(report, ['entities']));

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Last Sync Report', style: t.titleSmall),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                success ? Icons.check_circle_outline : Icons.warning_amber_outlined,
                size: 16,
                color: success ? c.success : c.warning,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  success
                      ? 'Local database synchronized'
                      : 'Synchronization completed with errors',
                  style: t.labelLarge?.copyWith(color: c.fg),
                ),
              ),
              if (duration > 0)
                Text('${duration.toStringAsFixed(1)}s',
                    style: t.labelSmall?.copyWith(color: c.fgMuted)),
            ],
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.8,
            children: [
              for (final row in const [
                ('Checked', 'records_checked'),
                ('Inserted', 'records_inserted'),
                ('Updated', 'records_updated'),
                ('Deleted', 'records_deleted'),
                ('Unchanged', 'records_unchanged'),
                ('Errors', 'errors'),
              ])
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(Radii.sm),
                    border: Border.all(color: c.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(row.$1,
                          style: t.labelSmall?.copyWith(color: c.fgMuted)),
                      Text(Fmt.count(intOf(stats, [row.$2])),
                          style: t.titleMedium?.copyWith(
                              color: row.$1 == 'Errors' &&
                                      intOf(stats, [row.$2]) > 0
                                  ? c.danger
                                  : c.fg)),
                    ],
                  ),
                ),
            ],
          ),
          if (entities.isNotEmpty) ...[            const SizedBox(height: 14),
            Text('By entity', style: t.labelMedium?.copyWith(color: c.fgMuted)),
            const SizedBox(height: 6),
            for (final e in entities) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(str(e, ['entity'], '—'),
                          style: t.bodySmall?.copyWith(color: c.fg),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    Text('+${intOf(e, ['inserted'])}',
                        style: t.labelSmall?.copyWith(color: c.success)),
                    const SizedBox(width: 10),
                    Text('~${intOf(e, ['updated'])}',
                        style: t.labelSmall?.copyWith(color: c.info)),
                    const SizedBox(width: 10),
                    Text('−${intOf(e, ['deleted'])}',
                        style: t.labelSmall?.copyWith(color: c.danger)),
                    const SizedBox(width: 10),
                    Text('=${intOf(e, ['unchanged'])}',
                        style: t.labelSmall?.copyWith(color: c.fgFaint)),
                  ],
                ),
              ),
            ],
          ],
          const SizedBox(height: 10),
          Text(
            'Started ${Fmt.dateTime(pick(report, ['started_at']))} · '
            'finished ${Fmt.dateTime(pick(report, ['completed_at']))}',
            style: t.labelSmall?.copyWith(color: c.fgFaint),
          ),
        ],
      ),
    );
  }

  static Map<String, dynamic> _map(Map<String, dynamic> row, String key) {
    final v = row[key];
    return v is Map ? Map<String, dynamic>.from(v) : const {};
  }
}
