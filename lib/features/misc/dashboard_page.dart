import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../config/api_config.dart';
import '../../../config/app_config.dart';
import '../../../core/api/query_cache.dart';
import '../../../core/utils/formatting.dart';
import '../../../data/resource_controller.dart';
import '../../../state/app_scope.dart';
import '../../../ui/kit/data.dart';
import '../../../ui/kit/feedback.dart';
import '../../../ui/kit/primitives.dart';
import '../../../ui/kit/shell_parts.dart';
import '../../../ui/shell/app_shell.dart';
import '../../../ui/theme.dart';

/// Port of `features/quotations/pages/dashboard-page.tsx`.
///
/// The period metrics, the previous-period comparison, the aging buckets and the
/// charts all come from `/dashboard/summary` and its siblings; the only figures
/// computed here are the ones the React page also computes in the browser —
/// percentage deltas, alert thresholds and the quotation funnel counts, which
/// come from the quotation list the summary endpoint does not carry.
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  static const _periods = ['day', 'week', 'month', 'quarter', 'year'];
  static const _periodLabels = ['Today', 'Week', 'Month', 'Quarter', 'Year'];

  int _period = 2;
  bool _exporting = false;

  // Rebuilt by _setPeriod(), so it cannot be final.
  late ResourceController<Map<String, dynamic>> _summary;
  late final ResourceController<List<Map<String, dynamic>>> _activity;
  late final ResourceController<List<Map<String, dynamic>>> _clientWise;
  late final ResourceController<List<Map<String, dynamic>>> _itemWise;
  late final ResourceController<Map<String, dynamic>> _aging;
  late final ResourceController<List<Map<String, dynamic>>> _yearly;
  late final ResourceController<List<Map<String, dynamic>>> _todayDeliveries;
  late final ResourceController<List<Map<String, dynamic>>> _quotations;

  @override
  void initState() {
    super.initState();
    _summary = _one('dashboard.summary', _fetchSummary);
    _activity = _rows('dashboard.activity',
        () => _get('/dashboard/recent-activity', query: {'limit': 10}));
    _clientWise =
        _rows('reports.client-wise', () => _get('/reports/client-wise'));
    _itemWise = _rows('reports.item-wise', () => _get('/reports/item-wise'));
    _aging = _one('dashboard.aging', _fetchAging);
    _yearly = _rows('dashboard.yearly', () => _get('/dashboard/yearly-trend'));
    _todayDeliveries =
        _rows('dashboard.today', () => _get('/dashboard/today-deliveries'));
    _quotations = _rows('quotations', () async {
      final s = AppScope.read(context);
      return asRows(await s.api.get(ServiceNames.quotation, '/quotations'));
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _summary.load(force: true);
      for (final c in [
        _activity,
        _clientWise,
        _itemWise,
        _aging,
        _yearly,
        _todayDeliveries,
        _quotations,
      ]) {
        c.load(force: true);
      }
    });
  }

  ResourceController<Map<String, dynamic>> _one(
    String key,
    Future<Map<String, dynamic>> Function() fetcher,
  ) =>
      ResourceController<Map<String, dynamic>>(
        key: key,
        cache: AppScope.read(context).cache,
        fetcher: fetcher,
      )..addListener(_onChanged);

  ResourceController<List<Map<String, dynamic>>> _rows(
    String key,
    Future<List<Map<String, dynamic>>> Function() fetcher,
  ) =>
      ResourceController<List<Map<String, dynamic>>>(
        key: key,
        cache: AppScope.read(context).cache,
        fetcher: fetcher,
      )..addListener(_onChanged);

  Future<Map<String, dynamic>> _fetchSummary() async {
    final s = AppScope.read(context);
    final payload = await s.api.get(ServiceNames.bills, '/dashboard/summary',
        query: {'period': _periods[_period]});
    if (payload is Map) return Map<String, dynamic>.from(payload);
    return const {};
  }

  Future<Map<String, dynamic>> _fetchAging() async {
    final s = AppScope.read(context);
    try {
      final payload =
          await s.api.get(ServiceNames.bills, '/dashboard/outstanding-aging');
      if (payload is Map) return Map<String, dynamic>.from(payload);
    } catch (_) {
      // The aging buckets are an extra read; a deployment without them still
      // renders every other part of the dashboard.
    }
    return const {};
  }

  Future<List<Map<String, dynamic>>> _get(String path,
      {Map<String, dynamic>? query}) async {
    final s = AppScope.read(context);
    return asRows(await s.api.get(ServiceNames.bills, path, query: query));
  }

  @override
  void dispose() {
    for (final c in [
      _summary,
      _activity,
      _clientWise,
      _itemWise,
      _aging,
      _yearly,
      _todayDeliveries,
      _quotations,
    ]) {
      c.removeListener(_onChanged);
      c.dispose();
    }
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _setPeriod(int i) {
    if (i == _period) return;
    setState(() => _period = i);
    _summary
      ..removeListener(_onChanged)
      ..dispose();
    _summary = _one('dashboard.summary.${_periods[i]}', _fetchSummary)
      ..load(force: true);
  }

  Future<void> _reload() async {
    await Future.wait([
      _summary.load(force: true),
      _activity.load(force: true),
      _clientWise.load(force: true),
      _itemWise.load(force: true),
      _aging.load(force: true),
      _yearly.load(force: true),
      _todayDeliveries.load(force: true),
      _quotations.load(force: true),
    ]);
  }

  // ── Metric access ──────────────────────────────────────────────────────────

  Map<String, dynamic> get _current {
    final data = _summary.data;
    if (data == null) return const {};
    final v = data['current'];
    return v is Map ? Map<String, dynamic>.from(v) : const {};
  }

  Map<String, dynamic> get _previous {
    final data = _summary.data;
    if (data == null) return const {};
    final v = data['previous'];
    return v is Map ? Map<String, dynamic>.from(v) : const {};
  }

  double get _revenue => numOf(_current, ['revenue']);
  double get _collected => numOf(_current, ['collected']);
  double get _outstanding => numOf(_current, ['outstanding']);
  double get _itemsPending =>
      numOf(_current, ['itemsPending', 'items_pending']);
  List<Map<String, dynamic>> get _quoteRows => _quotations.data ?? const [];

  int get _quotationDraft => _quoteRows
      .where((q) => str(q, ['status']).toLowerCase() == 'draft')
      .length;
  int get _quotationSent => _quoteRows
      .where((q) => str(q, ['status']).toLowerCase() == 'received')
      .length;
  int get _quotationAccepted => _quoteRows
      .where((q) => str(q, ['status']).toLowerCase() == 'delivered')
      .length;
  double get _quotationAcceptedValue => _quoteRows
      .where((q) => str(q, ['status']).toLowerCase() == 'delivered')
      .fold(0.0, (s, q) => s + numOf(q, ['total_amount']));

  static double _delta(double cur, double prev) {
    if (prev == 0) return cur > 0 ? 100 : 0;
    return (cur - prev) / (prev < 1 ? 1 : prev) * 100;
  }

  /// The thresholds the React page applies after the summary lands, kept
  /// identical so both clients raise the same four alerts.
  List<(String, AppTone, String)> get _alerts {
    final out = <(String, AppTone, String)>[];
    final rate = numOf(_current, ['collectionRate', 'collection_rate']);
    if (rate < 70 && _revenue > 0) {
      out.add((
        'collection',
        AppTone.danger,
        'Collection rate is ${rate.toStringAsFixed(1)}%. Prioritize follow-ups '
            'on ${intOf(_current, [
              'pendingBills',
              'pending_bills'
            ])} unpaid bills.',
      ));
    }
    if (_outstanding > 0 && _outstanding > _revenue * 0.4) {
      out.add((
        'outstanding',
        AppTone.warning,
        'Outstanding receivables are ${(_outstanding / (_revenue < 1 ? 1 : _revenue) * 100).toStringAsFixed(0)}% '
            'of revenue (${_outstanding.toStringAsFixed(0)} LKR).',
      ));
    }
    if (_itemsPending > 50) {
      out.add((
        'pending-items',
        AppTone.warning,
        '$_itemsPending items are still pending delivery across '
            '${intOf(_current, ['gatePasses', 'gate_passes'])} gate passes.',
      ));
    }
    if (_quotationAccepted > 0 && _quotationDraft + _quotationSent > 0) {
      final conv = _quotationAccepted /
          (_quotationAccepted + _quotationDraft + _quotationSent);
      if (conv < 0.4) {
        out.add((
          'conversion',
          AppTone.info,
          'Quotation conversion is ${(conv * 100).toStringAsFixed(0)}%. '
              '$_quotationDraft drafts are still open.',
        ));
      }
    }
    return out;
  }

  // ── Export ─────────────────────────────────────────────────────────────────

  Future<void> _export(String type, String path, String extension) async {
    setState(() => _exporting = true);
    final s = AppScope.read(context);
    try {
      final bytes = await s.api.getBytes(ServiceNames.bills, path);
      final file = File(
        '${Directory.systemTemp.path}/$type-${Fmt.today()}.$extension',
      );
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Export — $type',
      );
      if (!mounted) return;
      AppToast.success(context, 'Exported $type as ${extension.toUpperCase()}');
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _pickExport() async {
    final type = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final t in const [
              ('gatepasses', 'Gate Passes'),
              ('bills', 'Bills'),
              ('deliveries', 'Deliveries'),
            ])
              ListTile(
                leading: const Icon(Icons.table_rows_outlined),
                title: Text('${t.$2} · CSV'),
                onTap: () => Navigator.of(context).pop(t.$1),
              ),
            for (final t in const [
              ('gatepasses', 'Gate Passes'),
              ('bills', 'Bills'),
              ('deliveries', 'Deliveries'),
            ])
              ListTile(
                leading: const Icon(Icons.table_chart_outlined),
                title: Text('${t.$2} · Excel'),
                onTap: () => Navigator.of(context).pop('${t.$1}/xlsx'),
              ),
          ],
        ),
      ),
    );
    if (type == null || !mounted) return;
    if (type.endsWith('/xlsx')) {
      final base = type.substring(0, type.length - 4);
      await _export(base, '/export/$type', 'xlsx');
    } else {
      await _export(type, '/export/$type', 'csv');
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final loading = _summary.isLoading && !_summary.hasData;

    return Column(
      children: [
        AppPageHeader(
          title: 'Dashboard',
          subtitle:
              'Business overview — $CompanyInfo.name, Medagama · Reg. No. ${CompanyInfo.registrationNo}',
          busy: loading,
          actions: [
            AppExportButton(onExport: _pickExport, busy: _exporting),
            AppButton(
              label: 'New Quotation',
              icon: Icons.add_rounded,
              size: AppButtonSize.sm,
              onPressed: () =>
                  AppNavigatorPush.push(context, '/quotations/new'),
            ),
          ],
          tabs: AppTabs(
            index: _period,
            onChanged: _setPeriod,
            tabs: [
              for (var i = 0; i < _periods.length; i++)
                AppTabItem(_periodLabels[i]),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _reload,
            child: loading
                ? ListView(
                    children: const [
                      AppSyncStatusBar(
                        status: CacheStatus.syncing,
                        label: 'Dashboard',
                      ),
                      AppSkeletonList(count: 5, lines: 2),
                    ],
                  )
                : !_summary.hasData
                    ? ListView(
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.5,
                            child: _summary.phase == LoadPhase.failed
                                ? AppErrorState(
                                    message: _summary.error,
                                    onRetry: () => _summary.load(force: true),
                                  )
                                : const AppEmptyState(
                                    title: 'No data available',
                                    message:
                                        'Start by creating a gate pass or bill.',
                                  ),
                          ),
                        ],
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                        children: [
                          AppSyncStatusBar(
                            status: _summary.status,
                            label: 'Dashboard',
                            updatedAt: _summary.lastUpdated,
                            onTap: _reload,
                          ),
                          const SizedBox(height: 14),
                          if (_alerts.isNotEmpty) ...[
                            for (final a in _alerts) ...[
                              AppNotice(message: a.$3, tone: a.$2),
                              const SizedBox(height: 8),
                            ],
                          ],
                          _kpiGrid(),
                          const SizedBox(height: 14),
                          _balancesCard(),
                          const SizedBox(height: 14),
                          _todayDeliveriesCard(),
                          const SizedBox(height: 14),
                          _comparisonCard(),
                          const SizedBox(height: 14),
                          _revenueChartCard(),
                          const SizedBox(height: 14),
                          _paymentStatusCard(),
                          const SizedBox(height: 14),
                          _topClientsCard(),
                          const SizedBox(height: 14),
                          _pendingBalanceCard(),
                          const SizedBox(height: 14),
                          _itemAnalyticsCard(),
                          const SizedBox(height: 14),
                          _agingCard(),
                          const SizedBox(height: 14),
                          _funnelCard(),
                          const SizedBox(height: 14),
                          _yearlyTrendCard(),
                          const SizedBox(height: 14),
                          _activityCard(),
                        ],
                      ),
          ),
        ),
      ],
    );
  }

  // ── Sections ───────────────────────────────────────────────────────────────

  Widget _kpiGrid() {
    final c = context.c;
    final t = context.texts;
    final prev = _previous;
    final kpis = <(String, String, double, String, IconData)>[
      (
        'Revenue',
        Fmt.money(_revenue),
        _delta(_revenue, numOf(prev, ['revenue'])),
        '/bills',
        Icons.payments_outlined
      ),
      (
        'Collected',
        Fmt.money(_collected),
        _delta(_collected, numOf(prev, ['collected'])),
        '/bills',
        Icons.check_circle_outline
      ),
      (
        'Outstanding',
        Fmt.money(_outstanding),
        _delta(_outstanding, numOf(prev, ['outstanding'])),
        '/bills',
        Icons.hourglass_bottom_outlined
      ),
      (
        'Collection Rate',
        Fmt.percent(numOf(_current, ['collectionRate', 'collection_rate'])),
        _delta(numOf(_current, ['collectionRate', 'collection_rate']),
            numOf(prev, ['collectionRate', 'collection_rate'])),
        '/bills',
        Icons.percent_rounded
      ),
      (
        'Gate Passes',
        Fmt.count(intOf(_current, ['gatePasses', 'gate_passes'])),
        _delta(numOf(_current, ['gatePasses', 'gate_passes']),
            numOf(prev, ['gatePasses', 'gate_passes'])),
        '/gatepasses',
        Icons.assignment_outlined
      ),
      (
        'Active Clients',
        Fmt.count(intOf(_current, ['activeClients', 'active_clients'])),
        _delta(numOf(_current, ['activeClients', 'active_clients']),
            numOf(prev, ['activeClients', 'active_clients'])),
        '/customers',
        Icons.people_outline
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.75,
      children: [
        for (final k in kpis)
          AppStatCard(
            label: k.$1,
            value: k.$2,
            compact: true,
            icon: k.$5,
            onTap: () => AppNavigatorPush.push(context, k.$4),
            footer: Row(
              children: [
                Icon(
                  k.$3 >= 0
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  size: 12,
                  color: k.$3 >= 0 ? c.success : c.danger,
                ),
                const SizedBox(width: 2),
                Text(
                  '${k.$3.abs().toStringAsFixed(1)}% vs prev',
                  style: t.labelSmall
                      ?.copyWith(color: k.$3 >= 0 ? c.success : c.danger),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _balancesCard() {
    final c = context.c;
    final t = context.texts;
    final collectedPct = _revenue > 0 ? _collected / _revenue * 100 : 0.0;
    final outstandingPct = _revenue > 0 ? _outstanding / _revenue * 100 : 0.0;
    final clients = (_clientWise.data ?? const [])
        .where((r) => numOf(r, ['outstanding']) > 0)
        .toList()
      ..sort((a, b) =>
          numOf(b, ['outstanding']).compareTo(numOf(a, ['outstanding'])));
    final maxOutstanding = clients.isEmpty
        ? 1.0
        : clients
            .map((r) => numOf(r, ['outstanding']))
            .reduce((a, b) => a > b ? a : b);

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(Radii.md)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total outstanding',
                    style: t.labelMedium?.copyWith(color: c.fgMuted)),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'LKR ${_outstanding.toStringAsFixed(0)}',
                    style: t.displaySmall?.copyWith(color: c.fg),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    for (final m in [
                      (
                        'Collected',
                        'LKR ${Fmt.compact(_collected)}',
                        '${collectedPct.toStringAsFixed(0)}%'
                      ),
                      (
                        'Pending',
                        'LKR ${Fmt.compact(_outstanding)}',
                        '${outstandingPct.toStringAsFixed(0)}%'
                      ),
                      (
                        'Bills',
                        '${intOf(_current, ['billCount', 'bill_count'])}',
                        '${intOf(_current, ['paidBills', 'paid_bills'])} paid'
                      ),
                    ])
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.$1,
                                style:
                                    t.labelSmall?.copyWith(color: c.fgMuted)),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(m.$2,
                                  style: t.labelLarge?.copyWith(color: c.fg)),
                            ),
                            Text(m.$3,
                                style:
                                    t.labelSmall?.copyWith(color: c.fgFaint)),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.pill),
                  child: SizedBox(
                    height: 8,
                    child: Row(
                      children: [
                        Expanded(
                          flex: collectedPct.round().clamp(0, 100),
                          child: Container(color: c.brand),
                        ),
                        Expanded(
                          flex: outstandingPct.round().clamp(0, 100),
                          child: Container(color: c.line2),
                        ),
                        if (collectedPct.round() + outstandingPct.round() < 100)
                          Expanded(
                            flex: 100 -
                                collectedPct.round() -
                                outstandingPct.round(),
                            child: Container(color: c.surface3),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Collected ${collectedPct.toStringAsFixed(0)}%',
                        style: t.labelSmall?.copyWith(color: c.fgMuted)),
                    Text('Outstanding ${outstandingPct.toStringAsFixed(0)}%',
                        style: t.labelSmall?.copyWith(color: c.fgMuted)),
                  ],
                ),
                if (_outstanding > 0) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: AppButton(
                      label: 'Full details',
                      icon: Icons.visibility_outlined,
                      variant: AppButtonVariant.secondary,
                      size: AppButtonSize.xs,
                      onPressed: _showBalances,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (clients.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Text('Outstanding by client'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Column(
                children: [
                  for (final cl in clients.take(8)) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            str(cl, ['client_name'], '—'),
                            style: t.labelLarge?.copyWith(color: c.fg),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                            'LKR ${numOf(cl, [
                                  'outstanding'
                                ]).toStringAsFixed(0)}',
                            style: t.labelLarge?.copyWith(color: c.fg)),
                        if (numOf(cl, ['total_billed']) > 0) ...[
                          const SizedBox(width: 6),
                          Text(
                            '${(numOf(cl, ['outstanding']) / numOf(cl, [
                                  'total_billed'
                                ], 1) * 100).toStringAsFixed(0)}% of bill',
                            style: t.labelSmall?.copyWith(color: c.fgFaint),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.pill),
                      child: LinearProgressIndicator(
                        value: (numOf(cl, ['outstanding']) / maxOutstanding)
                            .clamp(0.0, 1.0),
                        minHeight: 6,
                        backgroundColor: c.surface3,
                        valueColor: AlwaysStoppedAnimation(c.brand),
                      ),
                    ),
                    for (final item in asRows(pick(cl, ['items'])))
                      Padding(
                        padding: const EdgeInsets.only(top: 4, left: 4),
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                str(item, ['item_name'], '—'),
                                style: t.labelSmall?.copyWith(color: c.fg2),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (str(item, ['specification']).isNotEmpty) ...[
                              const SizedBox(width: 6),
                              AppBadge(str(item, ['specification']),
                                  compact: true),
                            ],
                            const Spacer(),
                            Text(
                              '${Fmt.qty(numOf(item, [
                                    'delivered'
                                  ]))}/${Fmt.qty(numOf(item, ['received']))}',
                              style: t.labelSmall?.copyWith(color: c.fgMuted),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${Fmt.qty(numOf(item, ['pending']))} pending',
                              style: t.labelSmall?.copyWith(color: c.warning),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showBalances() {
    final rows = _clientWise.data ?? const [];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
          children: [
            Text('Client balances', style: context.texts.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Outstanding LKR ${_outstanding.toStringAsFixed(0)} · '
              'Collected LKR ${_collected.toStringAsFixed(0)}',
              style:
                  context.texts.bodySmall?.copyWith(color: context.c.fgMuted),
            ),
            const SizedBox(height: 14),
            for (final r in rows) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      str(r, ['client_name'], '—'),
                      style: context.texts.labelLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text('Billed ${Fmt.money(numOf(r, ['total_billed']))}',
                      style: context.texts.labelSmall
                          ?.copyWith(color: context.c.fgMuted)),
                  const SizedBox(width: 10),
                  Text('Paid ${Fmt.money(numOf(r, ['paid_amount']))}',
                      style: context.texts.labelSmall
                          ?.copyWith(color: context.c.success)),
                  const SizedBox(width: 10),
                  Text('Due ${Fmt.money(numOf(r, ['outstanding']))}',
                      style: context.texts.labelSmall
                          ?.copyWith(color: context.c.warning)),
                ],
              ),
              const SizedBox(height: 6),
              const Divider(height: 1),
            ],
          ],
        ),
      ),
    );
  }

  Widget _todayDeliveriesCard() {
    final c = context.c;
    final t = context.texts;
    final clients = _todayDeliveries.data ?? const [];
    final total =
        clients.fold<double>(0, (s, r) => s + numOf(r, ['total_qty']));

    return _section(
      title: "Today's Deliveries",
      icon: Icons.local_shipping_outlined,
      trailing: clients.isEmpty
          ? null
          : Text('$total pcs sent',
              style: t.labelSmall?.copyWith(color: c.fgMuted)),
      child: clients.isEmpty
          ? const AppEmptyState(
              title: 'No deliveries recorded today.',
              icon: Icons.local_shipping_outlined,
              compact: true,
            )
          : Column(
              children: [
                for (final client in clients) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: c.surface2,
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            str(client, ['client_name'], '—'),
                            style: t.labelLarge?.copyWith(color: c.fg),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (boolOf(client, ['has_note_delivery']))
                          const Padding(
                            padding: EdgeInsets.only(right: 6),
                            child: AppBadge('Marked by note',
                                tone: AppTone.warning, compact: true),
                          ),
                        Text('Sent ',
                            style: t.labelSmall?.copyWith(color: c.fgMuted)),
                        Text(Fmt.qty(numOf(client, ['total_qty'])),
                            style: t.labelLarge?.copyWith(color: c.fg)),
                      ],
                    ),
                  ),
                  for (final n in asRows(pick(client, ['note_deliveries'])))
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: c.warningSoft,
                        borderRadius: BorderRadius.circular(Radii.sm),
                        border: Border.all(color: c.warningBorder),
                      ),
                      child: Text(
                        '#${str(n, ['gate_pass_number'])} — '
                        '${str(n, ['note'], 'Marked delivered (note)')}',
                        style: t.labelSmall?.copyWith(color: c.warning),
                      ),
                    ),
                  for (final row in _mergeDeliveryItems(client)) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    row.item,
                                    style: t.bodySmall?.copyWith(color: c.fg),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (row.spec.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  AppBadge(row.spec, compact: true),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('${Fmt.qty(row.sent)} sent',
                              style: t.labelSmall?.copyWith(color: c.fgMuted)),
                          const SizedBox(width: 10),
                          if (row.pending > 0)
                            Text('${Fmt.qty(row.pending)} pending',
                                style:
                                    t.labelSmall?.copyWith(color: c.warning)),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                ],
              ],
            ),
    );
  }

  static ({String item, String spec, double sent, double pending}) _mergeRow(
      Map<String, dynamic> src,
      {required bool pending}) {
    return (
      item: str(src, ['item_name']),
      spec: str(src, ['specification']),
      sent: pending ? 0 : numOf(src, ['quantity']),
      pending: pending ? numOf(src, ['pending']) : 0,
    );
  }

  /// Today's dispatch and the remaining balance share a row per item, so the
  /// operator can see "sent today" and "still owed" on one line.
  List<({String item, String spec, double sent, double pending})>
      _mergeDeliveryItems(Map<String, dynamic> client) {
    final merged =
        <String, ({String item, String spec, double sent, double pending})>{};
    for (final d in asRows(pick(client, ['delivered_items']))) {
      final r = _mergeRow(d, pending: false);
      final key = '${r.item}||${r.spec}';
      final existing = merged[key];
      merged[key] = (
        item: r.item,
        spec: r.spec,
        sent: (existing?.sent ?? 0) + r.sent,
        pending: existing?.pending ?? 0,
      );
    }
    for (final p in asRows(pick(client, ['pending_items']))) {
      final r = _mergeRow(p, pending: true);
      final key = '${r.item}||${r.spec}';
      final existing = merged[key];
      merged[key] = (
        item: r.item,
        spec: r.spec,
        sent: existing?.sent ?? 0,
        pending: r.pending,
      );
    }
    return merged.values.toList();
  }

  Widget _comparisonCard() {
    final c = context.c;
    final t = context.texts;
    final prev = _previous;
    final rows = <(String, double, double, bool, bool)>[
      ('Revenue', _revenue, numOf(prev, ['revenue']), false, true),
      ('Collected', _collected, numOf(prev, ['collected']), false, true),
      ('Outstanding', _outstanding, numOf(prev, ['outstanding']), true, true),
      (
        'Avg Bill',
        numOf(_current, ['avgBill', 'avg_bill']),
        numOf(prev, ['avgBill', 'avg_bill']),
        false,
        true
      ),
      (
        'Bills',
        numOf(_current, ['billCount', 'bill_count']),
        numOf(prev, ['billCount', 'bill_count']),
        false,
        false
      ),
      (
        'Clients',
        numOf(_current, ['activeClients', 'active_clients']),
        numOf(prev, ['activeClients', 'active_clients']),
        false,
        false
      ),
    ];

    return _section(
      title: 'Period Comparison',
      icon: Icons.timer_outlined,
      child: Wrap(
        children: [
          for (final r in rows)
            Container(
              width: (MediaQuery.of(context).size.width - 32) / 2,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.$1, style: t.labelSmall?.copyWith(color: c.fgMuted)),
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      r.$5 ? Fmt.money(r.$2) : Fmt.count(r.$2.round()),
                      style: t.titleSmall?.copyWith(color: c.fg),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        _delta(r.$2, r.$3) >= 0
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 12,
                        color: (r.$4
                                ? _delta(r.$2, r.$3) < 0
                                : _delta(r.$2, r.$3) > 0)
                            ? c.success
                            : c.danger,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${_delta(r.$2, r.$3).abs().toStringAsFixed(0)}% vs prev',
                        style: t.labelSmall?.copyWith(
                          color: (r.$4
                                  ? _delta(r.$2, r.$3) < 0
                                  : _delta(r.$2, r.$3) > 0)
                              ? c.success
                              : c.danger,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _revenueChartCard() {
    final series = asRows(pick(_current, ['revenueSeries', 'revenue_series']));
    return _section(
      title: 'Revenue vs Collection',
      icon: Icons.show_chart_rounded,
      child: series.isEmpty
          ? const _ChartEmpty('No data for this period')
          : SizedBox(height: 220, child: _lineChart(series, bills: false)),
    );
  }

  Widget _paymentStatusCard() {
    final c = context.c;
    final t = context.texts;
    final slices = asRows(pick(_current, ['paymentStatus', 'payment_status']))
        .where((s) => numOf(s, ['value']) > 0)
        .toList();
    final total = slices.fold<double>(0, (s, r) => s + numOf(r, ['value']));

    return _section(
      title: 'Payment Status',
      icon: Icons.pie_chart_outline_rounded,
      child: slices.isEmpty
          ? const _ChartEmpty('No bills yet')
          : Column(
              children: [
                for (final s in slices) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(str(s, ['name']),
                            style: t.labelLarge?.copyWith(color: c.fg)),
                      ),
                      Text('LKR ${Fmt.compact(numOf(s, ['value']))}',
                          style: t.labelLarge?.copyWith(color: c.fg)),
                      const SizedBox(width: 6),
                      Text(
                        '${(numOf(s, [
                                  'value'
                                ]) / (total == 0 ? 1 : total) * 100).toStringAsFixed(0)}%',
                        style: t.labelSmall?.copyWith(color: c.fgMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.pill),
                    child: LinearProgressIndicator(
                      value: numOf(s, ['value']) / (total == 0 ? 1 : total),
                      minHeight: 6,
                      backgroundColor: c.surface3,
                      valueColor: AlwaysStoppedAnimation(
                        _sliceColor(str(s, ['color']), c),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }

  /// The server sends a CSS colour with each slice; anything unparseable falls
  /// back to the info tone rather than a hard-coded hue.
  static Color _sliceColor(String raw, AppColors c) {
    final value = raw.replaceAll('var(--', '').replaceAll(')', '').trim();
    switch (value) {
      case 'success-text':
        return c.success;
      case 'warning-text':
        return c.warning;
      case 'danger-text':
        return c.danger;
      case 'brand':
        return c.brand;
      case 'info-text':
      default:
        return c.info;
    }
  }

  Widget _lineChart(List<Map<String, dynamic>> series, {required bool bills}) {
    final c = context.c;
    final t = context.texts;
    final spotsRevenue = <FlSpot>[];
    final spotsCollected = <FlSpot>[];
    for (var i = 0; i < series.length; i++) {
      spotsRevenue.add(FlSpot(i.toDouble(), numOf(series[i], ['revenue'])));
      spotsCollected.add(FlSpot(i.toDouble(), numOf(series[i], ['collected'])));
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: c.line, strokeWidth: 1, dashArray: [3, 3]),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 46,
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  Fmt.compact(value),
                  style: t.labelSmall?.copyWith(color: c.fgMuted),
                  textAlign: TextAlign.right,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: (series.length / 5).ceilToDouble().clamp(1, 9999),
              getTitlesWidget: (value, meta) {
                final i = value.round();
                if (i < 0 || i >= series.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    str(series[i], ['label']),
                    style: t.labelSmall?.copyWith(color: c.fgMuted),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => c.fg,
            getTooltipItems: (spots) => spots.map((s) {
              return LineTooltipItem(
                '${Fmt.money(s.y)}\n${bills ? str(series[s.spotIndex], [
                        'label'
                      ]) : ''}',
                TextStyle(color: c.surface, fontSize: 11),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          _bar(spotsRevenue, c.brand, c.brand.withValues(alpha: 0.18)),
          _bar(spotsCollected, c.success, c.success.withValues(alpha: 0.18)),
        ],
      ),
    );
  }

  static LineChartBarData _bar(List<FlSpot> spots, Color color, Color fill) =>
      LineChartBarData(
        spots: spots,
        isCurved: true,
        curveSmoothness: 0.24,
        color: color,
        barWidth: 2,
        isStrokeCapRound: true,
        dotData: FlDotData(show: false),
        belowBarData: BarAreaData(show: true, color: fill),
      );

  Widget _topClientsCard() {
    final c = context.c;
    final t = context.texts;
    final rows =
        asRows(pick(_current, ['topClients', 'top_clients'])).take(5).toList();
    final maxRevenue = rows.isEmpty
        ? 1.0
        : rows
            .map((r) => numOf(r, ['revenue']))
            .reduce((a, b) => a > b ? a : b);

    return _section(
      title: 'Top Clients',
      icon: Icons.people_outline,
      child: rows.isEmpty
          ? const _ChartEmpty('No client revenue yet')
          : Column(
              children: [
                for (final r in rows) ...[
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          str(r, ['client_name'], '—'),
                          style: t.labelLarge?.copyWith(color: c.fg),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(Radii.pill),
                          child: LinearProgressIndicator(
                            value: numOf(r, ['revenue']) / maxRevenue,
                            minHeight: 6,
                            backgroundColor: c.surface3,
                            valueColor: AlwaysStoppedAnimation(c.brand),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: Text(
                          Fmt.money(numOf(r, ['revenue'])),
                          style: t.labelLarge?.copyWith(color: c.fg),
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        numOf(r, ['outstanding']) > 0
                            ? Fmt.money(numOf(r, ['outstanding']))
                            : '—',
                        style: t.labelSmall?.copyWith(
                          color: numOf(r, ['outstanding']) > 0
                              ? c.warning
                              : c.fgFaint,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }

  Widget _pendingBalanceCard() {
    final c = context.c;
    final t = context.texts;
    final pending =
        asRows(pick(_current, ['pendingGatePasses', 'pending_gate_passes']));
    final byClient = <String, (double, List<(String, String, double)>)>{};
    for (final gp in pending) {
      final client = str(gp, ['client_name'], '—');
      final entry =
          byClient.putIfAbsent(client, () => (0, <(String, String, double)>[]));
      final items = <(String, String, double)>[];
      var total = entry.$1;
      for (final i in asRows(pick(gp, ['items']))) {
        final pendingQty = numOf(i, ['pending']);
        items.add(
            (str(i, ['item_name']), str(i, ['specification']), pendingQty));
        total += pendingQty;
      }
      byClient[client] = (total, items);
    }
    final clients = byClient.entries.toList()
      ..sort((a, b) => b.value.$1.compareTo(a.value.$1));

    return _section(
      title: 'Pending Balance',
      icon: Icons.inventory_2_outlined,
      trailing: _itemsPending > 0
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(Fmt.qty(_itemsPending),
                    style: t.titleSmall?.copyWith(color: c.warning)),
                const SizedBox(width: 8),
                AppButton(
                  label: 'Deliver',
                  icon: Icons.local_shipping_outlined,
                  size: AppButtonSize.xs,
                  onPressed: () =>
                      AppNavigatorPush.push(context, '/deliveries/new'),
                ),
              ],
            )
          : null,
      child: clients.isEmpty
          ? const _ChartEmpty('All deliveries are up to date')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in clients) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(entry.key,
                            style: t.labelLarge?.copyWith(color: c.fg),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      Text(Fmt.qty(entry.value.$1),
                          style: t.labelLarge?.copyWith(color: c.warning)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  for (final i in entry.value.$2)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, left: 4),
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(i.$1,
                                style: t.labelSmall?.copyWith(color: c.fg2),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                          if (i.$2.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            AppBadge(i.$2, compact: true),
                          ],
                          const Spacer(),
                          Text('${Fmt.qty(i.$3)} pending',
                              style: t.labelSmall?.copyWith(color: c.warning)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }

  Widget _itemAnalyticsCard() {
    final c = context.c;
    final t = context.texts;
    final rows = (_itemWise.data ?? const []).take(8).toList();
    final maxReceived = rows.isEmpty
        ? 1.0
        : rows
            .map((r) => numOf(r, ['total_received']))
            .reduce((a, b) => a > b ? a : b);

    return _section(
      title: 'Item Analytics',
      icon: Icons.layers_outlined,
      child: rows.isEmpty
          ? const _ChartEmpty('No item data yet')
          : Column(
              children: [
                for (final r in rows) ...[
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(str(r, ['item_name'], '—'),
                            style: t.labelLarge?.copyWith(color: c.fg),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      Expanded(
                        flex: 2,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(Radii.pill),
                          child: LinearProgressIndicator(
                            value: numOf(r, ['total_received']) / maxReceived,
                            minHeight: 6,
                            backgroundColor: c.surface3,
                            valueColor: AlwaysStoppedAnimation(c.info),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(Fmt.qty(numOf(r, ['total_received'])),
                          style: t.labelLarge?.copyWith(color: c.fg)),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 52,
                        child: Text(
                          numOf(r, ['pending']) > 0
                              ? '${Fmt.qty(numOf(r, ['pending']))} pend'
                              : '—',
                          style: t.labelSmall?.copyWith(color: c.warning),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }

  Widget _agingCard() {
    final c = context.c;
    final t = context.texts;
    final aging = _aging.data ?? const {};
    final buckets = <(String, double, Color)>[
      ('Current', numOf(aging, ['current']), c.success),
      ('1-30 days', numOf(aging, ['30_day', '30-day']), c.warning),
      ('31-60 days', numOf(aging, ['60_day', '60-day']), c.warning),
      ('61-90 days', numOf(aging, ['90_day', '90-day']), c.danger),
      ('90+ days', numOf(aging, ['over_90', 'over-90']), c.danger),
    ];
    final total = buckets.fold<double>(0, (s, b) => s + b.$2);

    return _section(
      title: 'Outstanding Aging',
      icon: Icons.bar_chart_outlined,
      trailing: total == 0
          ? null
          : Text('LKR ${Fmt.compact(total)}',
              style: t.labelLarge?.copyWith(color: c.fg)),
      child: total == 0
          ? const _ChartEmpty('Nothing outstanding')
          : Column(
              children: [
                for (final b in buckets) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(b.$1,
                            style: t.labelLarge?.copyWith(color: c.fg)),
                      ),
                      Text('LKR ${Fmt.compact(b.$2)}',
                          style: t.labelLarge?.copyWith(color: c.fg)),
                      const SizedBox(width: 6),
                      Text('${(b.$2 / total * 100).toStringAsFixed(0)}%',
                          style: t.labelSmall?.copyWith(color: c.fgMuted)),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.pill),
                    child: LinearProgressIndicator(
                      value: b.$2 / total,
                      minHeight: 6,
                      backgroundColor: c.surface3,
                      valueColor: AlwaysStoppedAnimation(b.$3),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }

  Widget _funnelCard() {
    final c = context.c;
    final t = context.texts;
    final total = _quotationDraft + _quotationSent + _quotationAccepted;
    final stages = <(String, int, Color)>[
      ('Draft', _quotationDraft, c.fgMuted),
      ('Sent', _quotationSent, c.info),
      ('Accepted', _quotationAccepted, c.success),
    ];

    return _section(
      title: 'Quotation Funnel',
      icon: Icons.track_changes_outlined,
      child: total == 0
          ? const _ChartEmpty('No quotations yet')
          : Column(
              children: [
                for (final s in stages) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(s.$1,
                            style: t.labelLarge?.copyWith(color: c.fg)),
                      ),
                      Text('${s.$2}',
                          style: t.labelLarge?.copyWith(color: c.fg)),
                      const SizedBox(width: 6),
                      Text('${(s.$2 / total * 100).toStringAsFixed(0)}%',
                          style: t.labelSmall?.copyWith(color: c.fgMuted)),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.pill),
                    child: LinearProgressIndicator(
                      value: (s.$2 / total * 100).clamp(0.02, 1.0),
                      minHeight: 6,
                      backgroundColor: c.surface3,
                      valueColor: AlwaysStoppedAnimation(s.$3),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                if (_quotationAcceptedValue > 0)
                  Row(
                    children: [
                      Expanded(
                        child: Text('Accepted value',
                            style: t.labelSmall?.copyWith(color: c.fgMuted)),
                      ),
                      Text(Fmt.money(_quotationAcceptedValue),
                          style: t.labelLarge?.copyWith(color: c.success)),
                    ],
                  ),
              ],
            ),
    );
  }

  Widget _yearlyTrendCard() {
    final trend = _yearly.data ?? const [];
    return _section(
      title: '12-Month Trend',
      icon: Icons.trending_up_rounded,
      child: trend.isEmpty
          ? const _ChartEmpty('No data yet')
          : SizedBox(height: 240, child: _lineChart(trend, bills: true)),
    );
  }

  Widget _activityCard() {
    final c = context.c;
    final t = context.texts;
    final rows = _activity.data ?? const [];
    if (rows.isEmpty) return const SizedBox.shrink();

    return _section(
      title: 'Recent Activity',
      icon: Icons.history_rounded,
      trailing: TextButton(
        onPressed: () => AppNavigatorPush.push(context, '/reports'),
        child: const Text('View all'),
      ),
      child: Column(
        children: [
          for (final r in rows) ...[
            Row(
              children: [
                AppBadge(
                  str(r, ['action'], '—').toUpperCase().replaceAll('_', ' '),
                  tone: _actionTone(str(r, ['action'])),
                  compact: true,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: str(r, ['user_id'], 'system'),
                        style: t.bodySmall?.copyWith(color: c.fg),
                      ),
                      TextSpan(
                        text: ' ${str(r, [
                              'action'
                            ]).toLowerCase().replaceAll('_', ' ')} ',
                        style: t.bodySmall?.copyWith(color: c.fgMuted),
                      ),
                      TextSpan(
                        text: str(r, ['entity']),
                        style: t.bodySmall?.copyWith(color: c.fg),
                      ),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(Fmt.relative(pick(r, ['timestamp'])),
                    style: t.labelSmall?.copyWith(color: c.fgFaint)),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  static AppTone _actionTone(String action) {
    final a = action.toUpperCase();
    if (a.contains('DELETE') || a.contains('REMOVE') || a.contains('CANCEL')) {
      return AppTone.danger;
    }
    if (a.contains('CREATE') || a.contains('ADD') || a.contains('PAYMENT')) {
      return AppTone.success;
    }
    return AppTone.neutral;
  }

  Widget _section({
    required String title,
    required IconData icon,
    required Widget child,
    Widget? trailing,
  }) {
    final c = context.c;
    final t = context.texts;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: c.fgFaint),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: t.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// Chart placeholder, matching the React pages' bare centred message.
class _ChartEmpty extends StatelessWidget {
  const _ChartEmpty(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Container(
        height: 120,
        alignment: Alignment.center,
        width: double.infinity,
        child: Text(
          message,
          style: context.texts.bodySmall?.copyWith(color: context.c.fgMuted),
          textAlign: TextAlign.center,
        ),
      );
}
