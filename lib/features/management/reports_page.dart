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

/// Port of `management-reports.tsx`: the four report tabs the web app offers,
/// each backed by `/api/reports/*`.
class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage>
    with SingleTickerProviderStateMixin {
  static const _reports = ['profit-loss', 'daily', 'monthly', 'outstanding'];

  late final TabController _tabs;
  ResourceController<dynamic> _controller = _unused();

  static ResourceController<dynamic> _unused() =>
      throw StateError('controller is replaced in initState');

  int _index = 0;
  late DateTime _from;
  late DateTime _to;
  late DateTime _day;
  late int _year;
  late int _month;

  String get _report => _reports[_index];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _reports.length, vsync: this)
      ..addListener(_onTab);
    final now = Fmt.lktNow();
    _day = now;
    _from = DateTime(now.year, now.month, 1);
    _to = now;
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
        key: 'management.reports.$_report',
        cache: AppScope.read(context).cache,
        fetcher: _fetch,
      )..addListener(_onChanged);

  /// Each report is a different endpoint, so switching tabs swaps in a
  /// controller cached under that report's own key.
  void _load() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    setState(() => _controller = _build());
    _controller.load(force: true);
  }

  void _reload() => _controller.load(force: true);

  Future<dynamic> _fetch() async {
    final s = AppScope.read(context);
    switch (_report) {
      case 'daily':
        return s.api.get(mgmt, '/api/reports/daily',
            query: {'report_date': Fmt.isoDate(_day)});
      case 'monthly':
        return s.api.get(mgmt, '/api/reports/monthly',
            query: {'year': _year, 'month': _month});
      case 'outstanding':
        return s.api.get(mgmt, '/api/reports/outstanding');
      default:
        return s.api.get(mgmt, '/api/reports/profit-loss', query: {
          'start_date': Fmt.isoDate(_from),
          'end_date': Fmt.isoDate(_to),
        });
    }
  }

  Map<String, dynamic> get _map {
    final d = _controller.data;
    return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          AppExportButton(onExport: _export),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppTabs(
              index: _index,
              onChanged: (i) => _tabs.index = i,
              tabs: const [
                AppTabItem('Profit & loss', icon: Icons.trending_up_rounded),
                AppTabItem('Daily', icon: Icons.today_outlined),
                AppTabItem('Monthly', icon: Icons.calendar_month_outlined),
                AppTabItem('Outstanding',
                    icon: Icons.account_balance_wallet_outlined),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          AppSyncStatusBar(
            status: _controller.status,
            updatedAt: _controller.lastUpdated,
            label: _label,
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

  String get _label => switch (_report) {
        'daily' => 'Daily report',
        'monthly' => 'Monthly report',
        'outstanding' => 'Outstanding payments',
        _ => 'Profit & loss',
      };

  Widget _filters() {
    if (_report == 'outstanding') return const SizedBox.shrink();
    return Container(
      color: context.c.surface,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: switch (_report) {
        'daily' => Row(
            children: [
              Expanded(
                child: AppDateField(
                  label: 'Report date',
                  value: _day,
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _day = v);
                    _reload();
                  },
                ),
              ),
            ],
          ),
        'monthly' => Row(
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
              AppButton(
                label: 'Load',
                variant: AppButtonVariant.secondary,
                onPressed: _reload,
              ),
            ],
          ),
        _ => Row(
            children: [
              Expanded(
                child: AppDateField(
                  label: 'From',
                  value: _from,
                  lastDate: _to,
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _from = v);
                    _reload();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppDateField(
                  label: 'To',
                  value: _to,
                  firstDate: _from,
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _to = v);
                    _reload();
                  },
                ),
              ),
            ],
          ),
      },
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
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _filters(),
        Padding(
          padding: const EdgeInsets.all(12),
          child: switch (_report) {
            'outstanding' => _outstanding(),
            'profit-loss' => _profitLoss(),
            _ => _periodSummary(),
          },
        ),
      ],
    );
  }

  Widget _profitLoss() {
    final d = _map;
    final net = numOf(d, ['net_profit']);
    final byCustomer = asRows(d['revenue_by_customer']);
    final byCategory = asRows(d['revenue_by_category']);
    final expenses = asRows(d['expenses_by_category']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 1.5,
          children: [
            AppStatCard(
              compact: true,
              label: 'Total revenue',
              value: Fmt.money(numOf(d, ['total_revenue'])),
              icon: Icons.trending_up_rounded,
            ),
            AppStatCard(
              compact: true,
              label: 'Cost of goods',
              value: Fmt.money(numOf(d, ['total_cogs'])),
              icon: Icons.inventory_2_outlined,
            ),
            AppStatCard(
              compact: true,
              label: 'Gross profit',
              value: Fmt.money(numOf(d, ['gross_profit'])),
              icon: Icons.savings_outlined,
            ),
            AppStatCard(
              compact: true,
              label: 'Net profit',
              value: Fmt.money(net),
              icon: net >= 0
                  ? Icons.thumb_up_outlined
                  : Icons.thumb_down_outlined,
              trend: net >= 0 ? StatTrend.up : StatTrend.down,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (byCustomer.isNotEmpty) _bars('Revenue by customer', byCustomer),
        if (byCategory.isNotEmpty) _bars('Revenue by category', byCategory),
        if (expenses.isNotEmpty) _bars('Expenses by category', expenses),
        if (byCustomer.isEmpty && byCategory.isEmpty && expenses.isEmpty)
          const AppEmptyState(
            title: 'Nothing in this range',
            message: 'No revenue or expense was recorded between these dates.',
            icon: Icons.insert_chart_outlined,
            compact: true,
          ),
      ],
    );
  }

  /// The web app draws these as recharts bars and a pie; on a phone the same
  /// numbers read fine as ranked bars.
  Widget _bars(String title, List<Map<String, dynamic>> rows) {
    final sorted = [...rows]..sort((a, b) =>
        numOf(b, ['value', 'total']).compareTo(numOf(a, ['value', 'total'])));
    final peak = sorted.fold<double>(
      0,
      (m, r) =>
          numOf(r, ['value', 'total']) > m ? numOf(r, ['value', 'total']) : m,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        title: title,
        child: Column(
          children: [
            for (final r in sorted.take(8))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    SizedBox(
                      width: 108,
                      child: Text(
                        str(r, ['name', 'category'], '—'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.bodySmall
                            ?.copyWith(color: context.c.fgMuted),
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(Radii.pill),
                        child: LinearProgressIndicator(
                          value: peak == 0
                              ? 0
                              : numOf(r, ['value', 'total']) / peak,
                          minHeight: 8,
                          backgroundColor: context.c.surface3,
                          valueColor: AlwaysStoppedAnimation(context.c.brand),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 78,
                      child: Text(
                        Fmt.money(numOf(r, ['value', 'total'])),
                        textAlign: TextAlign.end,
                        style: context.texts.labelSmall
                            ?.copyWith(color: context.c.fg2),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _periodSummary() {
    final d = _map;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 1.5,
      children: [
        AppStatCard(
          compact: true,
          label: 'Transactions',
          value: Fmt.count(intOf(d, ['transactions'])),
          icon: Icons.receipt_long_outlined,
        ),
        AppStatCard(
          compact: true,
          label: 'Total quantity',
          value: Fmt.qty(numOf(d, ['total_quantity'])),
          icon: Icons.scale_outlined,
        ),
        AppStatCard(
          compact: true,
          label: 'Revenue',
          value: Fmt.money(numOf(d, ['total_revenue'])),
          icon: Icons.trending_up_rounded,
        ),
        AppStatCard(
          compact: true,
          label: 'Gross profit',
          value: Fmt.money(numOf(d, ['gross_profit'])),
          icon: Icons.savings_outlined,
        ),
      ],
    );
  }

  Widget _outstanding() {
    final rows = asRows(_controller.data);
    if (rows.isEmpty) {
      return const AppEmptyState(
        title: 'No outstanding payments',
        message: 'Every customer is settled up.',
        icon: Icons.verified_outlined,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          str(r, ['customer_name', 'name'], '—'),
                          style: context.texts.titleSmall,
                        ),
                      ),
                      Text(
                        Fmt.money(numOf(r, ['outstanding'])),
                        style: context.texts.titleSmall?.copyWith(
                          color: numOf(r, ['outstanding']) > 0
                              ? context.c.danger
                              : context.c.success,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Billed ${Fmt.money(numOf(r, ['total_billed']))}',
                        style: context.texts.bodySmall
                            ?.copyWith(color: context.c.fgMuted),
                      ),
                      Text(
                        'Paid ${Fmt.money(numOf(r, ['total_paid']))}',
                        style: context.texts.bodySmall
                            ?.copyWith(color: context.c.fgMuted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _export() async {
    final buffer = StringBuffer();
    if (_report == 'outstanding') {
      final rows = asRows(_controller.data);
      if (rows.isEmpty) {
        AppToast.warning(context, 'Nothing to export');
        return;
      }
      buffer.writeln('customer,total_billed,total_paid,outstanding');
      for (final r in rows) {
        buffer.writeln(
          '${str(r, ['customer_name', 'name'])},${numOf(r, ['total_billed'])},'
          '${numOf(r, ['total_paid'])},${numOf(r, ['outstanding'])}',
        );
      }
    } else {
      final d = _map;
      buffer
        ..writeln('metric,value')
        ..writeln('revenue,${numOf(d, ['total_revenue'])}')
        ..writeln('gross_profit,${numOf(d, ['gross_profit'])}')
        ..writeln('transactions,${intOf(d, ['transactions'])}');
    }
    // The management API has no export route, so the figures go to the clipboard.
    await copyExport(context, buffer.toString(), '$_label CSV');
  }
}
