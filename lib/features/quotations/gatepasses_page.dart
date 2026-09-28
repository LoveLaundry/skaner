import 'package:flutter/material.dart';

import '../../core/utils/formatting.dart';
import '../../data/resource_controller.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/inputs.dart';
import '../../ui/kit/shell_parts.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/theme.dart';
import 'bill_model.dart';
import 'gatepass_detail_page.dart';
import 'gatepass_form_page.dart';
import 'gatepass_slip_page.dart';
import 'quotation_model.dart';
import 'shared_widgets.dart';

/// Port of `pages/gatepasses-page.tsx`.
///
/// The web page buckets passes by how much of the receipt is still open work
/// rather than by their raw status, so the sections here use the same rule:
/// a pass with a count mismatch is not "received", it is "partially received",
/// and that is what the operator has to chase.
class GatepassesPage extends StatefulWidget {
  const GatepassesPage({super.key});

  @override
  State<GatepassesPage> createState() => _GatepassesPageState();
}

class _GatepassesPageState extends State<GatepassesPage> {
  final _searchCtrl = TextEditingController();

  late final ResourceController<List<GatePass>> _passes;

  String _search = '';
  DateTime? _from;
  DateTime? _to;
  bool _moreFilters = false;

  @override
  void initState() {
    super.initState();
    _passes = ResourceController(
      key: 'gatepasses',
      cache: AppScope.read(context).cache,
      fetcher: _fetch,
    );
    _passes.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _passes.removeListener(_onChanged);
    _passes.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<List<GatePass>> _fetch() async {
    final payload = await AppScope.read(context).api.get(
      operationsService,
      GatePassApi.list,
      query: {
        if (_search.isNotEmpty) 'search': _search,
        if (_from != null) 'date_from': Fmt.isoDate(_from),
        if (_from == null && _to != null) 'date_to': Fmt.isoDate(_to),
        'limit': 200,
      },
    );
    return gatePassesFrom(payload);
  }

  Future<void> _reload() => _passes.load(force: true);

  bool get _hasFilters => _search.isNotEmpty || _from != null || _to != null;

  void _resetFilters() {
    _searchCtrl.clear();
    setState(() {
      _search = '';
      _from = null;
      _to = null;
    });
    _reload();
  }

  List<GatePass> get _rows {
    final all = _passes.data ?? const <GatePass>[];
    final needle = _search.toLowerCase();
    return all.where((gp) {
      if (needle.isNotEmpty) {
        final haystack = [
          gp.gatePassNumber,
          gp.clientName,
          gp.receivedBy,
          ...gp.items.map((i) => i.itemName),
        ].join(' ').toLowerCase();
        if (!haystack.contains(needle)) return false;
      }
      final day = (gp.receivingDate ?? '').split('T').first;
      if (_from != null &&
          day.isNotEmpty &&
          day.compareTo(_dayKey(_from!)) < 0) {
        return false;
      }
      if (_to != null && day.isNotEmpty && day.compareTo(_dayKey(_to!)) > 0) {
        return false;
      }
      return true;
    }).toList();
  }

  static String _dayKey(DateTime d) => Fmt.isoDate(d);

  List<OpsMetric> get _metrics {
    final all = _passes.data ?? const <GatePass>[];
    final today = Fmt.isoDate(Fmt.lktNow());
    int bySection(String key) => all.where((gp) => gp.sectionKey == key).length;
    return [
      OpsMetric(
        id: 'total',
        label: 'Gate passes',
        value: '${all.length}',
        icon: Icons.assignment_outlined,
        tone: AppTone.info,
      ),
      OpsMetric(
        id: 'today',
        label: "Today's receipts",
        value:
            '${all.where((g) => (g.receivingDate ?? '').startsWith(today)).length}',
        icon: Icons.calendar_month_outlined,
        tone: AppTone.info,
      ),
      OpsMetric(
        id: 'pending',
        label: 'Pending',
        value: '${bySection('pending')}',
        icon: Icons.inventory_2_outlined,
        tone: AppTone.warning,
      ),
      OpsMetric(
        id: 'received',
        label: 'Received',
        value: '${bySection('received')}',
        icon: Icons.move_to_inbox_outlined,
        tone: AppTone.neutral,
      ),
      OpsMetric(
        id: 'partial',
        label: 'Partially received',
        value: '${bySection('partial')}',
        icon: Icons.warning_amber_rounded,
        tone: AppTone.danger,
      ),
      OpsMetric(
        id: 'completed',
        label: 'Completed',
        value: '${bySection('completed')}',
        icon: Icons.check_circle_outline,
        tone: AppTone.success,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    if (!canView(services, gatePassesPermission)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gate passes')),
        body: opsNotPermitted('gate passes'),
      );
    }
    final canWrite = services.auth.hasPermission(gatePassesPermission);
    final all = _passes.data ?? const <GatePass>[];
    final rows = _rows;
    final loading = _passes.isLoading && all.isEmpty;

    Map<String, List<GatePass>> grouped() {
      final by = <String, List<GatePass>>{
        for (final k in const [
          'pending',
          'received',
          'partial',
          'completed',
          'historical',
        ])
          k: <GatePass>[],
      };
      for (final gp in rows) {
        by[gp.sectionKey]!.add(gp);
      }
      return by;
    }

    final by = grouped();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gate passes'),
        actions: [
          AppButton.icon(
            icon: Icons.refresh,
            tooltip: 'Refresh',
            loading: _passes.isLoading,
            onPressed: _reload,
          ),
        ],
      ),
      body: Column(
        children: [
          AppSyncStatusBar(
            status: _passes.status,
            updatedAt: _passes.lastUpdated,
            label: 'Gate passes',
          ),
          AppOfflineSyncBar(engine: services.sync),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: AppTextInput(
                    controller: _searchCtrl,
                    hint: 'Search by gate pass no., item, person…',
                    icon: Icons.search,
                    textInputAction: TextInputAction.search,
                    onChanged: (v) => setState(() => _search = v.trim()),
                    suffix: _search.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            tooltip: 'Clear search',
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _search = '');
                            },
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                AppButton.icon(
                  icon: Icons.tune_outlined,
                  tooltip: 'More filters',
                  onPressed: () => setState(() => _moreFilters = !_moreFilters),
                ),
              ],
            ),
          ),
          if (_moreFilters)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: AppDateField(
                      value: _from,
                      hint: 'Received from',
                      onChanged: (d) => setState(() => _from = d),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppDateField(
                      value: _to,
                      hint: 'Received to',
                      onChanged: (d) => setState(() => _to = d),
                    ),
                  ),
                ],
              ),
            ),
          if (_hasFilters)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _resetFilters,
                icon: const Icon(Icons.filter_alt_off_outlined, size: 15),
                label: const Text('Clear'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: context.c.fgMuted,
                ),
              ),
            ),
          CompactMetrics(items: _metrics),
          Expanded(
            child: RefreshIndicator(
              color: context.c.brand,
              onRefresh: _reload,
              child: _passes.phase == LoadPhase.failed && all.isEmpty
                  ? AppErrorState(message: _passes.error, onRetry: _reload)
                  : loading
                      ? const AppSkeletonList()
                      : all.isEmpty
                          ? _empty(canWrite, filtered: false)
                          : rows.isEmpty
                              ? _empty(canWrite, filtered: true)
                              : OpsSectionList<GatePass>(
                                  sections: [
                                    OpsSection<GatePass>(
                                      key: 'pending',
                                      label: 'Pending',
                                      icon: Icons.schedule,
                                      tone: AppTone.warning,
                                      items: by['pending']!,
                                    ),
                                    OpsSection<GatePass>(
                                      key: 'received',
                                      label: 'Received',
                                      icon: Icons.move_to_inbox_outlined,
                                      tone: AppTone.info,
                                      items: by['received']!,
                                    ),
                                    OpsSection<GatePass>(
                                      key: 'partial',
                                      label: 'Partially received',
                                      icon: Icons.warning_amber_rounded,
                                      tone: AppTone.danger,
                                      items: by['partial']!,
                                    ),
                                    OpsSection<GatePass>(
                                      key: 'completed',
                                      label: 'Completed',
                                      icon: Icons.check_circle_outline,
                                      tone: AppTone.success,
                                      items: by['completed']!,
                                    ),
                                    OpsSection<GatePass>(
                                      key: 'historical',
                                      label: 'Historical',
                                      icon: Icons.history,
                                      tone: AppTone.neutral,
                                      items: by['historical']!,
                                    ),
                                  ],
                                  itemBuilder: (context, gp) => _GatePassCard(
                                    gatePass: gp,
                                    onOpen: () => _openDetail(gp.id),
                                    onPrint: () => _printSlip(gp.id),
                                  ),
                                ),
            ),
          ),
        ],
      ),
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              onPressed: _openCreate,
              backgroundColor: context.c.brand,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('New gate pass'),
            )
          : null,
    );
  }

  Widget _empty(bool canWrite, {required bool filtered}) => ListView(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.4,
            child: AppEmptyState(
              title: filtered
                  ? 'Nothing matches these filters'
                  : 'No gate passes found',
              message: filtered
                  ? 'Try a different search or date range.'
                  : 'Record a gate pass when laundry is received from a hotel.',
              icon: Icons.inbox_outlined,
              action: filtered
                  ? AppButton(
                      label: 'Clear filters',
                      variant: AppButtonVariant.secondary,
                      onPressed: _resetFilters,
                    )
                  : canWrite
                      ? AppButton(
                          label: 'New gate pass',
                          variant: AppButtonVariant.primary,
                          icon: Icons.add,
                          onPressed: _openCreate,
                        )
                      : null,
            ),
          ),
        ],
      );

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const GatepassFormPage()),
    );
    if (!mounted) return;
    if (created == true) _reload();
  }

  Future<void> _openDetail(String id) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => GatepassDetailPage(gatepassId: id)),
    );
    if (mounted) _reload();
  }

  Future<void> _printSlip(String id) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => GatepassSlipPage(gatepassId: id)),
    );
  }
}

