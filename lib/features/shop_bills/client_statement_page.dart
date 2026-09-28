import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../config/api_config.dart';
import '../../core/api/api_exception.dart';
import '../../core/utils/formatting.dart';
import '../../data/resource_controller.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/data.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/inputs.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/kit/shell_parts.dart';
import '../../ui/theme.dart';
import 'shop_bill_model.dart';

/// Per-client ledger across every shop bill.
///
/// Mirrors the React client statement: one client in, a chronological set of
/// movements out, with billed / collected / outstanding reconciled at the top.
/// The React page assembles this client-side from bills + payments; the
/// dedicated route already does the arithmetic, so this screen prefers the
/// server's own totals and only falls back to summing the rows when the payload
/// omits them.
class ClientStatementPage extends StatefulWidget {
  const ClientStatementPage({super.key});

  @override
  State<ClientStatementPage> createState() => _ClientStatementPageState();
}

class _ClientStatementPageState extends State<ClientStatementPage> {
  final _clientCtrl = TextEditingController();

  String _client = '';
  bool _loading = false;
  bool _exporting = false;
  String? _error;

  List<Map<String, dynamic>> _bills = const [];
  List<Map<String, dynamic>> _payments = const [];
  Map<String, dynamic> _summary = const {};
  Map<String, dynamic>? _loyalty;

  @override
  void initState() {
    super.initState();
    _clientCtrl.addListener(_onClientChanged);
  }

  @override
  void dispose() {
    _clientCtrl
      ..removeListener(_onClientChanged)
      ..dispose();
    super.dispose();
  }

  void _onClientChanged() {
    final next = _clientCtrl.text.trim();
    if (next == _client) return;
    setState(() {
      _client = next;
      // Clearing the box must not leave the previous client's money on screen.
      if (next.isEmpty) _reset();
    });
  }

  void _reset() {
    _bills = const [];
    _payments = const [];
    _summary = const {};
    _loyalty = null;
    _error = null;
  }

  Future<void> _load() async {
    final name = _clientCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a client name');
      return;
    }
    setState(() {
      _client = name;
      _loading = true;
      _error = null;
      _reset();
    });

