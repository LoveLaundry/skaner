import 'package:flutter/material.dart';

import '../../../config/api_config.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/utils/formatting.dart';
import '../../../data/resource_controller.dart';
import '../../../state/app_scope.dart';
import '../../../ui/kit/data.dart';
import '../../../ui/kit/feedback.dart';
import '../../../ui/kit/inputs.dart';
import '../../../ui/kit/primitives.dart';
import '../../../ui/shell/app_shell.dart';
import '../../../ui/theme.dart';

/// Port of `features/today/pages/today-page.tsx`.
///
/// One operating day, read from the server's own ledgers: gate passes, deliveries,
/// the adjustments queue, reconciliation issues, day money, the event journal and
/// the end-of-day snapshot. Every figure is either the server's number or a sum
/// over a server's rows — the screen never keeps a second copy of a balance.
class TodayPage extends StatefulWidget {
  const TodayPage({super.key});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  late DateTime _date;
  bool _busy = false;
  final _note = TextEditingController();

  late final ResourceController<List<Map<String, dynamic>>> _gatepasses;
  late final ResourceController<List<Map<String, dynamic>>> _deliveries;
  late final ResourceController<List<Map<String, dynamic>>> _adjustments;
  late final ResourceController<Map<String, dynamic>> _recon;
  late ResourceController<Map<String, dynamic>> _money;
  late ResourceController<List<Map<String, dynamic>>> _events;
  late final ResourceController<List<Map<String, dynamic>>> _pendingPasses;
  late final ResourceController<List<Map<String, dynamic>>> _pendingItems;
  late final ResourceController<List<Map<String, dynamic>>> _pendingResend;
  late ResourceController<List<Map<String, dynamic>>> _expenses;
  ResourceController<Map<String, dynamic>>? _dayClose;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = DateTime(now.year, now.month, now.day);