class _GatePassCard extends StatelessWidget {
  const _GatePassCard({
    required this.gatePass,
    required this.onOpen,
    required this.onPrint,
  });

  final GatePass gatePass;
  final VoidCallback onOpen;
  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final showAllHotels = AppScope.of(context).hotels.showAllHotels;
    return AppCard(
      onTap: onOpen,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const OpsIcon(Icons.assignment_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      gatePass.gatePassNumber.isEmpty
                          ? 'Unnumbered'
                          : gatePass.gatePassNumber,
                      style: context.texts.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    if (showAllHotels)
                      HotelBadge(name: gatePass.clientName)
                    else
                      Text(
                        gatePass.clientName.isEmpty ? '—' : gatePass.clientName,
                        style:
                            context.texts.bodySmall?.copyWith(color: c.fgMuted),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      Fmt.date(gatePass.receivingDate),
                      style:
                          context.texts.bodySmall?.copyWith(color: c.fgMuted),
                    ),
                  ],
                ),
              ),
              GatePassStatusBadge(status: gatePass.status),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _stat(context, '${gatePass.items.length} types'),
              _stat(context, '${gatePass.totalReceived} pcs'),
              _stat(context,
                  'by ${gatePass.receivedBy.isEmpty ? '—' : gatePass.receivedBy}'),
              if (gatePass.mismatchCount > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 12, color: c.warning),
                    const SizedBox(width: 3),
                    Text(
                      '${gatePass.mismatchCount} '
                      'mismatch${gatePass.mismatchCount > 1 ? 'es' : ''}',
                      style:
                          context.texts.bodySmall?.copyWith(color: c.warning),
                    ),
                  ],
                ),
              if (gatePass.rewashedQty > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.undo, size: 12, color: c.success),
                    const SizedBox(width: 3),
                    Text(
                      '${gatePass.rewashedQty} pcs re-wash · not billed',
                      style: context.texts.bodySmall
                          ?.copyWith(color: context.c.success),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: EntityCardActions(
              onOpen: onOpen,
              onPrint: onPrint,
              canWrite: false,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String text) => Text(
        text,
        style: context.texts.bodySmall?.copyWith(color: context.c.fgMuted),
      );
}