    final services = AppScope.read(context);
    try {
      final payload = asMap(await services.api.get(
        ServiceNames.bills,
        ShopBillApi.clientStatement(name),
      ));
      final bills = _rowsFrom(payload, const ['bills', 'items', 'shop_bills']);
      final payments =
          _rowsFrom(payload, const ['payments', 'payment_history']);
      final summary = asMap(pick(payload, const ['summary', 'totals']));
      if (!mounted) return;
      setState(() {
        _bills = bills;
        _payments = payments;
        _summary = summary;
        _loading = false;
      });
      _loadLoyalty(name);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  /// Loyalty is a nicety on top of the ledger; a failure must never turn a
  /// loaded statement into an error.
  Future<void> _loadLoyalty(String name) async {
    try {
      final payload = await AppScope.read(context).api.get(
            ServiceNames.bills,
            ShopBillApi.clientLoyalty(name),
          );
      if (!mounted) return;
      final map = asMap(payload);
      setState(() => _loyalty = map.isEmpty ? null : map);
    } catch (_) {
      if (mounted) setState(() => _loyalty = null);
    }
  }

  static List<Map<String, dynamic>> _rowsFrom(
    Map<String, dynamic> payload,
    List<String> keys,
  ) {
    final raw = pick(payload, keys);
    if (raw is List) return asRows(raw);
    if (raw is Map) {
      return asRows(asMap(raw).values.firstWhere(
            (v) => v is List,
            orElse: () => const [],
          ));
    }
    return const [];
  }

  double get _billed => _serverTotal(
        const ['total_billed', 'billed', 'total_amount', 'grand_total'],
        () => _bills.fold<double>(0, (s, b) => s + billGrandTotalOf(b)),
      );

  double get _collected => _serverTotal(
        const ['total_collected', 'collected', 'paid', 'total_paid'],
        () {
          if (_payments.isNotEmpty) {
            return _payments.fold<double>(
              0,
              (s, p) => s + numOf(p, const ['amount', 'paid_amount', 'value']),
            );
          }
          return _bills.fold<double>(0, (s, b) => s + billPaid(b));
        },
      );

  double get _outstanding => _serverTotal(
        const ['outstanding', 'total_outstanding', 'due', 'balance'],
        () => _bills.fold<double>(0, (s, b) => s + billOutstanding(b)),
      );

  double get _returns =>
      _serverTotal(const ['returns', 'total_returns'], () => 0);

  double _serverTotal(List<String> keys, double Function() fallback) {
    final value = numOf(_summary, keys, -1);
    return value >= 0 ? value : fallback();
  }

  /// Bills and payments interleaved by date — the "movements" ledger.
  List<_Movement> get _movements {
    final rows = <_Movement>[
      for (final bill in _bills)
        _Movement(
          at: Fmt.parseDate(
              pick(bill, const ['created_at', 'bill_date', 'date'])),
          kind: 'BILL',
          description: 'Bill ${billNumber(bill)}',
          amount: billGrandTotalOf(bill),
        ),
      for (final payment in _payments)
        _Movement(
          at: Fmt.parseDate(
            pick(payment, const ['date', 'created_at', 'paid_at']),
          ),
          kind: 'PAYMENT',
          description: Fmt.humanise(
            str(payment, const ['method', 'payment_method', 'mode'], 'Payment'),
            fallback: 'Payment',
          ),
          amount: numOf(payment, const ['amount', 'paid_amount', 'value']),
        ),
    ]..sort((a, b) {
        final at = a.at ?? DateTime(1970);
        final bt = b.at ?? DateTime(1970);
        return bt.compareTo(at);
      });
    return rows;
  }

  /// Writes a real CSV to a temp file and hands it to the platform share sheet;
  /// the React page does the same thing on the client.
  Future<void> _export() async {
    if (_movements.isEmpty) {
      AppToast.error(context, 'Nothing to export');
      return;
    }
    setState(() => _exporting = true);
    try {
      final buffer = StringBuffer('date,type,client,description,amount\n');
      for (final m in _movements) {
        buffer.writeln(
          [
            m.at == null ? '' : Fmt.isoDate(m.at),
            m.kind,
            _client,
            '"${m.description.replaceAll('"', '""')}"',
            m.amount.toStringAsFixed(2),
          ].join(','),
        );
      }
      final file = File(
        '${Directory.systemTemp.path}/statement-${_client.replaceAll(RegExp(r'\s+'), '-')}.csv',
      );
      await file.writeAsString(buffer.toString());
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv')],
        subject: 'Statement — $_client',
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
    if (!services.auth.hasPermission(shopBillsPermission)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Client statement')),
        body: const AppErrorState(
          title: 'Not permitted',
          message: 'You do not have access to shop bills.',
          icon: Icons.lock_outline,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Client statement'),
        actions: [
          AppExportButton(onExport: _export, busy: _exporting),
        ],
      ),
      body: Column(
        children: [
          AppOfflineSyncBar(engine: services.sync),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: AppField(
                    label: 'Client name',
                    error: _client.isEmpty ? _error : null,
                    child: AppTextInput(
                      controller: _clientCtrl,
                      hint: 'Shop / hotel name',
                      icon: Icons.storefront_outlined,
                      textInputAction: TextInputAction.search,
                      textCapitalization: TextCapitalization.words,
                      onSubmitted: (_) => _load(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AppButton(
                  label: 'Load',
                  icon: Icons.search,
                  loading: _loading,
                  onPressed: _client.isEmpty ? null : _load,
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
    final c = context.c;
    if (_loading) return const AppSkeletonList();
    if (_error != null && _bills.isEmpty) {
      return AppErrorState(message: _error, onRetry: _load);
    }
    if (_client.isEmpty) {
      return const AppEmptyState(
        title: 'Pick a client',
        message: 'Enter a shop or hotel name to see every bill and payment.',
        icon: Icons.receipt_long_outlined,
      );
    }
    if (_bills.isEmpty && _payments.isEmpty) {
      return const AppEmptyState(
        title: 'No movements',
        message: 'This client has no shop bills on record.',
        icon: Icons.inbox_outlined,
      );
    }

    return RefreshIndicator(
      color: c.brand,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AppNotice(message: _error!, tone: AppTone.warning),
            ),
          Row(
            children: [
              Expanded(
                child: AppStatCard(
                  compact: true,
                  label: 'Total billed',
                  value: Fmt.money(_billed),
                  icon: Icons.request_quote_outlined,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppStatCard(
                  compact: true,
                  label: 'Collected',
                  value: Fmt.money(_collected),
                  icon: Icons.check_circle_outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: AppStatCard(
                  compact: true,
                  label: 'Outstanding',
                  value: Fmt.money(_outstanding),
                  icon: Icons.account_balance_wallet_outlined,
                  footer: _outstanding > 0
                      ? Text(
                          'Collect outstanding',
                          style: context.texts.labelSmall
                              ?.copyWith(color: c.danger),
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppStatCard(
                  compact: true,
                  label: 'Returns',
                  value: Fmt.money(_returns),
                  icon: Icons.assignment_return_outlined,
                ),
              ),
            ],
          ),
          if (_loyalty != null) ...[
            const SizedBox(height: 12),
            _LoyaltyStrip(loyalty: _loyalty!),
          ],
          const SizedBox(height: 14),
          AppCard(
            title: 'Movements',
            subtitle: '${_movements.length} entries',
            child: Column(
              children: [
                for (final m in _movements)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 74,
                          child: Text(
                            Fmt.dateShort(m.at),
                            style: context.texts.labelSmall
                                ?.copyWith(color: c.fgFaint),
                          ),
                        ),
                        SizedBox(
                          width: 62,
                          child: AppBadge(
                            m.kind,
                            tone: m.kind == 'PAYMENT'
                                ? AppTone.success
                                : AppTone.info,
                            compact: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(m.description,
                              style: context.texts.bodyMedium),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${m.kind == 'PAYMENT' ? '+' : ''}${Fmt.money(m.amount)}',
                          style: context.texts.titleSmall?.copyWith(
                            color: m.kind == 'PAYMENT' ? c.success : null,
                          ),
                        ),
                      ],
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

class _Movement {
  _Movement({
    required this.at,
    required this.kind,
    required this.description,
    required this.amount,
  });

  final DateTime? at;
  final String kind;
  final String description;
  final double amount;
}

class _LoyaltyStrip extends StatelessWidget {
  const _LoyaltyStrip({required this.loyalty});

  final Map<String, dynamic> loyalty;

  @override
  Widget build(BuildContext context) {
    final tier = str(loyalty, const ['tier', 'level', 'rank'], 'Member');
    final points =
        numOf(loyalty, const ['points', 'loyalty_points', 'balance']);
    final discount = numOf(loyalty, const ['discount', 'discount_percent']);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Icon(Icons.workspace_premium_outlined,
              size: 20, color: context.c.brand),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(Fmt.humanise(tier, fallback: 'Member'),
                    style: context.texts.titleSmall),
                Text(
                  [
                    if (points > 0) '${Fmt.count(points)} points',
                    if (discount > 0) '${Fmt.percent(discount)} discount',
                  ].join(' · '),
                  style: context.texts.labelSmall
                      ?.copyWith(color: context.c.fgMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
