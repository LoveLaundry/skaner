import 'package:flutter/material.dart';

import '../../config/api_config.dart';
import '../../core/utils/formatting.dart';
import '../../data/resource_controller.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/data.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/inputs.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/kit/shell_parts.dart';
import '../../ui/theme.dart';
import 'shop_bill_detail_page.dart';
import 'shop_bill_form_page.dart';
import 'shop_bill_model.dart';

/// Port of `features/shop-bills/pages/shop-bills-list-page.tsx`.
///
/// Search, an operational-status filter, a payment-status filter and a client
/// filter all narrow the same server-side list; the summary strip is computed
/// from the rows that survived the filters so it can never disagree with what
/// is on screen.
class ShopBillsPage extends StatefulWidget {
  const ShopBillsPage({super.key});

  @override
  State<ShopBillsPage> createState() => _ShopBillsPageState();
}

class _ShopBillsPageState extends State<ShopBillsPage> {
  final _searchCtrl = TextEditingController();
  late final ResourceController<List<Map<String, dynamic>>> _controller;

  String _search = '';
  String _status = '';
  String _paymentStatus = '';
  String? _client;
  final int _limit = 100;

  @override
  void initState() {
    super.initState();
    _controller = ResourceController(
      key: 'bills',
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

  Future<List<Map<String, dynamic>>> _fetch() async {
    final payload = await AppScope.read(context).api.get(
      ServiceNames.bills,
      ShopBillApi.list(),
      query: {
        if (_search.isNotEmpty) 'search': _search,
        if (_status.isNotEmpty) 'status': _status,
        if (_paymentStatus.isNotEmpty) 'payment_status': _paymentStatus,
        if (_client != null && _client!.isNotEmpty) 'client_name': _client,
        'sort_by': 'created_at',
        'sort_order': 'desc',
        'limit': _limit,
      },
    );
    return asRows(payload);
  }

  Future<void> _reload() => _controller.load(force: true);

  List<Map<String, dynamic>> get _rows => _controller.data ?? const [];

  bool get _hasFilters =>
      _search.isNotEmpty ||
      _status.isNotEmpty ||
      _paymentStatus.isNotEmpty ||
      (_client != null && _client!.isNotEmpty);

  /// The client filter offers the clients already on screen, so the operator
  /// never has to guess a spelling the server does not know.
  List<String> get _clients {
    final names = <String>{for (final row in _rows) billClient(row)};
    names.removeWhere((e) => e.trim().isEmpty);
    return names.toList()..sort();
  }

  double get _totalValue =>
      _rows.fold<double>(0, (sum, row) => sum + billGrandTotalOf(row));

  double get _unpaid => _rows.fold<double>(
        0,
        (sum, row) =>
            sum + (billOutstanding(row) < 0 ? 0 : billOutstanding(row)),
      );

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final c = context.c;
    final t = context.texts;
    if (!services.auth.hasPermission(shopBillsPermission)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Shop bills')),
        body: const AppErrorState(
          title: 'Not permitted',
          message: 'You do not have access to shop bills.',
          icon: Icons.lock_outline,
        ),
      );
    }

    final rows = _rows;
    final loading = _controller.isLoading && rows.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shop bills'),
        actions: [
          AppButton.icon(
            icon: Icons.refresh,
            tooltip: 'Refresh',
            loading: _controller.isLoading,
            onPressed: _reload,
          ),
        ],
      ),
      body: Column(
        children: [
          AppSyncStatusBar(
            status: _controller.status,
            updatedAt: _controller.lastUpdated,
            label: 'Shop bills',
          ),
          AppOfflineSyncBar(engine: services.sync),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: AppTextInput(
              controller: _searchCtrl,
              hint: 'Search by bill number or client…',
              icon: Icons.search,
              textInputAction: TextInputAction.search,
              onChanged: (v) => setState(() {
                _search = v.trim();
              }),
              suffix: _search.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _search = '');
                        _reload();
                      },
                    ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final option in BillStatusBadge.billStatusFilters)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: AppFilterChip(
                      label: option.label,
                      selected: _paymentStatus == option.value,
                      onTap: () {
                        setState(() => _paymentStatus = option.value);
                        _reload();
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                AppFilterChip(
                  label: 'All statuses',
                  selected: _status.isEmpty,
                  onTap: () {
                    setState(() => _status = '');
                    _reload();
                  },
                ),
                for (final status in shopBillStatusFlow)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: AppFilterChip(
                      label: Fmt.humanise(status),
                      selected: _status == status,
                      onTap: () {
                        setState(() => _status = status);
                        _reload();
                      },
                    ),
                  ),
                AppFilterChip(
                  label: 'Cancelled',
                  selected: _status == 'CANCELLED',
                  onTap: () {
                    setState(() =>
                        _status = _status == 'CANCELLED' ? '' : 'CANCELLED');
                    _reload();
                  },
                ),
              ],
            ),
          ),
          if (_clients.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: AppSearchableSelect<String>(
                value: _client,
                label: 'Client',
                hint: 'All clients',
                clearable: true,
                options: [
                  for (final name in _clients)
                    AppSelectOption<String>(value: name, label: name),
                ],
                onChanged: (v) {
                  setState(() => _client = v);
                  _reload();
                },
              ),
            ),
          if (_hasFilters)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
              child: Row(
                children: [
                  Text(
                    '${Fmt.count(rows.length)} shown',
                    style: t.labelSmall?.copyWith(color: c.fgMuted),
                  ),
                  const Spacer(),
                  AppButton(
                    label: 'Reset',
                    variant: AppButtonVariant.ghost,
                    size: AppButtonSize.xs,
                    icon: Icons.filter_alt_off_outlined,
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() {
                        _search = '';
                        _status = '';
                        _paymentStatus = '';
                        _client = null;
                      });
                      _reload();
                    },
                  ),
                ],
              ),
            ),
          _SummaryStrip(
            count: rows.length,
            totalValue: _totalValue,
            unpaid: _unpaid,
          ),
          Expanded(
            child: RefreshIndicator(
              color: c.brand,
              onRefresh: _reload,
              child: _controller.phase == LoadPhase.failed && rows.isEmpty
                  ? AppErrorState(message: _controller.error, onRetry: _reload)
                  : loading
                      ? const AppSkeletonList()
                      : AppDataTable<Map<String, dynamic>>(
                          rows: rows,
                          emptyTitle: _hasFilters
                              ? 'No shop bills match'
                              : 'No shop bills yet',
                          emptyMessage: _hasFilters
                              ? 'Try adjusting the search or filters.'
                              : 'Create your first shop bill to get started.',
                          emptyIcon: Icons.receipt_long_outlined,
                          columns: [
                            AppDataColumn<Map<String, dynamic>>(
                              label: 'Bill',
                              value: billNumber,
                            ),
                            AppDataColumn<Map<String, dynamic>>(
                              label: 'Client',
                              value: billClient,
                              minWidth: 130,
                            ),
                            AppDataColumn<Map<String, dynamic>>(
                              label: 'Date',
                              value: (r) => Fmt.date(
                                pick(r, const [
                                  'created_at',
                                  'bill_date',
                                  'date',
                                ]),
                              ),
                            ),
                            AppDataColumn<Map<String, dynamic>>(
                              label: 'Total',
                              value: (r) => Fmt.money(billGrandTotalOf(r)),
                            ),
                            AppDataColumn<Map<String, dynamic>>(
                              label: 'Unpaid',
                              value: (r) {
                                final due = billOutstanding(r);
                                return due > 0 ? Fmt.money(due) : '—';
                              },
                            ),
                          ],
                          rowLeading: (context, row) => Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              BillStatusBadge(
                                status: billPaymentStatus(row),
                              ),
                              const SizedBox(height: 5),
                              AppBadge(
                                Fmt.humanise(billStatus(row), fallback: '—'),
                                tone: shopBillStatusTone(billStatus(row)),
                                compact: true,
                              ),
                            ],
                          ),
                          onRowTap: (row) => _openDetail(
                            '${pick(row, const ['id']) ?? ''}',
                          ),
                        ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        backgroundColor: c.brand,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New bill'),
      ),
    );
  }

  Future<void> _openDetail(String id) async {
    if (id.isEmpty) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ShopBillDetailPage(billId: id)),
    );
    if (mounted) _reload();
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ShopBillFormPage()),
    );
    if (!mounted) return;
    if (created == true) _reload();
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({
    required this.count,
    required this.totalValue,
    required this.unpaid,
  });

  final int count;
  final double totalValue;
  final double unpaid;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
        child: Row(
          children: [
            Expanded(
              child: AppStatCard(
                compact: true,
                label: 'Bills',
                value: Fmt.count(count),
                icon: Icons.receipt_long_outlined,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AppStatCard(
                compact: true,
                label: 'Value',
                value: Fmt.money(totalValue),
                icon: Icons.payments_outlined,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AppStatCard(
                compact: true,
                label: 'Unpaid',
                value: Fmt.money(unpaid),
                icon: Icons.account_balance_wallet_outlined,
                footer: unpaid > 0
                    ? Text(
                        'Outstanding',
                        style: context.texts.labelSmall
                            ?.copyWith(color: context.c.danger),
                      )
                    : null,
              ),
            ),
          ],
        ),
      );
}
