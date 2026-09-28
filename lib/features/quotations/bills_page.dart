import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/sync_engine.dart';
import '../../core/utils/formatting.dart';
import '../../data/resource_controller.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/data.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/inputs.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/kit/shell_parts.dart';
import '../../ui/theme.dart';
import 'bill_detail_page.dart';
import 'bill_form_page.dart';
import 'bill_model.dart';
import 'quotation_model.dart';
import 'shared_widgets.dart';

/// Port of `features/quotations/pages/bills-list-page.tsx`.
///
/// The list is the operator's money view, so it is split by what still has to
/// happen: bills with an outstanding balance, gate passes that have gone out
/// but were never billed, bills that are settled, and everything else.
class BillsPage extends StatefulWidget {
  const BillsPage({super.key});

  @override
  State<BillsPage> createState() => _BillsPageState();
}

class _BillsPageState extends State<BillsPage> {
  final _searchCtrl = TextEditingController();

  late final ResourceController<List<BillRecord>> _bills;
  late final ResourceController<List<UnbilledGatePass>> _unbilled;

  String _search = '';
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    final cache = AppScope.read(context).cache;
    _bills =
        ResourceController(key: 'bills', cache: cache, fetcher: _fetchBills);
    _unbilled = ResourceController(
      key: 'bills-unbilled',
      cache: cache,
      fetcher: _fetchUnbilled,
    );
    _bills.addListener(_onChanged);
    _unbilled.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _bills.removeListener(_onChanged);
    _unbilled.removeListener(_onChanged);
    _bills.dispose();
    _unbilled.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<List<BillRecord>> _fetchBills() async {
    final payload = await AppScope.read(context).api.get(
      operationsService,
      BillApi.list,
      query: {
        if (_search.isNotEmpty) 'search': _search,
        if (_from != null) 'date_from': Fmt.isoDate(_from),
        if (_to != null) 'date_to': Fmt.isoDate(_to),
        'limit': 200,
      },
    );
    return billsFrom(payload);
  }

  Future<List<UnbilledGatePass>> _fetchUnbilled() async {
    final hotel = AppScope.read(context).hotels.queryParam;
    final payload = await AppScope.read(context).api.get(
      operationsService,
      BillApi.unbilledGatePasses,
      query: {if (hotel != null) 'client_name': hotel},
    );
    return unbilledGatePassesFrom(payload);
  }

  Future<void> _reload() async {
    await Future.wait([_bills.load(force: true), _unbilled.load(force: true)]);
  }

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

  List<BillRecord> get _bills_ => _bills.data ?? const [];
  List<UnbilledGatePass> get _unbilled_ => _unbilled.data ?? const [];

