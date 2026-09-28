import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api/api_exception.dart';
import '../../core/utils/formatting.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/inputs.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/kit/shell_parts.dart';
import '../../ui/theme.dart';
import 'bill_detail_page.dart';
import 'bill_model.dart';
import 'quotation_model.dart';
import 'shared_widgets.dart';

/// Derived screen: the web app has no `billing-history-page.tsx`. This is
/// `pages/statement-page.tsx` for the operations side — the same per-client
/// chronology of bills, payments, deliveries and returns, the same
/// billed / collected / outstanding reconciliation, and the same client-side CSV
/// — kept under the name the app shell links to.
class BillingHistoryPage extends StatefulWidget {
  const BillingHistoryPage({super.key});

  @override
  State<BillingHistoryPage> createState() => _BillingHistoryPageState();
}

class _BillingHistoryPageState extends State<BillingHistoryPage> {
  final _searchCtrl = TextEditingController();

  String _client = '';
  List<BillRecord> _bills = const [];
  List<Delivery> _deliveries = const [];
  List<ReturnRecord> _returns = const [];
  Map<String, List<BillPayment>> _paymentsByBill = const {};

  bool _loading = false;
  bool _exporting = false;
  String? _error;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final client = _client;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = AppScope.read(context).api;
      final billsPayload = await api.get(
        operationsService,
        BillApi.list,
        query: {'client_name': client, 'limit': 200},
      );
      final bills = billsFrom(billsPayload);
      final deliveriesPayload = await api.get(
        operationsService,
        DeliveryApi.list,
        query: {'client_name': client},
      );
      final returnsPayload = await api.get(
        operationsService,
        ReturnApi.list,
        query: {'client_name': client, 'limit': 200},
      );
      // The React page fetches each bill's payments in parallel; a failure on
      // one bill must not blank the whole statement.
      final payments = <String, List<BillPayment>>{};
      await Future.wait(bills.map((b) async {
        try {
          final payload = await api.get(
            operationsService,
            BillApi.payments(b.id),
          );
          payments[b.id] = billPaymentsFrom(payload);
        } on ApiException {
          payments[b.id] = const [];
        }
      }));
      if (!mounted) return;
      setState(() {
        _bills = bills;
        _deliveries = deliveriesFrom(deliveriesPayload);
        _returns = returnsFrom(returnsPayload);
        _paymentsByBill = payments;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _search() {
    final client = _searchCtrl.text.trim();
    if (client.isEmpty) return;
    setState(() => _client = client);
    _load();
  }

  void _clear() {
    _searchCtrl.clear();
    setState(() {
      _client = '';
      _bills = const [];
      _deliveries = const [];
      _returns = const [];
      _paymentsByBill = const {};
      _error = null;
    });
  }

  List<_Movement> get _movements {
    final rows = <_Movement>[];
    for (final b in _bills) {
      rows.add(
        _Movement(
          at: b.createdAt,
          kind: 'BILL',
          client: b.clientName,
          detail:
              'Bill ${Fmt.truncate(b.id, 8).toUpperCase()} · ${b.paymentStatus}',
          quantity: b.totalQuantity,
          amount: b.grand,
        ),
      );
      for (final p in _paymentsByBill[b.id] ?? const <BillPayment>[]) {
        rows.add(
          _Movement(
            at: p.paidAt,
            kind: 'PAYMENT',
            client: b.clientName,
            detail: [
              p.method.isEmpty ? 'Payment' : p.method,
              if (p.reference.isNotEmpty) p.reference,
            ].join(' · '),
            amount: p.amount,
            money: true,
          ),
        );
      }
    }
    for (final d in _deliveries) {
      rows.add(
        _Movement(
          at: d.deliveryDate,
          kind: 'DELIVERY',
          client: d.clientName,
          detail: d.items.map((i) => '${i.itemName} ×${i.quantity}').join(', '),
          quantity: d.totalPieces.toDouble(),
        ),
      );
    }
    for (final r in _returns) {
      rows.add(
        _Movement(
          at: r.createdAt,
          kind: 'RETURN',
          client: r.clientName,
          detail: 'Return ${r.returnId}: '
              '${r.items.map((i) => '${i.itemName} ×${i.returnedQty}').join(', ')}',
          quantity: r.totalPieces.toDouble(),
        ),
      );
    }
    rows.sort((a, b) {
      final at = Fmt.parseDate(a.at) ?? DateTime(1970);
      final bt = Fmt.parseDate(b.at) ?? DateTime(1970);
      return bt.compareTo(at);
    });
    return rows;
  }

  List<BillRecord> get _activeBills =>
      _bills.where((b) => !b.isCancelled).toList();

  List<BillRecord> get _openBills {
    final open = _activeBills.where((b) => !b.isPaid).toList();
    open.sort((a, b) => b.owed.compareTo(a.owed));
    return open;
  }

  double get _billed => _activeBills.fold<double>(0, (s, b) => s + b.grand);

  double get _collected => _bills.fold<double>(
        0,
        (s, b) =>
            s +
            (_paymentsByBill[b.id] ?? const <BillPayment>[])
                .fold<double>(0, (t, p) => t + p.amount),
      );

  double get _outstanding => _activeBills.fold<double>(0, (s, b) => s + b.owed);

  int get _returnedPieces => _returns.fold<int>(0, (s, r) => s + r.totalPieces);

  Future<void> _export() async {
    final rows = _movements;
    if (rows.isEmpty) {
      AppToast.error(context, 'Nothing to export');
      return;
    }
    setState(() => _exporting = true);
    try {
      final buffer =
          StringBuffer('date,type,client,description,quantity,amount\n');
      for (final m in rows) {
        String esc(Object? v) =>
            '"${(v ?? '').toString().replaceAll('"', '""')}"';
        buffer.writeln(
          [
            esc(m.at == null ? '' : Fmt.date(m.at)),
            esc(m.kind),
            esc(m.client),
            esc(m.detail),
            esc(m.quantity == null ? '' : m.quantity!.toStringAsFixed(0)),
            esc(m.money ? m.amount.toStringAsFixed(2) : ''),
          ].join(','),
        );
      }
      final file = File(
        '${Directory.systemTemp.path}/'
        'billing-history-${_client.replaceAll(RegExp(r'[^\w]+'), '-')}.csv',
      );
      await file.writeAsString(buffer.toString());
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv')],
        subject: 'Billing history — $_client',
      );
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    if (!canView(services, billsPermission)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Billing history')),
        body: opsNotPermitted('billing history'),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Billing history'),
        actions: [
          if (_client.isNotEmpty)
            AppButton.icon(
              icon: Icons.ios_share,
              tooltip: 'Export CSV',
              loading: _exporting,
              onPressed: _export,
            ),
        ],
      ),
      body: Column(
        children: [
          AppOfflineSyncBar(engine: services.sync),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: AppTextInput(
                    controller: _searchCtrl,
                    hint: 'Enter client name…',
                    icon: Icons.search,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    suffix: _searchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            tooltip: 'Clear',
                            onPressed: _clear,
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                AppButton(
                  label: 'View',
                  icon: Icons.arrow_forward,
                  onPressed: _searchCtrl.text.trim().isEmpty ? null : _search,
                ),
              ],
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_client.isEmpty) {
      return const AppEmptyState(
        title: 'Pick a client',
        message:
            'Search by client name to see their bills, payments, deliveries and returns.',
        icon: Icons.account_balance_outlined,
      );
    }
    if (_loading) {
      return const AppSkeletonList(count: 6);
    }
    if (_error != null) {
      return AppErrorState(
        message: '$_error Check the client name and try again.',
        onRetry: _load,
      );
    }
    if (_bills.isEmpty && _deliveries.isEmpty && _returns.isEmpty) {
      return AppEmptyState(
        title: 'No activity for "$_client"',
        message: 'No bills, deliveries or returns were found for this client.',
        icon: Icons.account_balance_outlined,
      );
    }
    return RefreshIndicator(
      color: context.c.brand,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _metrics(),
          const SizedBox(height: 12),
          if (_openBills.isNotEmpty) ...[
            _openBillsCard(),
            const SizedBox(height: 12),
          ],
          _movementsCard(),
        ],
      ),
    );
  }

  Widget _metrics() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _metric('Total billed', Fmt.money(_billed),
                  '${_activeBills.length} bills', AppTone.neutral),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _metric('Collected', Fmt.money(_collected),
                  'across all payments', AppTone.success),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _metric(
                  'Outstanding',
                  Fmt.money(_outstanding),
                  'on open bills',
                  _outstanding > 0 ? AppTone.warning : AppTone.neutral),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _metric(
                  'Returns',
                  '$_returnedPieces',
                  '${_returns.length} return record${_returns.length == 1 ? '' : 's'}',
                  AppTone.warning),
            ),
          ],
        ),
      ],
    );
  }

  Widget _metric(String label, String value, String note, AppTone tone) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.texts.bodySmall?.copyWith(color: context.c.fgMuted),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.texts.titleMedium?.copyWith(
              color: switch (tone) {
                AppTone.success => context.c.success,
                AppTone.warning => context.c.warning,
                _ => context.c.fg,
              },
            ),
          ),
          Text(
            note,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.texts.bodySmall?.copyWith(color: context.c.fgFaint),
          ),
        ],
      ),
    );
  }

  Widget _openBillsCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Collect outstanding', style: context.texts.titleSmall),
          const SizedBox(height: 8),
          for (final b in _openBills) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bill ${Fmt.truncate(b.id, 8).toUpperCase()} · ${b.paymentStatus}',
                          style: context.texts.bodyMedium,
                        ),
                        Text(
                          'Billed ${Fmt.money(b.grand)} · Paid ${Fmt.money((_paymentsByBill[b.id] ?? const <BillPayment>[]).fold<double>(0, (t, p) => t + p.amount))}',
                          style: context.texts.bodySmall
                              ?.copyWith(color: context.c.fgFaint),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    Fmt.money(b.owed),
                    style: context.texts.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: b.owed > 0 ? context.c.warning : context.c.fg,
                    ),
                  ),
                  const SizedBox(width: 8),
                  AppButton(
                    label: 'Record payment',
                    size: AppButtonSize.xs,
                    variant: AppButtonVariant.outline,
                    icon: Icons.arrow_forward,
                    onPressed: () => _openBill(b.id),
                  ),
                ],
              ),
            ),
            if (b != _openBills.last) Divider(height: 1, color: context.c.line),
          ],
        ],
      ),
    );
  }

  Widget _movementsCard() {
    final rows = _movements;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Movements', style: context.texts.titleSmall),
              const Spacer(),
              Text(
                '${rows.length} entries',
                style:
                    context.texts.bodySmall?.copyWith(color: context.c.fgFaint),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: context.c.line),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(
                    switch (rows[i].kind) {
                      'BILL' => Icons.receipt_long_outlined,
                      'PAYMENT' => Icons.account_balance_outlined,
                      'DELIVERY' => Icons.local_shipping_outlined,
                      _ => Icons.assignment_return_outlined,
                    },
                    size: 16,
                    color: switch (rows[i].kind) {
                      'BILL' => context.c.warning,
                      'PAYMENT' => context.c.success,
                      'DELIVERY' => context.c.info,
                      _ => context.c.warning,
                    },
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${rows[i].client} — ${rows[i].kind.toLowerCase()}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.bodyMedium,
                        ),
                        Text(
                          rows[i].detail,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.bodySmall
                              ?.copyWith(color: context.c.fgMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (rows[i].money)
                    Text(
                      '+${Fmt.money(rows[i].amount)}',
                      style: context.texts.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: context.c.success,
                      ),
                    )
                  else if (rows[i].kind == 'BILL')
                    Text(
                      Fmt.money(rows[i].amount),
                      style: context.texts.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    )
                  else
                    Text(
                      '${rows[i].quantity?.toStringAsFixed(0) ?? '0'} pcs',
                      style: context.texts.bodySmall
                          ?.copyWith(color: context.c.fgMuted),
                    ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 66,
                    child: Text(
                      rows[i].at == null ? '—' : Fmt.date(rows[i].at),
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      style: context.texts.bodySmall
                          ?.copyWith(color: context.c.fgFaint),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openBill(String id) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => BillDetailPage(billId: id)),
    );
    if (mounted) _load();
  }
}

class _Movement {
  const _Movement({
    required this.kind,
    required this.client,
    required this.detail,
    this.at,
    this.quantity,
    this.amount = 0,
    this.money = false,
  });

  final String kind;
  final String client;
  final String detail;
  final String? at;
  final double? quantity;
  final double amount;
  final bool money;

  @override
  String toString() => '$kind $client $detail $at $quantity $amount';
}
