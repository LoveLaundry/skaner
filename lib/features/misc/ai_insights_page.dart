import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../config/api_config.dart';
import '../../../core/utils/formatting.dart';
import '../../../core/utils/idempotency.dart';
import '../../../data/resource_controller.dart';
import '../../../state/app_scope.dart';
import '../../../ui/kit/feedback.dart';
import '../../../ui/kit/primitives.dart';
import '../../../ui/theme.dart';
import 'app_settings_store.dart';

/// Port of `features/ai/pages/ai-insights-page.tsx`.
///
/// The Love AI service is not a normal JSON API: every request is signed and
/// every response carries a hash of its own payload. [LoveAiClient] is the Dart
/// twin of `features/ai/api/ai-api.ts` — it signs with the key from Settings and
/// refuses to hand the UI a payload whose `data_hash` does not match.
class AiInsightsPage extends StatefulWidget {
  const AiInsightsPage({super.key});

  @override
  State<AiInsightsPage> createState() => _AiInsightsPageState();
}

class _AiInsightsPageState extends State<AiInsightsPage> {
  static const _monthOptions = [3, 6, 12, 24];

  int _months = 12;

  late final LoveAiClient _ai;
  late final ResourceController<Map<String, dynamic>> _insights;
  late final ResourceController<Map<String, dynamic>> _revenue;
  late final ResourceController<Map<String, dynamic>> _expenses;
  late final ResourceController<Map<String, dynamic>> _salary;
  late final ResourceController<Map<String, dynamic>> _risk;