    _gatepasses = _rows('today.gatepasses', () => _get('/gatepasses'));
    _deliveries = _rows('today.deliveries', () => _get('/deliveries'));
    _adjustments = _rows('today.adjustments',
        () => _get('/adjustments', query: {'status': 'REQUESTED'}));
    _recon =
        _one('today.reconciliation', () => _getOne('/reconciliation/issues'));
    _money =
        _one('today.money', () => _getOne('/day-money', query: {'date': _iso}));
    _events =
        _rows('today.events', () => _get('/events', query: {'date': _iso}));
    _pendingPasses =
        _rows('today.pending', () => _get('/deliveries/pending-gatepasses'));
    // Same key as the notification bell, so anything that moves a quantity
    // invalidates the outstanding balance this screen sums.
    _pendingItems = _rows('notifications.gatepass-pending',
        () => _get('/notifications/gatepass-pending'));
    _pendingResend =
        _rows('today.returns', () => _get('/returns/pending-resent'));
    _expenses = _rows('today.expenses', () => _expensesForDay());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDay();
      for (final c in [
        _gatepasses,
        _deliveries,
        _adjustments,
        _recon,
        _pendingPasses,
        _pendingItems,
        _pendingResend,
      ]) {
        c.load(force: true);
      }
    });
  }

  ResourceController<List<Map<String, dynamic>>> _rows(
    String key,
    Future<List<Map<String, dynamic>>> Function() fetcher,
  ) =>
      ResourceController<List<Map<String, dynamic>>>(
        key: key,
        cache: AppScope.read(context).cache,
        fetcher: fetcher,
      )..addListener(_onChanged);

  ResourceController<Map<String, dynamic>> _one(
    String key,
    Future<Map<String, dynamic>> Function() fetcher,
  ) =>
      ResourceController<Map<String, dynamic>>(
        key: key,
        cache: AppScope.read(context).cache,
        fetcher: fetcher,
      )..addListener(_onChanged);

  @override
  void dispose() {
    for (final c in [
      _gatepasses,
      _deliveries,
      _adjustments,
      _recon,
      _money,
      _events,
      _pendingPasses,
      _pendingItems,
      _pendingResend,
      _expenses,
    ]) {
      c.removeListener(_onChanged);
      c.dispose();
    }
    _dayClose?.removeListener(_onChanged);
    _dayClose?.dispose();
    _note.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  String get _iso => Fmt.isoDate(_date);

  bool get _isToday {
    final now = DateTime.now();
    return _date.year == now.year &&
        _date.month == now.month &&
        _date.day == now.day;
  }

  bool get _isFuture {
    final now = DateTime.now();
    return _date.isAfter(DateTime(now.year, now.month, now.day));
  }

  Future<List<Map<String, dynamic>>> _get(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final s = AppScope.read(context);
    return asRows(await s.api.get(ServiceNames.bills, path, query: query));
  }

  Future<Map<String, dynamic>> _getOne(String path,
      {Map<String, dynamic>? query}) async {
    final s = AppScope.read(context);
    final payload = await s.api.get(ServiceNames.bills, path, query: query);
    if (payload is Map) return Map<String, dynamic>.from(payload);
    return const {};
  }

  Future<List<Map<String, dynamic>>> _expensesForDay() async {
    final s = AppScope.read(context);
    try {
      return asRows(await s.api.get(
        ServiceNames.management,
        '/api/expenses/summary',
        query: {'start_date': _iso, 'end_date': _iso},
      ));
    } catch (_) {
      // The management service is optional in a laundry-only deployment; the
      // day still has to be closable without it.
      return const [];
    }
  }

  void _setDate(DateTime next) {
    setState(() {
      _date = DateTime(next.year, next.month, next.day);
      _note.clear();
    });
    _loadDay();
  }

  void _shiftDate(int days) => _setDate(_date.add(Duration(days: days)));

  /// The four reads that are scoped to the selected day.
  void _loadDay() {
    _money
      ..removeListener(_onChanged)
      ..dispose();
    _dayClose?.removeListener(_onChanged);
    _dayClose?.dispose();

    _money = _one('today.money.$_iso',
        () => _getOne('/day-money', query: {'date': _iso}));
    _events
      ..removeListener(_onChanged)
      ..dispose();
    _events = _rows(
        'today.events.$_iso', () => _get('/events', query: {'date': _iso}));
    _expenses
      ..removeListener(_onChanged)
      ..dispose();
    _expenses = _rows('today.expenses.$_iso', _expensesForDay);
    _dayClose = _one('today.dayclose.$_iso',
        () => _getOne('/day-close', query: {'date': _iso}));

    for (final c in [_money, _events, _expenses, _dayClose!]) {
      c.load(force: true);
    }
  }

  // ── Derived figures ─────────────────────────────────────────────────────────

  List<Map<String, dynamic>> get _dayGatepasses =>
      (_gatepasses.data ?? const [])
          .where((gp) => _dayOf(pick(gp, ['receiving_date'])) == _iso)
          .where((gp) => str(gp, ['status']).toUpperCase() != 'CANCELLED')
          .toList();

  List<Map<String, dynamic>> get _dayDeliveries =>
      (_deliveries.data ?? const [])
          .where((d) => _dayOf(pick(d, ['delivery_date'])) == _iso)
          .where((d) => str(d, ['status']).toUpperCase() != 'CANCELLED')
          .toList();

  double get _itemsReceived => _dayGatepasses.fold(0.0, (sum, gp) {
        return sum +
            asRows(pick(gp, ['items'])).fold(
                0.0, (s, it) => s + numOf(it, ['received_qty', 'quantity']));
      });

  double get _itemsDelivered => _dayDeliveries.fold(0.0, (sum, d) {
        return sum +
            asRows(pick(d, ['items'])).fold(
                0.0, (s, it) => s + numOf(it, ['quantity', 'delivered_qty']));
      });

  double get _expensesTotal => (_expenses.data ?? const [])
      .fold(0.0, (sum, row) => sum + numOf(row, ['total', 'amount']));

  List<Map<String, dynamic>> get _adjustmentRows =>
      _adjustments.data ?? const [];

  List<Map<String, dynamic>> get _reconRows => _recon.data == null
      ? const []
      : asRows(_recon.data!['items'] ?? _recon.data!['rows']);

  /// Outstanding is a balance, so it comes from the server's pending feed scoped
  /// to passes received that day rather than being rebuilt from deliveries.
  double get _piecesOutstanding => (_pendingItems.data ?? const [])
      .where((e) => _dayOf(pick(e, ['receiving_date'])) == _iso)
      .fold(0.0, (sum, e) => sum + numOf(e, ['pending', 'total_pending']));

  int get _openFlags => _adjustmentRows.length + _reconRows.length;

  static String _dayOf(Object? iso) {
    if (iso == null) return '';
    final s = iso.toString();
    return s.length >= 10 ? s.substring(0, 10) : '';
  }

  Map<String, double> get _totals {
    final money = _money.data ?? const {};
    final billed = numOf(money, ['billed_amount']);
    final collected = numOf(money, ['collected_amount']);
    return {
      'gate_pass_count': _dayGatepasses.length.toDouble(),
      'pieces_received': _itemsReceived,
      'delivery_count': _dayDeliveries.length.toDouble(),
      'pieces_delivered': _itemsDelivered,
      'pieces_outstanding': _piecesOutstanding,
      'pending_adjustments': _adjustmentRows.length.toDouble(),
      'reconciliation_issues': _reconRows.length.toDouble(),
      'billed_amount': billed,
      'collected_amount': collected,
      'expenses_amount': _expensesTotal,
      'outstanding_amount': numOf(money, ['outstanding_amount']),
    };
  }

  static const _eventLabels = {
    'GATEPASS_CREATED': 'Gate pass received',
    'GATEPASS_STATUS_CHANGED': 'Gate pass status changed',
    'DELIVERY_CREATED': 'Delivery dispatched',
    'BILL_CREATED': 'Bill created',
    'PAYMENT_RECORDED': 'Payment recorded',
    'ADJUSTMENT_REQUESTED': 'Adjustment requested',
    'ADJUSTMENT_APPROVED': 'Adjustment approved',
    'ADJUSTMENT_REJECTED': 'Adjustment rejected',
    'RETURN_RECORDED': 'Return recorded',
    'DAY_CLOSED': 'Day closed',
  };

  String _eventLabel(String type) =>
      _eventLabels[type] ?? type.replaceAll('_', ' ').toLowerCase();

  // ── Writes ─────────────────────────────────────────────────────────────────

  Future<void> _actOnAdjustment(Map<String, dynamic> row, bool approve) async {
    final id = str(row, ['id']);
    if (id.isEmpty) return;
    final ok = await AppConfirmDialog.show(
      context,
      title: approve ? 'Approve adjustment?' : 'Reject adjustment?',
      message: '${str(row, ['item_name'])}'
          '${str(row, [
            'specification'
          ]).isEmpty ? '' : ' (${str(row, ['specification'])})'}'
          ' — ${str(row, ['reason'])}',
      confirmLabel: approve ? 'Approve' : 'Reject',
      destructive: !approve,
    );
    if (!ok || !mounted) return;
    final s = AppScope.read(context);
    try {
      final result = await s.api.post(ServiceNames.bills,
          '/adjustments/$id/${approve ? 'approve' : 'reject'}');
      if (!mounted) return;
      if (result is QueuedResponse) {
        AppToast.info(
            context, 'Queued — it will sync when you are back online');
      } else {
        AppToast.success(
            context, 'Adjustment ${approve ? 'approved' : 'rejected'}');
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, extractErrorMessage(e));
    }
    await _adjustments.refresh();
    await _recon.refresh();
  }

  Future<void> _closeDay() async {
    final totals = _totals;
    final ok = await AppConfirmDialog.show(
      context,
      title: (_dayClose?.hasData ?? false)
          ? 'Re-close the day?'
          : 'Close the day?',
      message:
          'This writes an end-of-day snapshot into the journal; the numbers '
          'below are frozen at this moment.',
      confirmLabel:
          (_dayClose?.hasData ?? false) ? 'Re-close day' : 'Close day',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final s = AppScope.read(context);
    try {
      final result = await s.api.post(ServiceNames.bills, '/day-close', body: {
        'date': _iso,
        'totals': {
          'gate_pass_count': totals['gate_pass_count']!.round(),
          'pieces_received': totals['pieces_received'],
          'delivery_count': totals['delivery_count']!.round(),
          'pieces_delivered': totals['pieces_delivered'],
          'pieces_outstanding': totals['pieces_outstanding'],
          'pending_adjustments': totals['pending_adjustments']!.round(),
          'reconciliation_issues': totals['reconciliation_issues']!.round(),
          'billed_amount': totals['billed_amount'],
          'collected_amount': totals['collected_amount'],
          'expenses_amount': totals['expenses_amount'],
          'outstanding_amount': totals['outstanding_amount'],
        },
        if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
      });
      if (!mounted) return;
      if (result is QueuedResponse) {
        AppToast.info(context, 'Queued — the snapshot will sync when online');
      } else {
        AppToast.success(context, 'Day closed for $_iso');
      }
      _note.clear();
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, extractErrorMessage(e));
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await _events.refresh();
    await _dayClose?.refresh();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final busy = _money.isLoading && !_money.hasData;

    return Column(
      children: [
        AppPageHeader(
          title: _isToday ? 'Today' : _longDay(_date),
          subtitle: _isToday
              ? '${_longDay(_date)} · Love Laundry daily operations'
              : 'Reviewing a past day',
          busy: busy,
          actions: [_dateStepper()],
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _reloadAll,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
              children: [
                _quickActions(),
                const SizedBox(height: 16),
                _volumeGrid(),
                const SizedBox(height: 16),
                _moneyCard(),
                const SizedBox(height: 14),
                _returnsOwedCard(),
                const SizedBox(height: 14),
                _attentionCard(),
                const SizedBox(height: 14),
                _pendingCard(),
                const SizedBox(height: 14),
                _timelineCard(),
                const SizedBox(height: 14),
                _closeDayCard(),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: AppButton(
                    label: 'Open full dashboard',
                    icon: Icons.insights_outlined,
                    variant: AppButtonVariant.secondary,
                    onPressed: () =>
                        AppNavigatorPush.push(context, '/dashboard'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _reloadAll() async {
    _loadDay();
    await Future.wait([
      _gatepasses.load(force: true),
      _deliveries.load(force: true),
      _adjustments.load(force: true),
      _recon.load(force: true),
      _pendingPasses.load(force: true),
      _pendingItems.load(force: true),
      _pendingResend.load(force: true),
    ]);
  }

  Widget _dateStepper() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            label: '',
            icon: Icons.chevron_left_rounded,
            variant: AppButtonVariant.secondary,
            size: AppButtonSize.sm,
            onPressed: () => _shiftDate(-1),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 132,
            child: AppDateField(
              value: _date,
              lastDate: DateTime.now(),
              onChanged: (v) {
                if (v != null) _setDate(v);
              },
            ),
          ),
          const SizedBox(width: 6),
          AppButton(
            label: '',
            icon: Icons.chevron_right_rounded,
            variant: AppButtonVariant.secondary,
            size: AppButtonSize.sm,
            onPressed: _isToday ? null : () => _shiftDate(1),
          ),
          if (!_isToday) ...[
            const SizedBox(width: 6),
            AppButton(
              label: 'Today',
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.sm,
              onPressed: () => _setDate(DateTime.now()),
            ),
          ],
        ],
      );

  static const _actions = [
    (
      label: 'Receive',
      hint: 'New gate pass',
      icon: Icons.assignment_outlined,
      path: '/gatepasses/new',
      main: true
    ),
    (
      label: 'Deliver',
      hint: 'Record delivery',
      icon: Icons.local_shipping_outlined,
      path: '/deliveries/new',
      main: true
    ),
    (
      label: 'Bill',
      hint: 'Create bill',
      icon: Icons.receipt_long_outlined,
      path: '/bills/new',
      main: false
    ),
    (
      label: 'Return',
      hint: 'Record return',
      icon: Icons.undo_outlined,
      path: '/returns/new',
      main: false
    ),
    (
      label: 'Expense',
      hint: 'Record expense',
      icon: Icons.payments_outlined,
      path: '/management/expenses',
      main: false
    ),
    (
      label: 'Attendance',
      hint: 'Log staff',
      icon: Icons.event_available_outlined,
      path: '/management/attendance-log',
      main: false
    ),
  ];

  Widget _quickActions() {
    final c = context.c;
    final t = context.texts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick actions', style: t.labelMedium?.copyWith(color: c.fgMuted)),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.15,
          children: [
            for (final a in _actions)
              AppCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                onTap: () => AppNavigatorPush.push(context, a.path),
                child: Row(
                  children: [
                    Icon(a.icon, size: 16, color: c.fg3),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(a.label,
                                    style: t.labelLarge?.copyWith(color: c.fg),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                              if (a.main) ...[
                                const SizedBox(width: 5),
                                const AppBadge('Main', tone: AppTone.brand),
                              ],
                            ],
                          ),
                          Text(a.hint,
                              style: t.labelSmall?.copyWith(color: c.fgFaint),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _volumeGrid() {
    final pending = _adjustmentRows.length;
    final issues = _reconRows.length;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.7,
      children: [
        AppStatCard(
          label: 'Gate passes in',
          value: Fmt.count(_dayGatepasses.length),
          compact: true,
          icon: Icons.assignment_outlined,
          onTap: () => AppNavigatorPush.push(context, '/gatepasses'),
        ),
        AppStatCard(
          label: 'Items received',
          value: Fmt.qty(_itemsReceived),
          compact: true,
          icon: Icons.inventory_2_outlined,
          onTap: () => AppNavigatorPush.push(context, '/gatepasses'),
        ),
        AppStatCard(
          label: 'Deliveries out',
          value: Fmt.count(_dayDeliveries.length),
          compact: true,
          icon: Icons.local_shipping_outlined,
          onTap: () => AppNavigatorPush.push(context, '/deliveries'),
        ),
        AppStatCard(
          label: 'Items delivered',
          value: Fmt.qty(_itemsDelivered),
          compact: true,
          icon: Icons.outbound_outlined,
          onTap: () => AppNavigatorPush.push(context, '/deliveries'),
        ),
        AppStatCard(
          label: 'Pending adjustments',
          value: Fmt.count(pending),
          compact: true,
          icon: Icons.tune_outlined,
          footer: pending > 0
              ? Text('Awaiting approval',
                  style: context.texts.labelSmall
                      ?.copyWith(color: context.c.warning))
              : null,
        ),
        AppStatCard(
          label: 'Reconciliation issues',
          value: Fmt.count(issues),
          compact: true,
          icon: Icons.rule_outlined,
          footer: issues > 0
              ? Text('Needs review',
                  style: context.texts.labelSmall
                      ?.copyWith(color: context.c.danger))
              : null,
        ),
      ],
    );
  }

  Widget _moneyTile(String label, double value, {AppTone? accent}) {
    final c = context.c;
    final t = context.texts;
    final color = accent == null ? c.fg : accent.resolve(c).$1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: c.line2),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: t.labelSmall?.copyWith(color: c.fgMuted)),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              Fmt.money(value),
              style: t.titleMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _moneyCard() {
    final c = context.c;
    final t = context.texts;
    final money = _money.data ?? const {};
    final collected = numOf(money, ['collected_amount']);
    final expenses = _expensesTotal;
    final net = collected - expenses;
    final outstanding = numOf(money, ['outstanding_amount']);
    final openBills = intOf(money, ['open_bills_count']);
    final bills = intOf(money, ['bills_created']);
    final payments = intOf(money, ['payments_count']);

    return _section(
      title: 'Money for the day',
      icon: Icons.account_balance_wallet_outlined,
      loading: _money.isLoading && !_money.hasData,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.5,
            children: [
              _moneyTile('Billed today', numOf(money, ['billed_amount'])),
              _moneyTile('Collected today', collected, accent: AppTone.success),
              _moneyTile('Expenses today', expenses, accent: AppTone.danger),
              _moneyTile('Net for day', net,
                  accent: net < 0 ? AppTone.warning : null),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Outstanding receivable',
                      style: t.bodySmall?.copyWith(color: c.fgMuted)),
                  const SizedBox(width: 6),
                  Text(
                    Fmt.money(outstanding),
                    style: t.labelLarge
                        ?.copyWith(color: outstanding > 0 ? c.warning : c.fg),
                  ),
                  const SizedBox(width: 4),
                  Text('across $openBills open bills',
                      style: t.bodySmall?.copyWith(color: c.fgFaint)),
                ],
              ),
              Text(
                '$bills bill${bills == 1 ? '' : 's'} created · '
                '$payments payment${payments == 1 ? '' : 's'} recorded',
                style: t.bodySmall?.copyWith(color: c.fgFaint),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _returnsOwedCard() {
    final c = context.c;
    final records = _pendingResend.data ?? const [];
    final owed = records.fold<double>(0, (sum, r) {
      return sum +
          asRows(pick(r, ['items']))
              .fold(0.0, (s, i) => s + numOf(i, ['returned_qty', 'qty']));
    });
    final loading = _pendingResend.isLoading && !_pendingResend.hasData;

    return _section(
      title: 'Returns owed to clients',
      icon: Icons.undo_outlined,
      loading: loading,
      child: records.isEmpty
          ? const AppNotice(
              message: 'No pending resends — every return item is settled.',
              tone: AppTone.success,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$owed piece${owed == 1 ? '' : 's'} still owed across '
                  '${records.length} return${records.length == 1 ? '' : 's'}',
                  style: context.texts.bodySmall?.copyWith(color: c.fgMuted),
                ),
                const SizedBox(height: 8),
                for (final r in records.take(4)) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          str(r, ['client_name'], '—'),
                          style: context.texts.bodySmall?.copyWith(color: c.fg),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${asRows(pick(r, [
                              'items'
                            ])).fold<double>(0, (s, i) => s + numOf(i, [
                                  'returned_qty',
                                  'qty'
                                ]))} pcs',
                        style:
                            context.texts.bodySmall?.copyWith(color: c.fgMuted),
                      ),
                    ],
                  ),
                  if (r != records.take(4).last) const Divider(height: 10),
                ],
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: AppButton(
                    label: 'Review returns',
                    icon: Icons.arrow_forward_rounded,
                    variant: AppButtonVariant.ghost,
                    size: AppButtonSize.sm,
                    onPressed: () => AppNavigatorPush.push(context, '/returns'),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _attentionCard() {
    final c = context.c;
    final t = context.texts;
    final pending = _adjustmentRows;
    final issues = _reconRows;
    final clear = pending.isEmpty && issues.isEmpty;
    final loading = (_adjustments.isLoading && !_adjustments.hasData) ||
        (_recon.isLoading && !_recon.hasData);

    return _section(
      title: 'Needs attention',
      icon: Icons.gpp_maybe_outlined,
      trailing: clear
          ? null
          : AppBadge('${pending.length + issues.length} open',
              tone: AppTone.danger, solid: true, compact: true),
      loading: loading,
      child: clear
          ? const AppNotice(
              title: 'All clear',
              message: 'No pending adjustments and no reconciliation issues.',
              tone: AppTone.success,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (pending.isNotEmpty) ...[
                  Text('Quantity adjustments awaiting approval',
                      style: t.labelMedium?.copyWith(color: c.fgMuted)),
                  const SizedBox(height: 8),
                  for (final a in pending) ...[
                    AppCard(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  str(a, ['item_name'], '—'),
                                  style: t.labelLarge?.copyWith(color: c.fg),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${Fmt.qty(numOf(a, ['original_qty']))} → '
                                  '${Fmt.qty(numOf(a, ['corrected_qty']))}'
                                  '${str(a, [
                                        'reason'
                                      ]).isEmpty ? '' : ' · ${str(a, [
                                          'reason'
                                        ])}'}'
                                  '${str(a, [
                                        'requested_by'
                                      ]).isEmpty ? '' : ' · by ${str(a, [
                                          'requested_by'
                                        ])}'}',
                                  style:
                                      t.labelSmall?.copyWith(color: c.fgMuted),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          AppButton(
                            label: 'Reject',
                            icon: Icons.cancel_outlined,
                            variant: AppButtonVariant.ghost,
                            size: AppButtonSize.sm,
                            onPressed: () => _actOnAdjustment(a, false),
                          ),
                          const SizedBox(width: 4),
                          AppButton(
                            label: 'Approve',
                            icon: Icons.check_circle_outline,
                            size: AppButtonSize.sm,
                            onPressed: () => _actOnAdjustment(a, true),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
                if (issues.isNotEmpty) ...[
                  Text('Reconciliation issues',
                      style: t.labelMedium?.copyWith(color: c.fgMuted)),
                  const SizedBox(height: 8),
                  for (final row in issues.take(8))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading:
                          Icon(Icons.error_outline, size: 17, color: c.warning),
                      title: Text(
                        '#${str(row, ['gate_pass_number'])} · ${str(row, [
                              'client_name'
                            ])}',
                        style: t.labelLarge?.copyWith(color: c.fg),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        [
                          ...asRows(pick(row, ['issues']))
                              .map((i) => str(i, ['code']))
                              .where((s) => s.isNotEmpty),
                          if (boolOf(row, ['legacy_marked'])) 'legacy marked',
                        ].join(', '),
                        style: t.labelSmall?.copyWith(color: c.fgMuted),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing:
                          const Icon(Icons.chevron_right_rounded, size: 18),
                      onTap: () => AppNavigatorPush.push(
                          context, '/gatepasses/${str(row, ['id'])}'),
                    ),
                ],
              ],
            ),
    );
  }

  Widget _pendingCard() {
    final c = context.c;
    final t = context.texts;
    final rows = (_pendingPasses.data ?? const [])
        .where((r) => numOf(r, ['total_pending']) > 0)
        .toList();
    final loading = _pendingPasses.isLoading && !_pendingPasses.hasData;

    return _section(
      title: 'Pending to deliver',
      icon: Icons.inventory_2_outlined,
      trailing: rows.isEmpty
          ? null
          : AppButton(
              label: 'Deliver',
              icon: Icons.local_shipping_outlined,
              size: AppButtonSize.sm,
              onPressed: () =>
                  AppNavigatorPush.push(context, '/deliveries/new'),
            ),
      loading: loading,
      child: rows.isEmpty
          ? const AppEmptyState(
              title: 'Nothing pending',
              message: 'Every received item has been delivered.',
              icon: Icons.local_shipping_outlined,
              compact: true,
            )
          : Column(
              children: [
                for (final r in rows) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: () => AppNavigatorPush.push(
                        context, '/gatepasses/${str(r, ['gate_pass_id'])}'),
                    leading: Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.warningSoft,
                        borderRadius: BorderRadius.circular(Radii.sm),
                        border: Border.all(color: c.warningBorder),
                      ),
                      child: Text(
                        Fmt.qty(numOf(r, ['total_pending'])),
                        style: t.labelMedium?.copyWith(color: c.warning),
                      ),
                    ),
                    title: Text(
                      str(r, ['client_name'], '—'),
                      style: t.labelLarge?.copyWith(color: c.fg),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '#${str(r, ['gate_pass_number'])} · '
                      '${asRows(pick(r, [
                            'items'
                          ])).where((i) => numOf(i, ['pending_qty']) > 0).map((i) => '${str(i, [
                                'item_name'
                              ])} ×${Fmt.qty(numOf(i, [
                                'pending_qty'
                              ]))}').join(', ')}',
                      style: t.labelSmall?.copyWith(color: c.fgMuted),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, size: 18),
                  ),
                  if (r != rows.last) const Divider(height: 10),
                ],
              ],
            ),
    );
  }

  Widget _timelineCard() {
    final c = context.c;
    final t = context.texts;
    final events = _events.data ?? const [];
    final loading = _events.isLoading && !_events.hasData;

    return _section(
      title: 'Activity timeline',
      icon: Icons.monitor_heart_outlined,
      loading: loading,
      child: events.isEmpty
          ? const AppEmptyState(
              title: 'No activity recorded',
              message:
                  'Movements for this day will appear here as they are entered.',
              icon: Icons.schedule_outlined,
              compact: true,
            )
          : Column(
              children: [
                for (final e in events) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 46,
                        child: Text(
                          Fmt.time(pick(e, ['occurred_at'])),
                          style: t.labelSmall?.copyWith(color: c.fgFaint),
                          textAlign: TextAlign.right,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: c.brand,
                            shape: BoxShape.circle,
                            border: Border.all(color: c.surface, width: 2),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text.rich(
                              TextSpan(children: [
                                TextSpan(
                                  text: _eventLabel(str(e, ['event_type'])),
                                  style: t.bodyMedium?.copyWith(color: c.fg),
                                ),
                                if (asRows(pick(e, ['item_deltas'])).isNotEmpty)
                                  TextSpan(
                                    text: ' · ${asRows(pick(e, [
                                          'item_deltas'
                                        ])).map((d) {
                                      final before =
                                          pick(d, ['before', 'qty_before']);
                                      final after =
                                          pick(d, ['after', 'qty_after']);
                                      return '${str(d, ['item_name'])} '
                                          '${before == null ? '—' : Fmt.qty(asDouble(before))}→'
                                          '${after == null ? '—' : Fmt.qty(asDouble(after))}';
                                    }).join(', ')}',
                                    style:
                                        t.bodySmall?.copyWith(color: c.fgMuted),
                                  ),
                              ]),
                            ),
                            if (str(e, ['user_name']).isNotEmpty ||
                                str(e, ['reason']).isNotEmpty)
                              Text(
                                '${str(e, ['user_name'], 'system')}'
                                '${str(e, [
                                      'reason'
                                    ]).isEmpty ? '' : ' · ${str(e, [
                                        'reason'
                                      ])}'}',
                                style: t.labelSmall?.copyWith(color: c.fgFaint),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (e != events.last) const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }

  Widget _closeDayCard() {
    final c = context.c;
    final t = context.texts;
    final totals = _totals;
    final closed = _dayClose?.data;
    final hasClosed = closed != null && closed.isNotEmpty;
    final closedAt = hasClosed ? pick(closed, ['meta']) : null;
    final closedTime = closedAt is Map
        ? pick(Map<String, dynamic>.from(closedAt), ['closed_at'])
        : null;
    final net = totals['collected_amount']! - totals['expenses_amount']!;
    final loading = (_dayClose?.isLoading ?? false) && !_dayClose!.hasData;

    return _section(
      title: 'Close day',
      icon: Icons.flag_outlined,
      trailing: hasClosed
          ? AppBadge(
              'Closed${closedTime == null ? '' : ' · ${Fmt.time(closedTime)}'}',
              tone: AppTone.success,
              solid: true,
              compact: true)
          : null,
      loading: loading,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.6,
            children: [
              for (final row in const [
                ('Gate passes received', 'gate_pass_count'),
                ('Pieces received', 'pieces_received'),
                ('Deliveries recorded', 'delivery_count'),
                ('Pieces delivered', 'pieces_delivered'),
                ('Pieces outstanding', 'pieces_outstanding'),
              ])
                _countTile(row.$1, totals[row.$2]!,
                    warn:
                        row.$2 == 'pieces_outstanding' && totals[row.$2]! > 0),
            ],
          ),
          const SizedBox(height: 12),
          Text('Money for the day',
              style: t.labelMedium?.copyWith(color: c.fgMuted)),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.5,
            children: [
              _moneyTile('Billed', totals['billed_amount']!),
              _moneyTile('Collected', totals['collected_amount']!,
                  accent: AppTone.success),
              _moneyTile('Expenses', totals['expenses_amount']!,
                  accent: AppTone.danger),
              _moneyTile('Net for day', net,
                  accent: net < 0 ? AppTone.warning : AppTone.success),
            ],
          ),
          if (_openFlags > 0) ...[
            const SizedBox(height: 12),
            AppNotice(
              tone: AppTone.warning,
              message: '${totals['pending_adjustments']!.round()} pending '
                  'adjustment${totals['pending_adjustments']! == 1 ? '' : 's'} and '
                  '${totals['reconciliation_issues']!.round()} reconciliation '
                  'issue${totals['reconciliation_issues']! == 1 ? '' : 's'} still open. '
                  'Resolve them in Needs attention before closing.',
            ),
          ],
          if (hasClosed) ...[
            const SizedBox(height: 12),
            AppNotice(
              tone: AppTone.success,
              title: 'Day already closed',
              message:
                  'Re-close to record a fresh snapshot of the current numbers.'
                  '${str(closed, [
                    'reason'
                  ]).isEmpty ? '' : ' Note: "${str(closed, ['reason'])}"'}',
            ),
          ],
          if (_isFuture) ...[
            const SizedBox(height: 12),
            const AppNotice(
              message:
                  'This is a future day — pick today or an earlier day to close.',
            ),
          ],
          const SizedBox(height: 12),
          AppTextInput(
            controller: _note,
            hint:
                'Optional note for this day\'s close (e.g. late deliveries due)',
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              label: hasClosed ? 'Re-close day' : 'Close day',
              icon: Icons.flag_outlined,
              onPressed: _busy || _isFuture ? null : _closeDay,
            ),
          ),
        ],
      ),
    );
  }

  Widget _countTile(String label, double value, {bool warn = false}) {
    final c = context.c;
    final t = context.texts;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: c.line2),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: t.labelSmall?.copyWith(color: c.fgMuted)),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              Fmt.qty(value),
              style: t.titleMedium?.copyWith(color: warn ? c.warning : c.fg),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section({
    required String title,
    required IconData icon,
    required Widget child,
    Widget? trailing,
    bool loading = false,
  }) {
    final c = context.c;
    final t = context.texts;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
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
              if (loading)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: AppSpinner(size: 14),
                )
              else if (trailing != null)
                trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  static String _longDay(DateTime d) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return '${weekdays[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}';
  }
}