  List<OpsMetric> get _metrics {
    final outstanding = _bills_
        .where((b) => !b.isCancelled)
        .fold<double>(0, (sum, b) => sum + b.owed);
    final collected = _bills_.fold<double>(0, (sum, b) => sum + b.paidAmount);
    return [
      OpsMetric(
        id: 'total',
        label: 'Bills',
        value: '${_bills_.length}',
        icon: Icons.receipt_long_outlined,
        tone: AppTone.info,
      ),
      OpsMetric(
        id: 'outstanding',
        label: 'Outstanding',
        value: outstanding.toStringAsFixed(2),
        icon: Icons.account_balance_wallet_outlined,
        tone: AppTone.danger,
        money: true,
      ),
      OpsMetric(
        id: 'collected',
        label: 'Collected',
        value: collected.toStringAsFixed(2),
        icon: Icons.verified_outlined,
        tone: AppTone.success,
        money: true,
      ),
      OpsMetric(
        id: 'unbilled',
        label: 'Unbilled gate passes',
        value: '${_unbilled_.length}',
        icon: Icons.inventory_2_outlined,
        tone: AppTone.warning,
      ),
      OpsMetric(
        id: 'unbilled-qty',
        label: 'Unbilled items',
        value: Fmt.qty(
          _unbilled_.fold<double>(0, (sum, g) => sum + g.totalUnbilledQty),
        ),
        icon: Icons.archive_outlined,
        tone: AppTone.neutral,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    if (!canView(services, billsPermission)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Bills')),
        body: opsNotPermitted('bills'),
      );
    }

    final rows = _bills_;
    final unbilled = _unbilled_;
    final loading = (_bills.isLoading || _unbilled.isLoading) &&
        rows.isEmpty &&
        unbilled.isEmpty;
    final canWrite = services.auth.hasPermission(billsPermission);

    final outstanding =
        rows.where((b) => !b.isCancelled && b.owed > 0).toList();
    final paid = rows.where((b) => !b.isCancelled && b.owed <= 0).toList();
    final history = rows.where((b) => b.isCancelled).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bills'),
        actions: [
          AppButton.icon(
            icon: Icons.refresh,
            tooltip: 'Refresh',
            loading: _bills.isLoading || _unbilled.isLoading,
            onPressed: _reload,
          ),
        ],
      ),
      body: Column(
        children: [
          AppSyncStatusBar(
            status: _bills.status,
            updatedAt: _bills.lastUpdated,
            label: 'Bills',
          ),
          AppOfflineSyncBar(engine: services.sync),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: AppTextInput(
              controller: _searchCtrl,
              hint: 'Search bills by client or title…',
              icon: Icons.search,
              textInputAction: TextInputAction.search,
              onChanged: (v) {
                setState(() => _search = v.trim());
                _reload();
              },
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: AppDateField(
                    value: _from,
                    hint: 'From',
                    onChanged: (d) {
                      setState(() => _from = d);
                      _reload();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppDateField(
                    value: _to,
                    hint: 'To',
                    onChanged: (d) {
                      setState(() => _to = d);
                      _reload();
                    },
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
                label: const Text('Clear filters'),
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
              child: _bills.phase == LoadPhase.failed &&
                      rows.isEmpty &&
                      unbilled.isEmpty
                  ? AppErrorState(message: _bills.error, onRetry: _reload)
                  : loading
                      ? const AppSkeletonList()
                      : rows.isEmpty && unbilled.isEmpty
                          ? ListView(
                              children: [
                                SizedBox(
                                  height:
                                      MediaQuery.of(context).size.height * 0.4,
                                  child: AppEmptyState(
                                    title: _hasFilters
                                        ? 'No bills match'
                                        : 'No bills yet',
                                    message: _hasFilters
                                        ? 'Try a different search or date range.'
                                        : 'Raise a bill from a quotation or an '
                                            'unbilled gate pass.',
                                    icon: Icons.receipt_long_outlined,
                                    action: canWrite
                                        ? AppButton(
                                            label: 'New bill',
                                            variant: AppButtonVariant.primary,
                                            icon: Icons.add,
                                            onPressed: _openCreate,
                                          )
                                        : null,
                                  ),
                                ),
                              ],
                            )
                          : OpsSectionList<Object>(
                              sections: [
                                OpsSection<Object>(
                                  key: 'outstanding',
                                  label: 'Outstanding',
                                  icon: Icons.account_balance_wallet_outlined,
                                  tone: AppTone.danger,
                                  items: outstanding,
                                ),
                                OpsSection<Object>(
                                  key: 'unbilled',
                                  label: 'Unbilled',
                                  icon: Icons.inventory_2_outlined,
                                  tone: AppTone.warning,
                                  items: unbilled,
                                ),
                                OpsSection<Object>(
                                  key: 'paid',
                                  label: 'Paid',
                                  icon: Icons.verified_outlined,
                                  tone: AppTone.success,
                                  items: paid,
                                ),
                                OpsSection<Object>(
                                  key: 'history',
                                  label: 'History',
                                  icon: Icons.archive_outlined,
                                  tone: AppTone.neutral,
                                  items: history,
                                ),
                              ],
                              itemBuilder: (context, item) => item is BillRecord
                                  ? _BillCard(
                                      bill: item,
                                      canWrite: canWrite,
                                      onOpen: () => _openDetail(item.id),
                                      onEdit: () => _openEdit(item.id),
                                      onDelete: () => _confirmDelete(item),
                                    )
                                  : _UnbilledCard(
                                      gatePass: item as UnbilledGatePass,
                                      canWrite: canWrite,
                                      onBill: () => _openCreate(item.id),
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
              label: const Text('New bill'),
            )
          : null,
    );
  }

  Future<void> _openCreate([String? gatePassId]) async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BillFormPage(
          gatePassId: gatePassId,
          clientName: gatePassId == null
              ? null
              : _unbilled_
                  .where((g) => g.id == gatePassId)
                  .map((g) => g.clientName)
                  .firstOrNull,
        ),
      ),
    );
    if (!mounted) return;
    if (created == true) _reload();
  }

  Future<void> _openEdit(String id) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => BillFormPage(billId: id)),
    );
    if (!mounted) return;
    if (saved == true) _reload();
  }

