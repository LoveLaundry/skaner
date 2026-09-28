import 'package:flutter/material.dart';

import '../../core/api/sync_engine.dart';
import '../../core/utils/formatting.dart';
import '../../data/resource_controller.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/inputs.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/kit/shell_parts.dart';
import '../../ui/theme.dart';
import 'bill_model.dart';
import 'delivery_detail_page.dart';
import 'delivery_form_page.dart';
import 'delivery_slips_page.dart';
import 'quotation_model.dart';
import 'shared_widgets.dart';

/// Port of `pages/deliveries-page.tsx`.
///
/// The section a delivery lands in is not its stored status. The web app
/// downgrades a delivery whose own status says DELIVERED when one of its origin
/// gate passes is still open, because a delivery spanning two passes is only as
/// complete as its least-complete pass.
class DeliveriesPage extends StatefulWidget {
  const DeliveriesPage({super.key});

  @override
  State<DeliveriesPage> createState() => _DeliveriesPageState();
}

class _DeliveriesPageState extends State<DeliveriesPage> {
  final _searchCtrl = TextEditingController();

  late final ResourceController<List<Delivery>> _deliveries;

  String _search = '';
  String _gatePassFilter = '';
  DateTime? _from;
  DateTime? _to;
  bool _moreFilters = false;

