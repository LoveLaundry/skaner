import 'package:flutter/material.dart';

import '../../core/api/query_cache.dart';
import '../../core/models/json.dart' as json;
import '../../core/models/linen.dart';
import '../../core/utils/formatting.dart';
import '../../data/resource_controller.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/kit/shell_parts.dart';
import '_linen_shared.dart';
import 'garment_detail_page.dart';
import '../../ui/theme.dart';

/// Port of `features/linen/pages/linen-profile.tsx`.
///
/// The page answers two questions for one piece: what does the tag say, and
/// where has it been. The quick actions are the whole scan vocabulary — the web
/// app offers every entry in `SCAN_ACTIONS` rather than only the subset valid
/// for the current status, so a piece that arrived out of order can still be
/// moved forward by hand.
class LinenTrackingDetailPage extends StatefulWidget {
  const LinenTrackingDetailPage({super.key, required this.docId});

  final String docId;

  @override
  State<LinenTrackingDetailPage> createState() =>
      _LinenTrackingDetailPageState();
}

class _LinenTrackingDetailPageState extends State<LinenTrackingDetailPage> {
  late final ResourceController<LinenItem> _item;
  late final ResourceController<List<LinenEvent>> _events;

  String? _pending;

  @override
  void initState() {
    super.initState();
    final cache = AppScope.read(context).cache;
    _item = ResourceController(
      key: 'linen-${widget.docId}',
      cache: cache,
      fetcher: _fetchItem,
    )..addListener(_onItem);
    _events = ResourceController(
      key: 'linen-${widget.docId}-events',
      cache: cache,
      fetcher: _fetchEvents,
    )..addListener(_onEvents);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _item.load(force: true);
      _events.load(force: true);
    });
  }

  @override
  void dispose() {
    _item.removeListener(_onItem);
    _item.dispose();
    _events.removeListener(_onEvents);
    _events.dispose();
    super.dispose();
  }

  void _onItem() {
    if (mounted) setState(() {});
  }

  void _onEvents() {
    if (mounted) setState(() {});
  }

  Future<LinenItem> _fetchItem() async {
    final payload = await AppScope.read(context)
        .api
        .get(linenService, LinenApi.one(widget.docId));
    return LinenItem.fromJson(json.asMap(payload));
  }

  Future<List<LinenEvent>> _fetchEvents() async {
    final payload = await AppScope.read(context).api.get(
      linenService,
      LinenApi.events(widget.docId),
      query: const {'skip': 0, 'limit': 100},
    );
    final map = json.asMap(payload);
    return json
        .asMapList(map['items'] ?? payload)
        .map(LinenEvent.fromJson)
        .toList();
  }

  Future<void> _reload() async {
    await Future.wait([_item.load(force: true), _events.load(force: true)]);
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final c = context.c;
    final item = _item.data;

    return Scaffold(
      appBar: AppBar(
        title: Text(item?.linenId ?? 'Linen'),
        actions: [
          if (item != null)
            AppButton.icon(
              icon: Icons.qr_code,
              tooltip: 'Show the tag',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => GarmentDetailPage(code: item.linenId),
                ),
              ),
            ),
          AppButton.icon(
            icon: Icons.refresh,
            tooltip: 'Refresh',
            loading: _item.isLoading || _events.isLoading,
            onPressed: _reload,
          ),
        ],
      ),
      body: Column(
        children: [
          AppSyncStatusBar(
            status: _item.status,
            updatedAt: _item.lastUpdated,
            label: 'Linen',
          ),
          AppOfflineSyncBar(engine: services.sync),
          Expanded(
            child: RefreshIndicator(
              color: c.brand,
              onRefresh: _reload,
              child: _item.phase == LoadPhase.failed && item == null
                  ? ListView(
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.4,
                          child: AppErrorState(
                            message: _item.error ??
                                'This linen could not be loaded.',
                            offline: _item.status == CacheStatus.offline,
                            onRetry: _reload,
                          ),
                        ),
                      ],
                    )
                  : item == null
                      ? const AppSkeletonList()
                      : _Body(
                          item: item,
                          events: _events.data ?? const [],
                          eventsStatus: _events.status,
                          pending: _pending,
                          onAction: _runAction,
                        ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runAction(LinenScanAction action) async {
    final item = _item.data;
    if (item == null) return;
    setState(() => _pending = action.value);
    final ok = await postLinenScan(context, item.id, action);
    if (!mounted) return;
    setState(() => _pending = null);
    if (ok) await _reload();
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.item,
    required this.events,
    required this.eventsStatus,
    required this.pending,
    required this.onAction,
  });

  final LinenItem item;
  final List<LinenEvent> events;
  final CacheStatus eventsStatus;
  final String? pending;
  final ValueChanged<LinenScanAction> onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  LinenStatusBadge(status: item.status, compact: false),
                  const Spacer(),
                  Text(
                    Fmt.qty(item.washCount),
                    style: t.titleMedium?.copyWith(color: c.fg3),
                  ),
                  const SizedBox(width: 4),
                  Text('washes',
                      style: t.labelSmall?.copyWith(color: c.fgFaint)),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                item.linenId,
                style: t.headlineSmall?.copyWith(
                  color: c.fg,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${item.itemType} · ${item.clientName}',
                style: t.bodySmall?.copyWith(color: c.fgMuted),
              ),
              if (item.location != null && item.location!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.place_outlined, size: 14, color: c.fgFaint),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(item.location!,
                          style: t.bodySmall?.copyWith(color: c.fg2)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        AppCard(
          title: 'Item details',
          child: LinenDetailGrid(
            entries: [
              ('Category', item.categoryLabel),
              ('Item type', item.itemType),
              ('Client', item.clientName),
              ('Department', item.department ?? '—'),
              ('Size', item.size ?? '—'),
              ('Color', item.color ?? '—'),
              ('Condition', item.conditionLabel),
              ('Wash count', '${item.washCount}'),
              ('Last washed', Fmt.date(item.lastWashedDate)),
              ('Last scanned', Fmt.date(item.lastScannedDate)),
              ('Created', Fmt.date(item.createdAt)),
              ('Last updated', Fmt.date(item.updatedAt)),
              ('Retirement', Fmt.date(item.retirementDate)),
            ],
          ),
        ),
        if (item.description != null &&
            item.description!.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          AppCard(
            title: 'Description',
            child: Text(
              item.description!,
              style: context.texts.bodyMedium?.copyWith(color: c.fg2),
            ),
          ),
        ],
        if (item.notes != null && item.notes!.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          AppNotice(message: item.notes!, tone: AppTone.neutral),
        ],
        const SizedBox(height: 10),
        if (item.allowedActions.isNotEmpty)
          AppCard(
            child: LinenQuickActions(
              actions: LinenScanAction.all,
              pendingValue: pending,
              onAction: onAction,
            ),
          )
        else
          const AppNotice(
            message:
                'This piece is retired — no further scans can be recorded.',
            tone: AppTone.neutral,
          ),
        const SizedBox(height: 10),
        AppCard(
          title: 'Movement history',
          subtitle: events.isEmpty
              ? null
              : '${events.length} event${events.length == 1 ? '' : 's'}'
                  '${eventsStatus == CacheStatus.offline ? ' · offline' : ''}',
          child: LinenTimeline(events: events),
        ),
      ],
    );
  }
}
