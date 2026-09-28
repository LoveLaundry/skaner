import 'package:flutter/material.dart';

import '../../core/api/api_exception.dart';
import '../../core/utils/formatting.dart';
import '../../data/resource_controller.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/inputs.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/theme.dart';
import 'bill_model.dart';
import 'print_paper.dart';
import 'quotation_model.dart';
import 'shared_widgets.dart';

/// Derived screen: the web app prints a delivery slip from the delivery itself
/// (`DeliveryPrintSheet`), with no separate slips screen. On mobile the slip is
/// a route the driver opens, so this screen is the list to pick one from — the
/// same document, reached by list rather than by a card action.
///
/// Opened with no argument it offers the recent deliveries to choose from;
/// opened with one it goes straight to that slip.
class DeliverySlipsPage extends StatefulWidget {
  const DeliverySlipsPage({super.key, this.deliveryId});

  final String? deliveryId;

  @override
  State<DeliverySlipsPage> createState() => _DeliverySlipsPageState();
}

class _DeliverySlipsPageState extends State<DeliverySlipsPage> {
  late final ResourceController<List<Delivery>> _deliveries;
  final _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void initState() {
    super.initState();
    _deliveries = ResourceController(
      key: 'deliveries',
      cache: AppScope.read(context).cache,
      fetcher: _fetch,
    );
    _deliveries.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _deliveries.load(force: true);
      final id = widget.deliveryId;
      if (id != null && mounted) _open(id);
    });
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
      query: {if (hotel != null) 'client_name': hotel, 'limit': 100},
    );
    return deliveriesFrom(payload);
  }

  Future<void> _open(String id) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => _SlipSheet(deliveryId: id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    if (!canView(services, deliveriesPermission)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Delivery slips')),
        body: opsNotPermitted('deliveries'),
      );
    }
    final all = _deliveries.data ?? const <Delivery>[];
    final needle = _search.toLowerCase();
    final rows = all
        .where((d) =>
            needle.isEmpty ||
            '${d.clientName} ${d.deliveredBy} ${d.id}'
                .toLowerCase()
                .contains(needle))
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Delivery slips')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: AppTextInput(
              controller: _searchCtrl,
              hint: 'Search by client, person or id…',
              icon: Icons.search,
              onChanged: (v) => setState(() => _search = v.trim()),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: context.c.brand,
              onRefresh: () => _deliveries.load(force: true),
              child: _deliveries.phase == LoadPhase.failed && all.isEmpty
                  ? AppErrorState(
                      message: _deliveries.error,
                      onRetry: () => _deliveries.load(force: true),
                    )
                  : _deliveries.isLoading && all.isEmpty
                      ? const AppSkeletonList()
                      : rows.isEmpty
                          ? ListView(
                              children: [
                                SizedBox(
                                  height:
                                      MediaQuery.of(context).size.height * 0.4,
                                  child: AppEmptyState(
                                    title: all.isEmpty
                                        ? 'No deliveries to print'
                                        : 'Nothing matches that search',
                                    message: all.isEmpty
                                        ? 'A slip can be printed once a delivery is recorded.'
                                        : 'Try a different search.',
                                    icon: Icons.local_shipping_outlined,
                                  ),
                                ),
                              ],
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                              itemCount: rows.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final d = rows[i];
                                return AppCard(
                                  onTap: () => _open(d.id),
                                  padding:
                                      const EdgeInsets.fromLTRB(14, 12, 12, 10),
                                  child: Row(
                                    children: [
                                      const OpsIcon(
                                        Icons.local_shipping_outlined,
                                        tone: AppTone.success,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              d.clientName.isEmpty
                                                  ? '—'
                                                  : d.clientName,
                                              style: context.texts.bodyMedium
                                                  ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            Text(
                                              '${Fmt.date(d.deliveryDate)} · '
                                              '${Fmt.qty(d.totalPieces)} pcs',
                                              style: context.texts.bodySmall
                                                  ?.copyWith(
                                                color: context.c.fgMuted,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      AppButton.icon(
                                        icon: Icons.print_outlined,
                                        tooltip: 'Print slip',
                                        size: AppButtonSize.iconSm,
                                        onPressed: () => _open(d.id),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The slip itself, from `components/delivery-print-sheet.tsx`.
class _SlipSheet extends StatefulWidget {
  const _SlipSheet({required this.deliveryId});

  final String deliveryId;

  @override
  State<_SlipSheet> createState() => _SlipSheetState();
}

class _SlipSheetState extends State<_SlipSheet> with OpsPrintMixin {
  Delivery? _delivery;
  bool _loading = true;
  String? _error;

  @override
  String get paperName => 'delivery-${_delivery?.id ?? widget.deliveryId}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final payload = await AppScope.read(context)
          .api
          .get(operationsService, DeliveryApi.one(widget.deliveryId));
      if (!mounted) return;
      setState(() {
        _delivery =
            Delivery.fromJson(Map<String, dynamic>.from(payload as Map));
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    if (!canView(services, deliveriesPermission)) {
      return PaperPageScaffold(
        title: 'Delivery note',
        child: opsNotPermitted('deliveries'),
      );
    }
    final d = _delivery;
    return PaperPageScaffold(
      title: 'Delivery note',
      actions: d == null ? const [] : paperActions,
      child: _loading
          ? const AppLoader(label: 'Preparing print layout')
          : _error != null
              ? AppErrorState(message: _error, onRetry: _load)
              : d == null
                  ? const AppEmptyState(
                      title: 'Delivery not found',
                      message: 'It may have been removed.',
                      icon: Icons.local_shipping_outlined,
                    )
                  : Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(12, 16, 12, 32),
                        child: RepaintBoundary(
                          key: paperKey,
                          child: PaperSheet(child: _sheet(d)),
                        ),
                      ),
                    ),
    );
  }

  Widget _sheet(Delivery d) {
    final tail = d.id.length > 8
        ? d.id.substring(d.id.length - 8).toUpperCase()
        : d.id.toUpperCase();
    final sourceNumbers = d.sourcePasses
        .map((p) => p.gatePassNumber)
        .where((n) => n.isNotEmpty)
        .join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CompanyLetterhead(),
        const PaperRule(gap: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                'DELIVERY NOTE',
                style: Paper.head.copyWith(
                  fontSize: 16,
                  letterSpacing: 2,
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Ref: DLV-$tail',
                  style: Paper.body.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  sourceNumbers.isEmpty
                      ? 'Gate Pass: ${Fmt.truncate(d.gatePassId, 10)}'
                      : 'Gate Pass: $sourceNumbers',
                  style: Paper.small,
                ),
              ],
            ),
          ],
        ),
        const PaperRule(gap: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PaperField(label: 'Delivered To', value: d.clientName),
                  const SizedBox(height: 6),
                  PaperField(label: 'Delivered By', value: d.deliveredBy),
                  const SizedBox(height: 6),
                  PaperField(label: 'Received By', value: d.receivedBy),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  PaperField(
                    label: 'Delivery Date',
                    value: Fmt.date(d.deliveryDate),
                    alignEnd: true,
                  ),
                  const SizedBox(height: 6),
                  PaperField(
                    label: 'Item Types',
                    value: '${d.items.length}',
                    alignEnd: true,
                  ),
                ],
              ),
            ),
          ],
        ),
        const PaperRule(gap: 10),
        PaperTable(
          headers: const ['NO.', 'ITEM', 'SPECIFICATION', 'QUANTITY'],
          flexes: const [1, 6, 3, 2],
          aligns: const [
            CrossAxisAlignment.start,
            CrossAxisAlignment.start,
            CrossAxisAlignment.start,
            CrossAxisAlignment.end,
          ],
          emptyText: 'No items',
          rows: [
            for (var i = 0; i < d.items.length; i++)
              PaperRow([
                '${i + 1}',
                d.items[i].itemName,
                d.items[i].specification,
                '${d.items[i].quantity}',
              ]),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text('Total Item Types: ${d.items.length}', style: Paper.body),
            const Spacer(),
            Text('Total Pieces: ${d.totalPieces}', style: Paper.body),
          ],
        ),
        const PaperRule(gap: 6),
        const PaperSignatureRow(
          labels: [
            'Delivered By',
            'Received By Client',
            'Authorized Signature'
          ],
        ),
      ],
    );
  }
}
