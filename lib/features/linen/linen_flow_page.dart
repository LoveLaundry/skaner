import 'package:flutter/material.dart';

import '../../core/models/json.dart' as json;
import '../../core/models/operations.dart';
import '../../core/utils/formatting.dart';
import '../../data/resource_controller.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/inputs.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/kit/shell_parts.dart';
import '../quotations/shared_widgets.dart';
import '_linen_shared.dart';
import 'linen_flow_hotel_page.dart';
import '../../ui/theme.dart';
import '../../ui/kit/data.dart';

/// Port of `features/quotations/pages/hotel-linen-flow-page.tsx`.
///
/// The page is a per-hotel balance: how many pieces each hotel handed over, how
/// many went back, and what is still owed. Every quantity is computed by the
/// server, so nothing here is derived locally — the totals strip sums the
/// hotels that survived the search filter, which is what the operator is
/// looking at.
class LinenFlowPage extends StatefulWidget {
  const LinenFlowPage({super.key});

  @override
  State<LinenFlowPage> createState() => _LinenFlowPageState();
}

class _LinenFlowPageState extends State<LinenFlowPage> {
  static const List<(String, String)> _periods = [
    ('all', 'All time'),
    ('month', 'This month'),
    ('quarter', 'Last 3 months'),
    ('year', 'This year'),
  ];

  final _searchCtrl = TextEditingController();
  late final ResourceController<LinenFlow> _controller;

  String _search = '';
  String _period = 'all';