  @override
  void initState() {
    super.initState();
    _ai = LoveAiClient(key: AppSettingsStore.aiKey, baseUrl: ApiConfig.aiBase);
    final cache = AppScope.read(context).cache;
    _insights = ResourceController<Map<String, dynamic>>(
      key: 'ai.insights',
      cache: cache,
      fetcher: () => _ai.dashboard(_months),
    )..addListener(_onChanged);
    _revenue = ResourceController<Map<String, dynamic>>(
      key: 'ai.revenue',
      cache: cache,
      fetcher: () => _ai.revenue(_months),
    )..addListener(_onChanged);
    _expenses = ResourceController<Map<String, dynamic>>(
      key: 'ai.expenses',
      cache: cache,
      fetcher: () => _ai.expenses(_months),
    )..addListener(_onChanged);
    _salary = ResourceController<Map<String, dynamic>>(
      key: 'ai.salary',
      cache: cache,
      fetcher: () => _ai.salary(_months),
    )..addListener(_onChanged);
    _risk = ResourceController<Map<String, dynamic>>(
      key: 'ai.risk',
      cache: cache,
      fetcher: _ai.payrollRisk,
    )..addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final c in [_insights, _revenue, _expenses, _salary, _risk]) {
      c.removeListener(_onChanged);
      c.dispose();
    }
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    await _insights.load(force: true);
    if (!mounted) return;
    await Future.wait([
      _revenue.load(force: true),
      _expenses.load(force: true),
      _salary.load(force: true),
      _risk.load(force: true),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    final d = _insights.data ?? const {};
    final loading = (_insights.isLoading && !_insights.hasData) ||
        (_revenue.isLoading && !_revenue.hasData);
    final failed = _insights.phase == LoadPhase.failed && !_insights.hasData;

    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: c.surface,
            border: Border(bottom: BorderSide(color: c.line)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [c.brand, c.info],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: Icon(Icons.psychology_outlined, size: 22, color: c.surface),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AI Insights & Forecasts', style: t.titleLarge),
                    const SizedBox(height: 2),
                    Text(
                      'Secure analytics from the Love AI service — signed requests, hashed responses',
                      style: t.bodySmall?.copyWith(color: c.fgMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
              children: [
                Row(
                  children: [
                    if (boolOf(d, ['verified']))
                      const Expanded(
                        child: AppBadge('Response verified',
                            tone: AppTone.success, icon: Icons.verified_user_outlined),
                      )
                    else
                      const Spacer(),
                    for (final m in _monthOptions) ...[
                      const SizedBox(width: 6),
                      AppFilterChip(
                        label: '$m mo',
                        selected: _months == m,
                        onTap: () {
                          setState(() => _months = m);
                          _load();
                        },
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Center(child: AppLoader()),
                  )
                else if (failed)
                  AppErrorState(
                    title: 'Could not reach the AI service',
                    message: 'Check that the AI service URL and API key in '
                        'Settings are configured correctly.${_insights.error == null ? '' : '\n$_insights.error'}',
                    onRetry: _load,
                  )
                else ...[
                  _statGrid(d),
                  const SizedBox(height: 16),
                  _forecastCard(
                      'Revenue Forecast', _block(d, 'revenue'), c.success),
                  const SizedBox(height: 14),
                  _forecastCard(
                      'Expenses Forecast', _block(d, 'expenses'), c.danger),
                  const SizedBox(height: 14),
                  _forecastCard(
                      'Payroll Forecast', _block(d, 'payroll'), c.info),
                  const SizedBox(height: 14),
                  _netProfitCard(d),
                  const SizedBox(height: 14),
                  _riskCard(),
                  const SizedBox(height: 14),
                  _topCustomersCard(),
                  const SizedBox(height: 14),
                  _topCategoriesCard(),
                  const SizedBox(height: 14),
                  _topEmployeesCard(),
                  const SizedBox(height: 14),
                  _momentumCard(d),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Sections ───────────────────────────────────────────────────────────────

  Widget _statGrid(Map<String, dynamic> d) {
    final c = context.c;
    final revenueGrowth = _growth(d, 'revenue');
    final expenseGrowth = _growth(d, 'expenses');
    final period = _mapOrNull(d, 'period');
    final net = numOf(d, const ['avg_monthly_net']);

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.9,
      children: [
        _stat(
          'Total Revenue',
          numOf(d, const ['total_revenue']),
          period == null
              ? 'Last $_months months'
              : '${str(period, const ['start'])} → ${str(period, const ['end'])}',
          Icons.payments_outlined,
          c.success,
          trend: revenueGrowth,
        ),
        _stat(
          'Total Expenses',
          numOf(d, const ['total_expenses']),
          'Last $_months months',
          Icons.receipt_long_outlined,
          c.danger,
          trend: expenseGrowth,
        ),
        _stat(
          'Total Payroll',
          numOf(d, const ['total_payroll']),
          'Net paid',
          Icons.account_balance_outlined,
          c.info,
        ),
        _stat(
          'Avg Monthly Net',
          net,
          'Revenue − Expenses',
          Icons.wallet_outlined,
          net >= 0 ? c.success : c.danger,
        ),
      ],
    );
  }

  Widget _stat(
    String title,
    double value,
    String sub,
    IconData icon,
    Color color, {
    double? trend,
  }) {
    final c = context.c;
    final t = context.texts;
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: t.labelSmall?.copyWith(color: c.fgMuted),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text('Rs. ${Fmt.compact(value)}', style: t.titleLarge),
          ),
          Row(
            children: [
              if (trend != null) ...[
                Icon(
                  trend >= 0
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  size: 12,
                  color: trend >= 0 ? c.success : c.danger,
                ),
                const SizedBox(width: 3),
              ],
              Expanded(
                child: Text(sub,
                    style: t.labelSmall?.copyWith(color: c.fgFaint),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// One history line plus the forecast tail the service projects, drawn the way
  /// the React card does: solid history, dashed forecast.
  Widget _forecastCard(String title, Map<String, dynamic> block, Color color) {
    final c = context.c;
    final t = context.texts;
    final series = asRows(pick(block, const ['series']));
    final forecast = _mapOrNull(block, 'forecast') ?? const <String, dynamic>{};
    final values = _numberList(pick(forecast, const ['forecast']));
    final growth = numOf(forecast, const ['growth_pct']);

    if (series.isEmpty) {
      return _card(title, Icons.auto_graph_rounded, const _EmptyNote('No series data'));
    }

    final history = series.map((s) => numOf(s, const ['value'])).toList();
    final spots = <FlSpot>[];
    final forecastSpots = <FlSpot>[];
    for (var i = 0; i < history.length; i++) {
      spots.add(FlSpot(i.toDouble(), history[i]));
    }
    // The forecast occupies the trailing slots, overlapping the last history
    // point so the two lines join instead of starting in mid-air.
    final offset = history.length - values.length;
    for (var i = 0; i < values.length; i++) {
      final x = (offset + i).toDouble();
      if (i == 0 && offset > 0) {
        forecastSpots.add(FlSpot(x - 1, history[offset - 1]));
      }
      forecastSpots.add(FlSpot(x, values[i]));
    }

    return _card(
      title,
      Icons.auto_graph_rounded,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppBadge(
                '${growth.abs().toStringAsFixed(1)}% / mo',
                tone: growth >= 0 ? AppTone.success : AppTone.danger,
                icon: growth >= 0
                    ? Icons.trending_up_rounded
                    : Icons.trending_down_rounded,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                      color: c.line, strokeWidth: 1, dashArray: [3, 3]),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 52,
                      getTitlesWidget: (value, meta) => Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text(
                          'Rs. ${Fmt.compact(value)}',
                          style: t.labelSmall?.copyWith(color: c.fgMuted),
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval:
                          (series.length / 5).ceilToDouble().clamp(1, 9999),
                      getTitlesWidget: (value, meta) {
                        final i = value.round();
                        if (i < 0 || i >= series.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            str(series[i], const ['month']),
                            style: t.labelSmall?.copyWith(color: c.fgMuted),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => c.fg,
                    getTooltipItems: (touched) => touched.map((s) {
                      return LineTooltipItem(
                        'Rs. ${s.y.toStringAsFixed(0)}',
                        TextStyle(color: c.surface, fontSize: 11),
                      );
                    }).toList(),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: color,
                    barWidth: 2.5,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: color.withValues(alpha: 0.12),
                    ),
                  ),
                  LineChartBarData(
                    spots: forecastSpots,
                    isCurved: true,
                    color: c.fg3,
                    barWidth: 2,
                    dashArray: [5, 4],
                    dotData: const FlDotData(show: false),
                  ),
                ],
              ),
            ),
          ),
          if (values.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Projected next ${values.length} months: '
              '${values.map((v) => 'Rs. ${v.toStringAsFixed(0)}').join(' · ')}',
              style: t.labelSmall?.copyWith(color: c.fgFaint),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              _legend(c, color, 'History'),
              const SizedBox(width: 14),
              _legend(c, c.fg3, 'Forecast'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legend(AppColors c, Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 14, height: 2.5, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: context.texts.labelSmall?.copyWith(color: c.fgMuted)),
        ],
      );

  Widget _netProfitCard(Map<String, dynamic> d) {
    final c = context.c;
    final t = context.texts;
    final history = _numberList(pick(d, const ['net_profit']));
    final series = asRows(pick(_block(d, 'revenue'), const ['series']));

    if (history.isEmpty) {
      return _card('Net Profit View', Icons.show_chart_rounded,
          const _EmptyNote('No net profit data'));
    }

    return _card(
      'Net Profit View',
      Icons.show_chart_rounded,
      SizedBox(
        height: 220,
        child: LineChart(
          LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) => FlLine(
                  color: c.line, strokeWidth: 1, dashArray: [3, 3]),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 52,
                  getTitlesWidget: (value, meta) => Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      'Rs. ${Fmt.compact(value)}',
                      style: t.labelSmall?.copyWith(color: c.fgMuted),
                    ),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 22,
                  interval: (series.length / 5).ceilToDouble().clamp(1, 9999),
                  getTitlesWidget: (value, meta) {
                    final i = value.round();
                    if (i < 0 || i >= series.length) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        i < series.length ? str(series[i], const ['month']) : '',
                        style: t.labelSmall?.copyWith(color: c.fgMuted),
                      ),
                    );
                  },
                ),
              ),
            ),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => c.fg,
                getTooltipItems: (touched) => touched.map((s) {
                  return LineTooltipItem(
                    'Rs. ${s.y.toStringAsFixed(0)}',
                    TextStyle(color: c.surface, fontSize: 11),
                  );
                }).toList(),
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: [
                  for (var i = 0; i < history.length; i++)
                    FlSpot(i.toDouble(), history[i]),
                ],
                isCurved: true,
                color: c.info,
                barWidth: 2.5,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: c.info.withValues(alpha: 0.12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _riskCard() {
    final c = context.c;
    final t = context.texts;
    final data = _risk.data ?? const {};
    final rows = asRows(pick(data, const ['employees_at_risk']));
    return _card(
      'Payroll Risk',
      Icons.auto_awesome_outlined,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (rows.isEmpty)
            Text('No outstanding advances. All clear!',
                style: t.bodySmall?.copyWith(color: c.fgMuted))
          else
            for (final e in rows) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(str(e, const ['employee_name'], '—'),
                        style: t.bodySmall?.copyWith(color: c.fg),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  Text('Rs. ${Fmt.money(numOf(e, const ['outstanding']))}',
                      style: t.labelSmall?.copyWith(color: c.danger)),
                  const SizedBox(width: 6),
                  AppBadge('${intOf(e, const ['count'])}×',
                      tone: AppTone.danger, compact: true),
                ],
              ),
              const SizedBox(height: 8),
            ],
          const Divider(height: 16),
          Row(
            children: [
              Text('Total outstanding',
                  style: t.labelSmall?.copyWith(color: c.fgMuted)),
              const Spacer(),
              Text(
                'Rs. ${Fmt.money(numOf(data, const ['total_outstanding_advances']))}',
                style: t.labelLarge?.copyWith(color: c.fg),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _topCustomersCard() {
    final rows = asRows(pick(_revenue.data ?? const {}, const ['top_customers']));
    return _ranked('Top Customers', Icons.trending_up_rounded, rows, 'customer_name',
        emptyMessage: 'No transaction data yet');
  }

  Widget _topCategoriesCard() {
    final rows = asRows(pick(_expenses.data ?? const {}, const ['top_categories']));
    return _ranked('Top Expense Categories', Icons.receipt_long_outlined, rows,
        'category',
        emptyMessage: 'No expenses yet');
  }

  Widget _topEmployeesCard() {
    final rows = asRows(pick(_salary.data ?? const {}, const ['top_employees']));
    return _ranked('Top Employees by Payroll', Icons.account_balance_outlined, rows,
        'employee_name',
        emptyMessage: 'No salary slips yet');
  }

  Widget _ranked(
    String title,
    IconData icon,
    List<Map<String, dynamic>> rows,
    String nameKey, {
    required String emptyMessage,
  }) {
    final c = context.c;
    final t = context.texts;
    return _card(
      title,
      icon,
      rows.isEmpty
          ? _EmptyNote(emptyMessage)
          : Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '#${i + 1} ${str(rows[i], [nameKey], '—')}',
                          style: t.bodySmall?.copyWith(color: c.fg),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        'Rs. ${Fmt.money(numOf(rows[i], const ['amount', 'total']))}',
                        style: t.labelLarge?.copyWith(color: c.fg),
                      ),
                    ],
                  ),
                  if (i != rows.length - 1) const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }

  Widget _momentumCard(Map<String, dynamic> d) {
    final c = context.c;
    final t = context.texts;
    final revenue = _growth(d, 'revenue');
    final expenses = _growth(d, 'expenses');
    final payroll = _growth(d, 'payroll');
    // Rising revenue and falling expenses/payroll are the healthy directions.
    final tiles = <(String, double, bool)>[
      ('Revenue', revenue, revenue >= 0),
      ('Expenses', expenses, expenses <= 0),
      ('Payroll', payroll, payroll <= 0),
    ];

    return _card(
      'Quick Trend Analysis',
      Icons.auto_awesome_outlined,
      Row(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: tiles[i].$3 ? c.successSoft : c.dangerSoft,
                  borderRadius: BorderRadius.circular(Radii.sm),
                  border: Border.all(
                      color: tiles[i].$3 ? c.successBorder : c.dangerBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${tiles[i].$1} momentum',
                        style: t.labelSmall?.copyWith(color: c.fgMuted)),
                    const SizedBox(height: 3),
                    Text(
                      '${tiles[i].$2.abs().toStringAsFixed(1)}%/mo',
                      style: t.titleMedium?.copyWith(
                          color: tiles[i].$3 ? c.success : c.danger),
                    ),
                    Text(
                      tiles[i].$2 >= 0 ? 'Rising' : 'Falling',
                      style: t.labelSmall?.copyWith(color: c.fgFaint),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _card(String title, IconData icon, Widget child) {
    final c = context.c;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: c.fgFaint),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: context.texts.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

}

/// A forecast block (`revenue`, `expenses`, `payroll`) is an object, not a list.
Map<String, dynamic> _block(Map<String, dynamic> source, String key) {
  final v = source[key];
  return v is Map ? Map<String, dynamic>.from(v) : const {};
}

/// `growth_pct` from a forecast block.
double _growth(Map<String, dynamic> source, String key) =>
    numOf(_mapOrNull(_block(source, key), 'forecast') ?? const <String, dynamic>{},
        const ['growth_pct']);

Map<String, dynamic>? _mapOrNull(Map<String, dynamic> source, String key) {
  final v = source[key];
  return v is Map ? Map<String, dynamic>.from(v) : null;
}

/// A series the service sends as bare numbers rather than objects.
List<double> _numberList(Object? raw) {
  if (raw is! List) return const [];
  return raw.map((v) => v is num ? v.toDouble() : asDouble(v)).toList();
}

/// Placeholder row inside a card whose data has not arrived.
class _EmptyNote extends StatelessWidget {
  const _EmptyNote(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: context.texts.bodySmall?.copyWith(color: context.c.fgMuted),
        ),
      );
}

/// Dart twin of `features/ai/api/ai-api.ts`.
///
/// Signs every request with the four `X-` headers the service expects and
/// verifies `data_hash` before returning the payload. A mismatch is a hard
/// failure: a tampered or truncated body is never shown to the operator.
class LoveAiClient {
  LoveAiClient({required this.key, required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  final String key;
  final String baseUrl;
  final http.Client _client;

  static const _timeout = Duration(seconds: 30);

  Map<String, String> _headers(String method, String path, String body) {
    final timestamp =
        (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final bodyHash = sha256Hex(body);
    final canonical = [method.toUpperCase(), path, timestamp, bodyHash].join('\n');
    return {
      'X-API-Key': key,
      'X-Timestamp': timestamp,
      'X-Body-Hash': bodyHash,
      'X-Signature': hmacSha256Hex(key, canonical),
      'Content-Type': 'application/json',
    };
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    var base = baseUrl;
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  /// Returns the verified `data` object of the envelope.
  Future<Map<String, dynamic>> _get(String path, {Map<String, String>? query}) async {
    final signedPath = query == null || query.isEmpty
        ? path
        : '$path?${Uri(path: path, queryParameters: query).query.split('?').last}';
    final response = await _client
        .get(_uri(path, query), headers: _headers('GET', signedPath, ''))
        .timeout(_timeout);
    return _verify(response, path);
  }

  Map<String, dynamic> _verify(http.Response response, String path) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'AI service returned ${response.statusCode}';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          final detail = decoded['detail'] ?? decoded['message'];
          if (detail != null) message = detail.toString();
        }
      } catch (_) {
        // A non-JSON error body keeps the status-code message.
      }
      throw AiException(message, path: path, statusCode: response.statusCode);
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw AiException('Unexpected AI response shape', path: path);
    }
    final envelope = Map<String, dynamic>.from(decoded);
    final data = envelope['data'];
    final hash = envelope['data_hash'];
    if (data is! Map) {
      throw AiException('AI response carried no data object', path: path);
    }
    if (hash is String && hash.isNotEmpty) {
      final actual = sha256Hex(canonicalJson(data));
      if (actual != hash) {
        throw AiException(
          'AI response integrity check failed — data hash mismatch',
          path: path,
        );
      }
    }
    return {
      ...Map<String, dynamic>.from(data),
      if (hash != null) 'verified': true,
      if (envelope['source'] != null) 'source': envelope['source'],
    };
  }

  Future<Map<String, dynamic>> dashboard(int months) =>
      _get('/api/ai/insights/dashboard', query: {'months': '$months'});

  Future<Map<String, dynamic>> revenue(int months) =>
      _get('/api/ai/insights/revenue', query: {'months': '$months'});

  Future<Map<String, dynamic>> expenses(int months) =>
      _get('/api/ai/insights/expenses', query: {'months': '$months'});

  Future<Map<String, dynamic>> salary(int months) =>
      _get('/api/ai/insights/salary', query: {'months': '$months'});

  Future<Map<String, dynamic>> payrollRisk() => _get('/api/ai/insights/payroll-risk');

  Future<Map<String, dynamic>> health() => _get('/api/ai/health');
}

/// Raised when the AI service cannot be reached or its payload fails the
/// integrity check.
class AiException implements Exception {
  AiException(this.message, {this.path, this.statusCode});

  final String message;
  final String? path;
  final int? statusCode;

  @override
  String toString() => message;
}