  @override
  void initState() {
    super.initState();
    _deliveries = ResourceController(
      key: 'deliveries',
      cache: AppScope.read(context).cache,
      fetcher: _fetch,
    );
    _deliveries.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _deliveries.removeListener(_onChanged);
    _deliveries.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<List<Delivery>> _fetch() async {
    final hotel = AppScope.read(context).hotels.queryParam;
    final payload = await AppScope.read(context).api.get(
      operationsService,
      DeliveryApi.list,
      query: {
        if (hotel != null) 'client_name': hotel,
        if (_from != null) 'date_from': Fmt.isoDate(_from),
        if (_to != null) 'date_to': Fmt.isoDate(_to),
        'limit': 200,
      },
    );
    return deliveriesFrom(payload);
  }

  Future<void> _reload() => _deliveries.load(force: true);

  bool get _hasFilters =>
      _search.isNotEmpty ||
      _gatePassFilter.isNotEmpty ||
      _from != null ||
      _to != null;

  void _resetFilters() {
    _searchCtrl.clear();
    setState(() {
      _search = '';
      _gatePassFilter = '';
      _from = null;
      _to = null;
    });
    _reload();
  }

  List<Delivery> get _rows {
    final all = _deliveries.data ?? const <Delivery>[];
    final needle = _search.toLowerCase();
    return all.where((d) {
      if (needle.isNotEmpty) {
        final haystack = [
          d.clientName,
          d.deliveredBy,
          d.receivedBy,
          ...d.items.map((i) => i.itemName),
        ].join(' ').toLowerCase();
        if (!haystack.contains(needle)) return false;
      }
      if (_gatePassFilter.isNotEmpty && !d.sources.contains(_gatePassFilter)) {
        return false;
      }
      return true;
    }).toList();
  }

  /// Only the passes a delivery in the list actually drew from, so the filter
  /// cannot offer a choice that yields nothing.
  List<String> get _gatePassOptions {
    final ids = <String>{};
    for (final d in _deliveries.data ?? const <Delivery>[]) {
      ids.addAll(d.sources);
    }
    return ids.toList()..sort();
  }

  List<OpsMetric> get _metrics {
    final all = _deliveries.data ?? const <Delivery>[];
    final byStatus = <String, int>{};
    for (final d in all) {
      final s = deriveDeliveryStatus(d);
      byStatus[s] = (byStatus[s] ?? 0) + 1;
    }
    return [
      OpsMetric(
        id: 'total',
        label: 'Total deliveries',
        value: '${all.length}',
        icon: Icons.local_shipping_outlined,
        tone: AppTone.success,
      ),
      OpsMetric(
        id: 'completed',
        label: 'Completed',
        value: '${byStatus['DELIVERED'] ?? 0}',
        icon: Icons.check_circle_outline,
        tone: AppTone.success,
      ),
      OpsMetric(
        id: 'partial',
        label: 'Partial',
        value: '${byStatus['PARTIALLY_DELIVERED'] ?? 0}',
        icon: Icons.inventory_2_outlined,
        tone: AppTone.warning,
      ),
      OpsMetric(
        id: 'processing',
        label: 'In progress',
        value: '${byStatus['PROCESSING'] ?? 0}',
        icon: Icons.schedule,
        tone: AppTone.warning,
      ),
      OpsMetric(
        id: 'ready',
        label: 'Ready',
        value: '${byStatus['READY_FOR_DELIVERY'] ?? 0}',
        icon: Icons.task_alt,
        tone: AppTone.info,
      ),
      OpsMetric(
        id: 'pending',
        label: 'Awaiting confirmation',
        value: '${byStatus['PENDING'] ?? 0}',
        icon: Icons.apartment_outlined,
        tone: AppTone.neutral,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    if (!canView(services, deliveriesPermission)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Deliveries')),
        body: opsNotPermitted('deliveries'),
      );
    }
    final canWrite = services.auth.hasPermission(deliveriesPermission);
    final all = _deliveries.data ?? const <Delivery>[];
    final rows = _rows;
    final loading = _deliveries.isLoading && all.isEmpty;

    final by = <String, List<Delivery>>{
      for (final k in const ['pending', 'partial', 'completed', 'history'])
        k: <Delivery>[],
    };
    for (final d in rows) {
      final status = deriveDeliveryStatus(d);
      if (status == 'DELIVERED') {
        by['completed']!.add(d);
      } else if (status == 'PARTIALLY_DELIVERED') {
        by['partial']!.add(d);
      } else if (status == 'CANCELLED') {
        by['history']!.add(d);
      } else {
        by['pending']!.add(d);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Deliveries'),
        actions: [
          AppButton.icon(
            icon: Icons.print_outlined,
            tooltip: 'Print slips',
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const DeliverySlipsPage()),
            ),
          ),
          AppButton.icon(
            icon: Icons.refresh,
            tooltip: 'Refresh',
            loading: _deliveries.isLoading,
            onPressed: _reload,
          ),
        ],
      ),
      body: Column(
        children: [
          AppSyncStatusBar(
            status: _deliveries.status,
            updatedAt: _deliveries.lastUpdated,
            label: 'Deliveries',
          ),
          AppOfflineSyncBar(engine: services.sync),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: AppTextInput(
                    controller: _searchCtrl,
                    hint: 'Search by client, item, person…',
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
          if (_moreFilters) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                children: [
                  AppSearchableSelect<String>(
                    value: _gatePassFilter.isEmpty ? null : _gatePassFilter,
                    label: 'Gate pass',
                    hint: 'Filter by source gate pass',
                    searchable: true,
                    clearable: true,
                    options: [
                      for (final id in _gatePassOptions)
                        AppSelectOption<String>(
                          value: id,
                          label: Fmt.truncate(id, 16),
                        ),
                    ],
                    onChanged: (v) => setState(() => _gatePassFilter = v ?? ''),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: AppDateField(
                          value: _from,
                          hint: 'From',
                          onChanged: (d) => setState(() => _from = d),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: AppDateField(
                          value: _to,
                          hint: 'To',
                          onChanged: (d) => setState(() => _to = d),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
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
              child: _deliveries.phase == LoadPhase.failed && all.isEmpty
                  ? AppErrorState(message: _deliveries.error, onRetry: _reload)
                  : loading
                      ? const AppSkeletonList()
                      : all.isEmpty
                          ? _empty(canWrite, filtered: false)
                          : rows.isEmpty
                              ? _empty(canWrite, filtered: true)
                              : OpsSectionList<Delivery>(
                                  sections: [
                                    OpsSection<Delivery>(
                                      key: 'pending',
                                      label: 'Pending',
                                      icon: Icons.schedule,
                                      tone: AppTone.warning,
                                      items: by['pending']!,
                                    ),
                                    OpsSection<Delivery>(
                                      key: 'partial',
                                      label: 'Partially delivered',
                                      icon: Icons.warning_amber_rounded,
                                      tone: AppTone.danger,
                                      items: by['partial']!,
                                    ),
                                    OpsSection<Delivery>(
                                      key: 'completed',
                                      label: 'Completed',
                                      icon: Icons.check_circle_outline,
                                      tone: AppTone.success,
                                      items: by['completed']!,
                                    ),
                                    OpsSection<Delivery>(
                                      key: 'history',
                                      label: 'Delivery history',
                                      icon: Icons.history,
                                      tone: AppTone.neutral,
                                      items: by['history']!,
                                    ),
                                  ],
                                  itemBuilder: (context, d) => _DeliveryCard(
                                    delivery: d,
                                    onOpen: () => _openDetail(d.id),
                                    onEdit: () => _openEdit(d.id),
                                    canWrite: canWrite,
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
              label: const Text('Record delivery'),
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
                  : 'No deliveries recorded',
              message: filtered
                  ? 'Try a different search or date range.'
                  : 'Record a delivery when clean linen leaves for a hotel.',
              icon: Icons.local_shipping_outlined,
              action: filtered
                  ? AppButton(
                      label: 'Clear filters',
                      variant: AppButtonVariant.secondary,
                      onPressed: _resetFilters,
                    )
                  : canWrite
                      ? AppButton(
                          label: 'Record delivery',
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
      MaterialPageRoute(builder: (_) => const DeliveryFormPage()),
    );
    if (!mounted) return;
    if (created == true) {
      QueryCacheInvalidator.instance.invalidate('gatepasses');
      _reload();
    }
  }

  Future<void> _openEdit(String id) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => DeliveryFormPage(deliveryId: id)),
    );
    if (!mounted) return;
    if (saved == true) {
      QueryCacheInvalidator.instance.invalidate('gatepasses');
      _reload();
    }
  }

  Future<void> _openDetail(String id) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => DeliveryDetailPage(deliveryId: id)),
    );
    if (mounted) _reload();
  }
}

class _DeliveryCard extends StatelessWidget {
  const _DeliveryCard({
    required this.delivery,
    required this.onOpen,
    required this.onEdit,
    required this.canWrite,
  });

  final Delivery delivery;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final bool canWrite;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final showAllHotels = AppScope.of(context).hotels.showAllHotels;
    final status = deriveDeliveryStatus(delivery);
    final sourceCount = delivery.sources.length;
    return AppCard(
      onTap: onOpen,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const OpsIcon(Icons.local_shipping_outlined,
                  tone: AppTone.success),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Fmt.date(delivery.deliveryDate),
                      style: context.texts.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    if (showAllHotels)
                      HotelBadge(name: delivery.clientName)
                    else
                      Text(
                        delivery.clientName.isEmpty ? '—' : delivery.clientName,
                        style:
                            context.texts.bodySmall?.copyWith(color: c.fgMuted),
                      ),
                  ],
                ),
              ),
              DeliveryStatusBadge(status: status),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              Text(
                '${delivery.lineCount} lines',
                style: context.texts.bodySmall?.copyWith(color: c.fgMuted),
              ),
              Text(
                '${delivery.totalPieces} pcs',
                style: context.texts.bodySmall?.copyWith(color: c.fgMuted),
              ),
              Text(
                'by ${delivery.deliveredBy.isEmpty ? '—' : delivery.deliveredBy}',
                style: context.texts.bodySmall?.copyWith(color: c.fgMuted),
              ),
              if (sourceCount > 1)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.call_split, size: 12, color: c.info),
                    const SizedBox(width: 3),
                    Text(
                      '$sourceCount gate passes',
                      style: context.texts.bodySmall?.copyWith(color: c.info),
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
              onEdit: onEdit,
              canWrite: canWrite,
            ),
          ),
        ],
      ),
    );
  }
}
