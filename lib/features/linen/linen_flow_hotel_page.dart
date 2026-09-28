import 'package:flutter/material.dart';

import '../../core/models/json.dart' as json;
import '../../core/models/operations.dart';
import '../../core/utils/formatting.dart';
import '../../data/resource_controller.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/data.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/kit/shell_parts.dart';
import '_linen_shared.dart';
import '../../ui/theme.dart';

/// Port of the drill-down half of `hotel-linen-flow-page.tsx`.
///
/// The hotel balance is a per-gate-pass breakdown, so the page lists every pass
/// in the window with its own received / delivered / outstanding triple and
/// opens the item-level shortfall underneath. The `/dashboard/linen-flow`
/// payload carries the whole tree, so the hotel is picked out of it by name
/// rather than refetched.
class LinenFlowHotelPage extends StatefulWidget {
  const LinenFlowHotelPage({super.key, required this.hotelName});

  final String hotelName;

  @override
  State<LinenFlowHotelPage> createState() => _LinenFlowHotelPageState();
}

class _LinenFlowHotelPageState extends State<LinenFlowHotelPage> {
  late final ResourceController<LinenFlow> _controller;

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
        .get(linenService, LinenApi.flow, query: {'period': 'all'});
    return LinenFlow.fromJson(json.asMap(payload));
  }

  Future<void> _reload() => _controller.load(force: true);

  /// The router hands the name over percent-encoded, and a hotel whose name
  /// contains a slash would otherwise be unmatchable.
  String get _name {
    try {
      return Uri.decodeComponent(widget.hotelName);
    } on FormatException {
      return widget.hotelName;
    }
  }

  LinenFlowHotel? get _hotel {
    final hotels = _controller.data?.hotels ?? const <LinenFlowHotel>[];
    if (hotels.isEmpty) return null;
    final target = _name.trim().toLowerCase();
    for (final h in hotels) {
      if (h.clientName.trim().toLowerCase() == target) return h;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final c = context.c;
    final hotel = _hotel;
    final loading = _controller.isLoading && !_controller.hasData;
    final global = _controller.data;

    return Scaffold(
      appBar: AppBar(title: Text(_name)),
      body: Column(
        children: [
          AppSyncStatusBar(
            status: _controller.status,
            updatedAt: _controller.lastUpdated,
            label: 'Linen flow',
          ),
          AppOfflineSyncBar(engine: services.sync),
          Expanded(
            child: RefreshIndicator(
              color: c.brand,
              onRefresh: _reload,
              child: _controller.phase == LoadPhase.failed &&
                      !_controller.hasData
                  ? AppErrorState(message: _controller.error, onRetry: _reload)
                  : loading
                      ? const AppSkeletonList()
                      : hotel == null
                          ? ListView(
                              children: [
                                SizedBox(
                                  height:
                                      MediaQuery.of(context).size.height * 0.4,
                                  child: AppEmptyState(
                                    title: 'No linen flow for this hotel',
                                    message: global == null
                                        ? null
                                        : 'Nothing was received or delivered for '
                                            '$_name in the selected period.',
                                    icon: Icons.business_outlined,
                                  ),
                                ),
                              ],
                            )
                          : _Body(hotel: hotel, total: global!.totals),
            ),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.hotel, required this.total});

  final LinenFlowHotel hotel;
  final LinenFlowTotals total;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    final pending = hotel.totals.outstandingDeliveryQty;
    final outstandingPasses = hotel.gatePasses
        .where((g) => g.totals.outstandingDeliveryQty > 0)
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        AppStatCard(
          label: 'Pcs received',
          value: Fmt.qty(hotel.totals.receivedQty),
          icon: Icons.inbox_outlined,
          caption: '${hotel.gatePasses.length} gate pass'
              '${hotel.gatePasses.length == 1 ? '' : 'es'}',
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: AppStatCard(
                label: 'Delivered',
                value: Fmt.qty(hotel.totals.deliveredQty),
                icon: Icons.outbox_outlined,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AppStatCard(
                label: 'Outstanding',
                value: Fmt.qty(pending < 0 ? 0 : pending),
                icon: Icons.pending_actions_outlined,
                trend: pending > 0 ? StatTrend.up : StatTrend.flat,
                trendLabel: outstandingPasses > 0
                    ? '$outstandingPasses pass'
                        '${outstandingPasses == 1 ? '' : 'es'}'
                    : 'all clear',
              ),
            ),
          ],
        ),
        if (hotel.unlinkedPieces > 0) ...[
          const SizedBox(height: 10),
          AppNotice(
            title: 'Unlinked deliveries',
            message:
                '${Fmt.qty(hotel.unlinkedPieces)} pieces were delivered in this window with no matching gate pass. '
                'They are counted in the delivered figure but cannot be balanced against a pass.',
            tone: AppTone.warning,
          ),
        ],
        if (hotel.unlinkedDeliveries.isNotEmpty) ...[
          const SizedBox(height: 8),
          AppCard(
            title: 'Unlinked deliveries',
            subtitle: 'Deliveries with no gate pass in this period',
            child: Column(
              children: [
                for (final d in hotel.unlinkedDeliveries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Icon(Icons.link_off, size: 15, color: c.fg3),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            Fmt.date(d.deliveryDate),
                            style: t.bodyMedium?.copyWith(color: c.fg2),
                          ),
                        ),
                        Text(
                          '${Fmt.qty(d.pieces)} pcs',
                          style: t.bodyMedium?.copyWith(color: c.fg),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            'GATE PASSES',
            style: t.labelSmall?.copyWith(
              color: c.fgMuted,
              fontSize: 10.5,
              letterSpacing: 0.6,
            ),
          ),
        ),
        if (hotel.gatePasses.isEmpty)
          AppEmptyState(
            title: 'No gate passes in this period',
            message:
                'Widen the period on the linen flow screen to see older passes.',
            icon: Icons.receipt_long_outlined,
            compact: true,
          )
        else
          for (final gp in hotel.gatePasses) ...[
            _GatePassCard(gatePass: gp),
            const SizedBox(height: 8),
          ],
        if (hotel.gatePasses.isEmpty && hotel.unlinkedDeliveries.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Across every hotel: ${Fmt.qty(total.receivedQty)} received, '
              '${Fmt.qty(total.deliveredQty)} delivered, '
              '${Fmt.qty(total.outstandingDeliveryQty < 0 ? 0 : total.outstandingDeliveryQty)} outstanding.',
              style: t.bodySmall?.copyWith(color: c.fgMuted),
            ),
          ),
      ],
    );
  }
}

