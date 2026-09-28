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

/// Port of `management-expenses.tsx`: dated expense entries filtered by range
/// and category, with the server's own per-category summary above the list.
class ExpensesPage extends StatefulWidget {
  const ExpensesPage({super.key});

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  static const _paymentMethods = [
    'CASH',
    'BANK_TRANSFER',
    'CHEQUE',
    'CARD',
    'ONLINE',
  ];

  late final ResourceController<List<Map<String, dynamic>>> _expenses;
  late final ResourceController<List<Map<String, dynamic>>> _categories;
  late final ResourceController<List<Map<String, dynamic>>> _summary;

  late DateTime _from;
  late DateTime _to;
  String? _categoryId;

  @override
  void initState() {
    super.initState();
    final cache = AppScope.read(context).cache;
    final today = Fmt.lktNow();
    _from = DateTime(today.year, today.month, 1);
    _to = today;

    _expenses = ResourceController<List<Map<String, dynamic>>>(
      key: 'expenses',
      cache: cache,
      fetcher: _fetchExpenses,
    );
    _categories = ResourceController<List<Map<String, dynamic>>>(
      key: 'expenses.categories',
      cache: cache,
      fetcher: () async {
        final s = AppScope.read(context);
        return asRows(await s.api.get(mgmt, '/api/expenses/categories'));
      },
    );
    _summary = ResourceController<List<Map<String, dynamic>>>(
      key: 'expenses.summary',
      cache: cache,
      fetcher: _fetchSummary,
    );
    for (final c in [_expenses, _categories, _summary]) {
      c.addListener(_onChanged);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _categories.load(force: true);
      _reload();
    });
  }

  @override
  void dispose() {
    for (final c in [_expenses, _categories, _summary]) {
      c.removeListener(_onChanged);
      c.dispose();
    }
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Map<String, dynamic> get _range => {
        'start_date': Fmt.isoDate(_from),
        'end_date': Fmt.isoDate(_to),
      };

  Future<List<Map<String, dynamic>>> _fetchExpenses() async {
    final s = AppScope.read(context);
    return asRows(await s.api.get(
      mgmt,
      '/api/expenses',
      query: {
        ..._range,
        if (_categoryId != null) 'category_id': _categoryId!,
        'limit': 100,
        'offset': 0,
      },
    ));
  }

  Future<List<Map<String, dynamic>>> _fetchSummary() async {
    final s = AppScope.read(context);
    final payload =
        await s.api.get(mgmt, '/api/expenses/summary', query: _range);
    return asRows(payload);
  }

  void _reload() {
    _expenses.load(force: true);
    _summary.load(force: true);
  }

  double get _total {
    var sum = 0.0;
    for (final r in _expenses.data ?? const <Map<String, dynamic>>[]) {
      sum += numOf(r, ['amount']);
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Expenses'),
        actions: [
          AppExportButton(onExport: _export),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          AppSyncStatusBar(
            status: _expenses.status,
            updatedAt: _expenses.lastUpdated,
            label: 'Expenses',
          ),
          AppOfflineSyncBar(engine: services.sync),
          Expanded(
            child: RefreshIndicator(
              color: context.c.brand,
              onRefresh: () async => _reload(),
              child: _body(),
            ),
          ),
        ],
      ),
      floatingActionButton: AppButton(
        label: 'Add',
        icon: Icons.add,
        variant: AppButtonVariant.primary,
        onPressed: () => _edit(),
      ),
    );
  }

  Widget _body() {
    if (_expenses.phase == LoadPhase.failed && _expenses.data == null) {
      return AppErrorState(
        message: _expenses.error,
        onRetry: () => _expenses.load(force: true),
      );
    }
    if (_expenses.isLoading && _expenses.data == null) {
      return const AppSkeletonList();
    }
    final rows = _expenses.data ?? const <Map<String, dynamic>>[];
    return ListView(
      padding: const EdgeInsets.only(bottom: 92),
      children: [
        _filters(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1.6,
            children: [
              AppStatCard(
                compact: true,
                label: 'Total',
                value: Fmt.money(_total),
                icon: Icons.receipt_long_outlined,
              ),
              for (final s
                  in (_summary.data ?? const <Map<String, dynamic>>[]).take(3))
                AppStatCard(
                  compact: true,
                  label: str(s, ['category', 'category_name'], 'Other'),
                  value: Fmt.money(numOf(s, ['total', 'amount'])),
                  caption: '${Fmt.count(intOf(s, ['count']))} entries',
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (rows.isEmpty)
          const AppEmptyState(
            title: 'No expenses',
            message: 'Nothing was recorded in this range.',
            icon: Icons.request_quote_outlined,
          )
        else
          AppDataTable<Map<String, dynamic>>(
            rows: rows,
            onRowTap: _edit,
            emptyTitle: 'No expenses',
            columns: [
              AppDataColumn(
                label: 'Date',
                value: (r) => Fmt.date(pick(r, ['date'])),
              ),
              AppDataColumn(
                label: 'Category',
                value: (r) => str(r, ['category_name', 'category'], '—'),
              ),
              AppDataColumn(
                label: 'Description',
                value: (r) => str(r, ['description', 'notes'], '—'),
              ),
              AppDataColumn(
                label: 'Amount',
                value: (r) => Fmt.money(numOf(r, ['amount'])),
              ),
              AppDataColumn(
                label: 'Paid by',
                value: (r) => Fmt.humanise(str(r, ['payment_method'])),
              ),
              AppDataColumn(
                label: 'Reference',
                value: (r) => str(r, ['reference'], '—'),
              ),
            ],
            rowLeading: (context, r) => AppBadge(
              str(r, ['category_name', 'category'], '—'),
              tone: AppTone.warning,
              compact: true,
            ),
            rowTrailing: (context, r) => AppButton.icon(
              icon: Icons.delete_outline,
              tooltip: 'Delete',
              size: AppButtonSize.iconSm,
              variant: AppButtonVariant.ghost,
              onPressed: () => _delete(r),
            ),
          ),
      ],
    );
  }

  Widget _filters() => Container(
        color: context.c.surface,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          children: [
            Row(
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
            const SizedBox(height: 8),
            AppSearchableSelect<String>(
              value: _categoryId ?? '',
              hint: 'All categories',
              clearable: true,
              searchable: false,
              options: [
                for (final c
                    in _categories.data ?? const <Map<String, dynamic>>[])
                  AppSelectOption(
                      value: str(c, ['id']), label: str(c, ['name'])),
              ],
              onChanged: (v) {
                setState(() => _categoryId = v);
                _expenses.load(force: true);
              },
            ),
          ],
        ),
      );

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final isEdit = row != null;
    final amount = TextEditingController(
      text: isEdit ? '${numOf(row, ['amount'])}' : '',
    );
    final description =
        TextEditingController(text: str(row ?? {}, ['description']));
    final reference =
        TextEditingController(text: str(row ?? {}, ['reference']));
    final notes = TextEditingController(text: str(row ?? {}, ['notes']));
    var method = str(row ?? {}, ['payment_method'], 'CASH');
    var category = str(row ?? {}, ['category_id'], _categoryId ?? '');
    var date = dateOf(row ?? {}, ['date']) ?? Fmt.lktNow();
    var error = false;
    StateSetter? inner;

    final saved = await AppDialog.show<bool>(
      context,
      title: isEdit ? 'Edit expense' : 'Add expense',
      body: StatefulBuilder(
        builder: (context, setInner) {
          inner = setInner;
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppDateField(
                  label: 'Date',
                  value: date,
                  onChanged: (v) => setInner(() => date = v ?? date),
                ),
                const SizedBox(height: 10),
                AppSearchableSelect<String>(
                  label: 'Category',
                  value: category,
                  searchable: false,
                  errorText:
                      error && category.isEmpty ? 'Pick a category' : null,
                  options: [
                    for (final c
                        in _categories.data ?? const <Map<String, dynamic>>[])
                      AppSelectOption(
                          value: str(c, ['id']), label: str(c, ['name'])),
                  ],
                  onChanged: (v) => setInner(() {
                    category = v ?? '';
                    error = false;
                  }),
                ),
                const SizedBox(height: 10),
                AppMoneyInput(
                  controller: amount,
                  label: 'Amount',
                  errorText: error && amount.text.trim().isEmpty
                      ? 'Amount is required'
                      : null,
                ),
                const SizedBox(height: 10),
                AppTextInput(
                  controller: description,
                  label: 'Description',
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 10),
                AppSearchableSelect<String>(
                  label: 'Payment method',
                  value: method,
                  searchable: false,
                  clearable: false,
                  options: [
                    for (final m in _paymentMethods)
                      AppSelectOption(value: m, label: Fmt.humanise(m)),
                  ],
                  onChanged: (v) => setInner(() => method = v ?? 'CASH'),
                ),
                const SizedBox(height: 10),
                AppTextInput(controller: reference, label: 'Reference'),
                const SizedBox(height: 10),
                AppTextInput(
                  controller: notes,
                  label: 'Notes',
                  maxLines: 2,
                  minLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ],
            ),
          );
        },
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: isEdit ? 'Save' : 'Add',
          variant: AppButtonVariant.primary,
          onPressed: () {
            if (category.isEmpty ||
                double.tryParse(amount.text.trim()) == null) {
              inner?.call(() => error = true);
              return;
            }
            Navigator.of(context).pop(true);
          },
        ),
      ],
    );

    for (final c in [amount, description, reference, notes]) {
      c.dispose();
    }
    if (saved != true || !mounted) return;

    final services = AppScope.read(context);
    final body = {
      'date': Fmt.isoDate(date),
      'category_id': category,
      'amount': double.parse(amount.text),
      'description': description.text.trim(),
      'payment_method': method,
      if (reference.text.trim().isNotEmpty) 'reference': reference.text.trim(),
      if (notes.text.trim().isNotEmpty) 'notes': notes.text.trim(),
    };
    final ok = await runMgmtWrite(
      context,
      () => (isEdit
          ? services.api.put(mgmt, '/api/expenses/${row['id']}', body: body)
          : services.api.post(mgmt, '/api/expenses', body: body)),
      success: isEdit ? 'Expense updated' : 'Expense added',
    );
    if (ok) _reload();
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: 'Delete expense?',
      message: '${Fmt.money(numOf(row, ['amount']))} on '
          '${Fmt.date(pick(row, ['date']))} will be removed.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirm || !mounted) return;
    final services = AppScope.read(context);
    final ok = await runMgmtWrite(
      context,
      () => services.api.delete(mgmt, '/api/expenses/${row['id']}'),
      success: 'Expense deleted',
    );
    if (ok) _reload();
  }

  Future<void> _export() async {
    final rows = _expenses.data ?? const <Map<String, dynamic>>[];
    if (rows.isEmpty) {
      AppToast.warning(context, 'Nothing to export in this range');
      return;
    }
    final buffer = StringBuffer(
        'date,category,description,amount,payment_method,reference\n');
    for (final r in rows) {
      buffer
        ..write('${Fmt.isoDate(pick(r, ['date']))},')
        ..write('${str(r, ['category_name', 'category'])},')
        ..write('${str(r, ['description'])},')
        ..write('${numOf(r, ['amount'])},')
        ..write('${str(r, ['payment_method'])},')
        ..writeln(str(r, ['reference']));
    }
    // The management API has no export route, so the sheet goes to the clipboard.
    await copyExport(context, buffer.toString(), 'Expenses CSV');
  }
}