  Future<void> _openDetail(String id) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => BillDetailPage(billId: id)),
    );
    if (mounted) _reload();
  }

  Future<void> _confirmDelete(BillRecord bill) async {
    final ok = await AppConfirmDialog.show(
      context,
      title: 'Delete this bill?',
      message: 'Bill #${bill.id} for ${bill.clientName} will be removed '
          'permanently. Payments recorded against it are kept.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      final result = await AppScope.read(context)
          .api
          .delete(operationsService, BillApi.one(bill.id));
      if (!mounted) return;
      QueryCacheInvalidator.instance.invalidate(_bills.key);
      await _bills.refresh();
      if (!mounted) return;
      AppToast.info(
        context,
        result is QueuedResponse
            ? 'Queued — will sync when back online'
            : 'Bill deleted',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      AppToast.error(context, e.message);
    }
  }
}

class _BillCard extends StatelessWidget {
  const _BillCard({
    required this.bill,
    required this.canWrite,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  final BillRecord bill;
  final bool canWrite;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AppCard(
      onTap: onOpen,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bill.clientName,
                      style: context.texts.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '#${bill.id} · ${Fmt.date(bill.createdAt)}',
                      style:
                          context.texts.bodySmall?.copyWith(color: c.fgMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              BillStatusBadge(status: bill.paymentStatus),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${Fmt.count(bill.itemCount)} items · ${Fmt.qty(bill.totalQuantity)} pcs',
                  style: context.texts.bodySmall?.copyWith(color: c.fgMuted),
                ),
              ),
              Text(
                Fmt.money(bill.grand),
                style: context.texts.titleSmall,
              ),
            ],
          ),
          if (bill.owed > 0) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 13, color: c.danger),
                const SizedBox(width: 5),
                Text(
                  '${Fmt.money(bill.owed)} outstanding',
                  style: context.texts.labelMedium?.copyWith(color: c.danger),
                ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              if (bill.verificationStatus != null)
                VerificationStatusBadge(status: bill.verificationStatus),
              const Spacer(),
              EntityCardActions(
                canWrite: canWrite,
                onOpen: onOpen,
                onEdit: bill.isPaid ? null : onEdit,
                onDelete: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UnbilledCard extends StatelessWidget {
  const _UnbilledCard({
    required this.gatePass,
    required this.canWrite,
    required this.onBill,
  });

  final UnbilledGatePass gatePass;
  final bool canWrite;
  final VoidCallback onBill;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      gatePass.clientName,
                      style: context.texts.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Gate pass ${gatePass.gatePassNumber} · ${Fmt.date(gatePass.receivingDate)}',
                      style:
                          context.texts.bodySmall?.copyWith(color: c.fgMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AppBadge(
                '${Fmt.qty(gatePass.totalUnbilledQty)} pcs',
                tone: AppTone.warning,
                compact: true,
              ),
            ],
          ),
          if (gatePass.unbilledItems.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final item in gatePass.unbilledItems.take(4))
                  AppBadge(
                    '${item.itemName} +${Fmt.qty(item.unbilledQty)}',
                    tone: AppTone.neutral,
                    compact: true,
                  ),
                if (gatePass.unbilledItems.length > 4)
                  AppBadge(
                    '+${gatePass.unbilledItems.length - 4} more',
                    tone: AppTone.neutral,
                    compact: true,
                  ),
              ],
            ),
          ],
          if (canWrite) ...[
            const SizedBox(height: 10),
            AppButton(
              label: 'Raise bill',
              icon: Icons.receipt_long_outlined,
              size: AppButtonSize.sm,
              variant: AppButtonVariant.primary,
              onPressed: onBill,
            ),
          ],
        ],
      ),
    );
  }
}
