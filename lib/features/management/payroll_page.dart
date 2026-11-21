import 'package:flutter/material.dart';

import '../../core/utils/formatting.dart';
import '../../data/resource_controller.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/data.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/inputs.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/kit/shell_parts.dart';
import '../../ui/theme.dart';
import '_management_shared.dart';
import 'employee_detail_page.dart';

/// Port of `salary-slip-page.tsx` + `salary-history-page.tsx`: the month's
/// payroll preview with a run button, and the slip ledger with its
/// finalize / pay / cancel actions.
class PayrollPage extends StatefulWidget {
  const PayrollPage({super.key});

  @override
  State<PayrollPage> createState() => _PayrollPageState();
}

class _PayrollPageState extends State<PayrollPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  ResourceController<dynamic> _controller = _unused();
  int _index = 0;
  late int _year;
  late int _month;
  String _statusFilter = 'ALL';
  bool _busy = false;

  static ResourceController<dynamic> _unused() =>
      throw StateError('controller is replaced in initState');

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this)..addListener(_onTab);
    final now = Fmt.lktNow();
    _year = now.year;
    _month = now.month;
    _controller = _build();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _controller.load(force: true),
    );
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTab);
    _tabs.dispose();
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTab() {
    if (_tabs.index == _index) return;
    setState(() => _index = _tabs.index);
    _load();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  ResourceController<dynamic> _build() => ResourceController<dynamic>(
        key: 'management.payroll.$_index.$_year.$_month',
        cache: AppScope.read(context).cache,
        fetcher: _fetch,
      )..addListener(_onChanged);

  void _load() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    setState(() => _controller = _build());
    _controller.load(force: true);
  }

  Future<dynamic> _fetch() async {
    final s = AppScope.read(context);
    if (_index == 0) {
      return s.api.get(mgmt, '/api/salary/payroll-preview',
          query: {'year': _year, 'month': _month});
    }
    return s.api.get(mgmt, '/api/salary/slips', query: {
      'year': _year,
      'month': _month,
      if (_statusFilter != 'ALL') 'status': _statusFilter,
      'limit': 100,
      'offset': 0,
    });
  }

  List<Map<String, dynamic>> get _rows {
    final d = _controller.data;
    if (d is List) return asRows(d);
    if (d is Map) {
      for (final key in const [
        'items',
        'data',
        'employees',
        'rows',
        'preview'
      ]) {
        final v = d[key];
        if (v is List) return asRows(v);
      }
    }
    return const [];
  }

  double get _netTotal {
    var sum = 0.0;
    for (final r in _rows) {
      sum += numOf(r, ['net_salary', 'net_pay', 'base_salary_for_period']);
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Scaffold(
      body: Column(
        children: [
          AppPageHeader(
            title: 'Payroll',
            actions: [
              AppExportButton(onExport: _export),
              const SizedBox(width: 4),
            ],
          ),
          AppSyncStatusBar(
            status: _controller.status,
            updatedAt: _controller.lastUpdated,
            label: _index == 0 ? 'Payroll preview' : 'Salary slips',
          ),
          AppOfflineSyncBar(engine: services.sync),
          Expanded(
            child: RefreshIndicator(
              color: context.c.brand,
              onRefresh: () => _controller.load(force: true),
              child: _body(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_controller.phase == LoadPhase.failed && _controller.data == null) {
      return AppErrorState(
        message: _controller.error,
        onRetry: () => _controller.load(force: true),
      );
    }
    if (_controller.isLoading && _controller.data == null) {
      return const AppSkeletonList();
    }
    final rows = _rows;
    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        _periodBar(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: AppStatCard(
            label: _index == 0 ? 'Net payroll' : 'Slips',
            value: _index == 0 ? Fmt.money(_netTotal) : Fmt.count(rows.length),
            icon: Icons.account_balance_wallet_outlined,
            caption: Fmt.monthYear(DateTime(_year, _month)),
          ),
        ),
        const SizedBox(height: 8),
        if (_index == 0) _runButton(),
        if (rows.isEmpty)
          AppEmptyState(
            title: _index == 0 ? 'Nothing to run' : 'No slips',
            message: _index == 0
                ? 'The preview is empty for this month.'
                : 'Generate slips to see them here.',
            icon: Icons.receipt_long_outlined,
          )
        else
          AppDataTable<Map<String, dynamic>>(
            rows: rows,
            onRowTap: (r) => _open(r),
            emptyTitle: 'No slips',
            columns: _index == 0 ? _previewColumns : _slipColumns,
            rowLeading: (context, r) => _index == 1
                ? AppBadge(
                    Fmt.humanise(str(r, ['status'], 'DRAFT')),
                    tone: slipStatusTone(str(r, ['status'])),
                    compact: true,
                  )
                : AppAvatar(name: employeeName(r), size: 30),
            rowTrailing: (context, r) => _index == 0
                ? (str(r, ['existing_slip_id']).isEmpty
                    ? const SizedBox.shrink()
                    : const AppBadge('Slipped',
                        tone: AppTone.info, compact: true))
                : _slipActions(r),
          ),
      ],
    );
  }

  List<AppDataColumn<Map<String, dynamic>>> get _previewColumns => [
        AppDataColumn(label: 'Employee', value: (r) => employeeName(r)),
        AppDataColumn(
          label: 'Method',
          value: (r) => Fmt.humanise(
              str(r, ['calculation_method', 'salary_type'], 'MONTHLY')),
        ),
        AppDataColumn(
          label: 'Base',
          value: (r) => Fmt.money(numOf(r, ['base_salary_for_period'])),
        ),
        AppDataColumn(
          label: 'Overtime',
          value: (r) => '${Fmt.qty(numOf(r, ['overtime_hours']))} hrs',
        ),
        AppDataColumn(
          label: 'Net',
          value: (r) => Fmt.money(numOf(r, ['net_salary', 'net_pay'])),
        ),
      ];

  List<AppDataColumn<Map<String, dynamic>>> get _slipColumns => [
        AppDataColumn(
            label: 'Slip', value: (r) => str(r, ['slip_number'], '—')),
        AppDataColumn(label: 'Employee', value: (r) => employeeName(r)),
        AppDataColumn(
          label: 'Period',
          value: (r) => '${Fmt.dateShort(pick(r, ['period_start']))} → '
              '${Fmt.dateShort(pick(r, ['period_end']))}',
        ),
        AppDataColumn(
          label: 'Earnings',
          value: (r) => Fmt.money(numOf(r, ['total_earnings'])),
        ),
        AppDataColumn(
          label: 'Deductions',
          value: (r) => Fmt.money(numOf(r, ['total_deductions'])),
        ),
        AppDataColumn(
          label: 'Net',
          value: (r) => Fmt.money(numOf(r, ['net_salary'])),
        ),
      ];

  Widget _periodBar() => Container(
        color: context.c.surface,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: AppNumberInput(
                    controller: TextEditingController(text: '$_year'),
                    label: 'Year',
                    allowDecimal: false,
                    onChanged: (v) {
                      final y = int.tryParse(v);
                      if (y == null || y < 2000) return;
                      setState(() => _year = y);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppNumberInput(
                    controller: TextEditingController(text: '$_month'),
                    label: 'Month',
                    suffix: Fmt.humanise('$_month'),
                    allowDecimal: false,
                    onChanged: (v) {
                      final m = int.tryParse(v);
                      if (m == null || m < 1 || m > 12) return;
                      setState(() => _month = m);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                if (_index == 1)
                  Expanded(
                    child: AppSearchableSelect<String>(
                      value: _statusFilter,
                      searchable: false,
                      clearable: false,
                      options: [
                        const AppSelectOption(value: 'ALL', label: 'All'),
                        for (final s in const [
                          'DRAFT',
                          'FINALIZED',
                          'PAID',
                          'CANCELLED',
                        ])
                          AppSelectOption(value: s, label: Fmt.humanise(s)),
                      ],
                      onChanged: (v) {
                        setState(() => _statusFilter = v ?? 'ALL');
                        _load();
                      },
                    ),
                  )
                else
                  AppButton(
                    label: 'Load',
                    variant: AppButtonVariant.secondary,
                    onPressed: _load,
                  ),
              ],
            ),
          ],
        ),
      );

  Widget _runButton() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: AppNotice(
          title: 'Run payroll',
          message: 'Generates a draft slip for every employee in this month. '
              'Slips already generated are skipped.',
          tone: AppTone.info,
          action: AppButton(
            label: 'Run',
            variant: AppButtonVariant.primary,
            size: AppButtonSize.sm,
            loading: _busy,
            onPressed: _busy ? null : _run,
          ),
        ),
      );

  Future<void> _run() async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Run payroll for ${Fmt.monthYear(DateTime(_year, _month))}?',
      message: 'A draft slip is created for every employee on the payroll.',
      confirmLabel: 'Run',
    );
    if (!confirm || !mounted) return;
    final services = AppScope.read(context);
    setState(() => _busy = true);
    final ok = await runMgmtWrite(
      context,
      () => services.api.post(mgmt, '/api/salary/payroll-run',
          body: {'year': _year, 'month': _month}),
      success: 'Payroll run complete',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      setState(() => _index = 1);
      _tabs.index = 1;
      _load();
    }
  }

  Widget _slipActions(Map<String, dynamic> row) {
    final status = str(row, ['status'], 'DRAFT').toUpperCase();
    if (boolOf(row, ['paid']) || status == 'PAID') {
      return AppBadge('Paid', tone: AppTone.success, compact: true);
    }
    if (status == 'DRAFT') {
      return AppButton.icon(
        icon: Icons.lock_outline,
        tooltip: 'Finalize',
        size: AppButtonSize.iconSm,
        variant: AppButtonVariant.ghost,
        onPressed: () => _act(row, 'finalize', 'Slip finalized'),
      );
    }
    if (status == 'FINALIZED') {
      return AppButton.icon(
        icon: Icons.payments_outlined,
        tooltip: 'Record payment',
        size: AppButtonSize.iconSm,
        variant: AppButtonVariant.ghost,
        onPressed: () => _pay(row),
      );
    }
    return const SizedBox.shrink();
  }

  Future<void> _act(
      Map<String, dynamic> row, String action, String success) async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: action == 'finalize' ? 'Finalize this slip?' : 'Cancel this slip?',
      message: action == 'finalize'
          ? 'The slip locks and can be paid.'
          : 'The slip is voided and pay stops.',
      confirmLabel: Fmt.humanise(action),
      destructive: action != 'finalize',
    );
    if (!confirm || !mounted) return;
    final services = AppScope.read(context);
    final id = str(row, ['id']);
    final ok = await runMgmtWrite(
      context,
      () => services.api.post(mgmt, '/api/salary/slips/$id/$action'),
      success: success,
    );
    if (ok) _load();
  }

  Future<void> _pay(Map<String, dynamic> row) async {
    final amount = numOf(row, ['net_salary'], numOf(row, ['total_earnings']));
    final controller = TextEditingController(text: '$amount');
    final confirmed = await AppDialog.show<bool>(
      context,
      title: 'Record payment',
      body: AppMoneyInput(
        controller: controller,
        label: 'Amount paid',
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: 'Record',
          variant: AppButtonVariant.primary,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
    controller.dispose();
    if (confirmed != true || !mounted) return;
    final paid = double.tryParse(controller.text.trim());
    if (paid == null) {
      AppToast.error(context, 'Enter a valid amount');
      return;
    }
    final services = AppScope.read(context);
    final ok = await runMgmtWrite(
      context,
      () => services.api.post(mgmt, '/api/salary/slips/${row['id']}/pay',
          query: {'amount': paid}),
      success: 'Payment recorded',
    );
    if (ok) _load();
  }

  Future<void> _open(Map<String, dynamic> row) async {
    if (_index == 0) {
      final id = str(row, ['employee_id', 'id']);
      if (id.isEmpty) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EmployeeDetailPage(employeeId: id),
        ),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(str(row, ['slip_number'], 'Slip'),
                style: context.texts.titleMedium),
            const SizedBox(height: 4),
            Text(employeeName(row), style: context.texts.bodySmall),
            const SizedBox(height: 14),
            for (final line in [
              (
                'Period',
                '${Fmt.date(pick(row, ['period_start']))} → '
                    '${Fmt.date(pick(row, ['period_end']))}'
              ),
              ('Earnings', Fmt.money(numOf(row, ['total_earnings']))),
              ('Deductions', Fmt.money(numOf(row, ['total_deductions']))),
              ('Net', Fmt.money(numOf(row, ['net_salary']))),
              ('Paid', Fmt.money(numOf(row, ['amount_paid']))),
              ('Status', Fmt.humanise(str(row, ['status'], 'DRAFT'))),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(
                        line.$1,
                        style: context.texts.bodySmall
                            ?.copyWith(color: context.c.fgMuted),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        line.$2,
                        textAlign: TextAlign.end,
                        style: context.texts.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            AppButton(
              label: 'Close',
              variant: AppButtonVariant.secondary,
              block: true,
              onPressed: () => Navigator.of(sheetContext).pop(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _export() async {
    final rows = _rows;
    if (rows.isEmpty) {
      AppToast.warning(context, 'Nothing to export');
      return;
    }
    final buffer = StringBuffer('slip,employee,period_start,period_end,'
        'earnings,deductions,net,status\n');
    for (final r in rows) {
      buffer.writeln(
        '${str(r, ['slip_number'])},${employeeName(r)},'
        '${Fmt.isoDate(pick(r, ['period_start']))},'
        '${Fmt.isoDate(pick(r, ['period_end']))},'
        '${numOf(r, ['total_earnings'])},${numOf(r, ['total_deductions'])},'
        '${numOf(r, ['net_salary'])},${str(r, ['status'])}',
      );
    }
    // The management API has no export route, so the sheet goes to the clipboard.
    await copyExport(context, buffer.toString(), 'Payroll CSV');
  }
}