  @override
  void initState() {
    super.initState();
    _controller = ResourceController(
      key: 'linen-flow',
      cache: AppScope.read(context).cache,
      fetcher: _fetch,
    );
    _controller.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reload();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<LinenFlow> _fetch() async {
    final payload = await AppScope.read(context)
        .api
        .get(linenService, LinenApi.flow, query: {'period': _period});
    return LinenFlow.fromJson(json.asMap(payload));
  }

  Future<void> _reload() => _controller.load(force: true);

  LinenFlow get _flow =>
      _controller.data ??
      const LinenFlow(
        period: 'all',
        hotels: [],
        totals: LinenFlowTotals.empty,
      );

  List<LinenFlowHotel> get _hotels {
    final q = _search.trim().toLowerCase();
    final hotels = _flow.hotels;
    if (q.isEmpty) return hotels;
    return hotels.where((h) => h.clientName.toLowerCase().contains(q)).toList();
  }

  bool get _hasFilters => _search.trim().isNotEmpty || _period != 'all';

  List<OpsMetric> get _metrics {
    final hotels = _hotels;
    double received = 0;
    double pending = 0;
    var passes = 0;
    for (final h in hotels) {
      received += h.totals.receivedQty;
      pending += h.totals.outstandingDeliveryQty;
      passes += h.gatePasses.length;
    }
    return [
      OpsMetric(
        id: 'hotels',
        label: 'Hotels',
        value: '${hotels.length}',
        icon: Icons.business_outlined,
        tone: AppTone.info,
      ),
      OpsMetric(
        id: 'passes',
        label: 'Gate passes',
        value: '$passes',
        icon: Icons.receipt_long_outlined,
        tone: AppTone.brand,
      ),
      OpsMetric(
        id: 'received',
        label: 'Pcs received',
        value: Fmt.qty(received),
        icon: Icons.inbox_outlined,
        tone: AppTone.success,
      ),
      OpsMetric(
        id: 'pending',
        label: 'Pcs remaining',
        value: Fmt.qty(pending < 0 ? 0 : pending),
        icon: Icons.pending_actions_outlined,
        tone: pending > 0 ? AppTone.warning : AppTone.success,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final c = context.c;
    final hotels = _hotels;
    final loading = _controller.isLoading && !_controller.hasData;

    return Scaffold(
      body: Column(
        children: [
          AppPageHeader(
            title: 'Hotel linen flow',
            actions: [
              AppButton.icon(
                icon: Icons.refresh,
                tooltip: 'Refresh',
                loading: _controller.isLoading,
                onPressed: _reload,
              ),
            ],
          ),
          AppSyncStatusBar(
            status: _controller.status,
            updatedAt: _controller.lastUpdated,
            label: 'Linen flow',
          ),
          AppOfflineSyncBar(engine: services.sync),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: AppTextInput(
              controller: _searchCtrl,
              hint: 'Search hotel…',
              icon: Icons.search,
              onChanged: (v) => setState(() => _search = v),
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
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              children: [
                for (final (value, label) in _periods) ...[
                  AppFilterChip(
                    label: label,
                    selected: _period == value,
                    onTap: () {
                      if (_period == value) return;
                      setState(() => _period = value);
                      _reload();
                    },
                  ),
                  if (value != _periods.last.$1) const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          CompactMetrics(items: _metrics),
          Expanded(
            child: RefreshIndicator(
              color: c.brand,
              onRefresh: _reload,
              child: _controller.phase == LoadPhase.failed &&
                      !_controller.hasData
                  ? AppErrorState(
                      message: _controller.error,
                      onRetry: _reload,
                    )
                  : loading
                      ? const AppSkeletonList()
                      : hotels.isEmpty
                          ? ListView(
                              children: [
                                SizedBox(
                                  height:
                                      MediaQuery.of(context).size.height * 0.4,
                                  child: AppEmptyState(
                                    title: _hasFilters
                                        ? 'No hotels match'
                                        : 'No linen flow yet',
                                    message: _hasFilters
                                        ? 'Try a different hotel or period.'
                                        : 'Linen flow appears once gate passes are received.',
                                    icon: Icons.swap_horiz_outlined,
                                    action: _hasFilters
                                        ? AppButton(
                                            label: 'Clear filters',
                                            variant: AppButtonVariant.secondary,
                                            onPressed: () {
                                              _searchCtrl.clear();
                                              setState(() {
                                                _search = '';
                                                _period = 'all';
                                              });
                                              _reload();
                                            },
                                          )
                                        : null,
                                  ),
                                ),
                              ],
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                              itemCount: hotels.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) => _HotelCard(
                                hotel: hotels[i],
                                onTap: () => _openHotel(hotels[i]),
                              ),
                            ),
            ),
          ),
        ],
      ),
    );
  }

  void _openHotel(LinenFlowHotel hotel) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LinenFlowHotelPage(hotelName: hotel.clientName),
      ),
    );
  }
}

class _HotelCard extends StatelessWidget {
  const _HotelCard({required this.hotel, required this.onTap});

  final LinenFlowHotel hotel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    final pending = hotel.totals.outstandingDeliveryQty;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  hotel.clientName.isEmpty ? 'Unknown hotel' : hotel.clientName,
                  style: t.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (pending > 0)
                AppBadge(
                  '${Fmt.qty(pending)} due',
                  tone: AppTone.warning,
                  icon: Icons.pending_actions_outlined,
                  compact: true,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _Figure(
                  label: 'Received',
                  value: Fmt.qty(hotel.totals.receivedQty),
                  color: c.success,
                ),
              ),
              Expanded(
                child: _Figure(
                  label: 'Delivered',
                  value: Fmt.qty(hotel.totals.deliveredQty),
                  color: c.info,
                ),
              ),
              Expanded(
                child: _Figure(
                  label: 'Remaining',
                  value: Fmt.qty(pending < 0 ? 0 : pending),
                  color: pending > 0 ? c.warning : c.success,
                ),
              ),
            ],
          ),
          if (hotel.gatePasses.isNotEmpty || hotel.unlinkedPieces > 0) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (hotel.gatePasses.isNotEmpty)
                  AppBadge(
                    '${hotel.gatePasses.length} gate pass'
                    '${hotel.gatePasses.length == 1 ? '' : 'es'}',
                    tone: AppTone.neutral,
                    icon: Icons.receipt_long_outlined,
                    compact: true,
                  ),
                if (hotel.unlinkedPieces > 0)
                  AppBadge(
                    '${Fmt.qty(hotel.unlinkedPieces)} unlinked',
                    tone: AppTone.danger,
                    icon: Icons.link_off,
                    compact: true,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure(
      {required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: context.texts.labelSmall
                ?.copyWith(color: context.c.fgFaint, fontSize: 10),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: context.texts.titleSmall?.copyWith(color: color),
            ),
          ),
        ],
      );
}