class _GatePassCard extends StatelessWidget {
  const _GatePassCard({required this.gatePass});

  final LinenFlowGatePass gatePass;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    final totals = gatePass.totals;
    final pending = totals.outstandingDeliveryQty;
    final label = gatePass.gatePassNumber?.trim();
    final number = label == null || label.isEmpty
        ? 'Gate pass ${gatePass.gatePassId}'
        : label;

    return AppCard(
      onTap:
          gatePass.outstandingItems.isEmpty ? null : () => _showItems(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      number,
                      style: t.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (gatePass.receivingDate != null)
                          'Received ${Fmt.date(gatePass.receivingDate)}',
                        if (gatePass.derivedStatus != null ||
                            gatePass.status != null)
                          Fmt.humanise(
                              gatePass.derivedStatus ?? gatePass.status),
                      ].join(' · '),
                      style: t.bodySmall?.copyWith(color: c.fgMuted),
                    ),
                  ],
                ),
              ),
              if (gatePass.markedDelivered)
                const AppBadge('Delivered',
                    tone: AppTone.success, compact: true)
              else if (pending > 0)
                AppBadge(
                  '${Fmt.qty(pending)} due',
                  tone: AppTone.warning,
                  compact: true,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                  child: _Cell(
                      label: 'In',
                      value: Fmt.qty(totals.receivedQty),
                      color: c.success)),
              Expanded(
                  child: _Cell(
                      label: 'Out',
                      value: Fmt.qty(totals.deliveredQty),
                      color: c.info)),
              Expanded(
                child: _Cell(
                  label: 'Due',
                  value: Fmt.qty(pending < 0 ? 0 : pending),
                  color: pending > 0 ? c.warning : c.success,
                ),
              ),
            ],
          ),
          if (gatePass.outstandingItems.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.expand_more, size: 15, color: c.fgFaint),
                const SizedBox(width: 4),
                Text(
                  '${gatePass.outstandingItems.length} item'
                  '${gatePass.outstandingItems.length == 1 ? '' : 's'} short',
                  style: t.labelSmall?.copyWith(color: c.fgMuted),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showItems(BuildContext context) {
    AppDialog.show<void>(
      context,
      title: 'Outstanding items',
      icon: Icons.pending_actions_outlined,
      maxWidth: 560,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const _ItemHeader(),
          for (final item in gatePass.outstandingItems)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      item.displayName,
                      style: context.texts.bodyMedium
                          ?.copyWith(color: context.c.fg),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(Fmt.qty(item.receivedQty),
                        textAlign: TextAlign.right,
                        style: context.texts.bodySmall
                            ?.copyWith(color: context.c.fgMuted)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(Fmt.qty(item.deliveredQty),
                        textAlign: TextAlign.right,
                        style: context.texts.bodySmall
                            ?.copyWith(color: context.c.fgMuted)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      Fmt.qty(item.outstandingDeliveryQty),
                      textAlign: TextAlign.right,
                      style: context.texts.bodyMedium?.copyWith(
                        color: item.outstandingDeliveryQty > 0
                            ? context.c.warning
                            : context.c.fg3,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ItemHeader extends StatelessWidget {
  const _ItemHeader();

  @override
  Widget build(BuildContext context) {
    final t = context.texts;
    final style =
        t.labelSmall?.copyWith(color: context.c.fgFaint, fontSize: 10.5);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text('ITEM', style: style)),
          Expanded(
              flex: 2,
              child: Text('IN', style: style, textAlign: TextAlign.right)),
          Expanded(
              flex: 2,
              child: Text('OUT', style: style, textAlign: TextAlign.right)),
          Expanded(
              flex: 2,
              child: Text('DUE', style: style, textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.value, required this.color});

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
          Text(value, style: context.texts.titleSmall?.copyWith(color: color)),
        ],
      );
}
