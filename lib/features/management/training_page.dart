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

/// There is no training endpoint in the management API. The nearest real
/// resource is extra-work: a category is a unit of work the company can train
/// and assign to staff, with a rate and unit, so this screen manages those
/// categories and shows how much of each has been assigned.
class TrainingPage extends StatefulWidget {
  const TrainingPage({super.key});

  @override
  State<TrainingPage> createState() => _TrainingPageState();
}

class _TrainingPageState extends State<TrainingPage> {
  late final ResourceController<List<Map<String, dynamic>>> _categories;
  late final ResourceController<List<Map<String, dynamic>>> _records;

  @override
  void initState() {
    super.initState();
    final cache = AppScope.read(context).cache;
    _categories = ResourceController<List<Map<String, dynamic>>>(
      key: 'management.training.categories',
      cache: cache,
      fetcher: () async {
        final s = AppScope.read(context);
        return asRows(await s.api.get(mgmt, '/api/extra-work/categories',
            query: {'is_active': true}));
      },
    );
    _records = ResourceController<List<Map<String, dynamic>>>(
      key: 'management.training.records',
      cache: cache,
      fetcher: () async {
        final s = AppScope.read(context);
        return asRows(await s.api.get(mgmt, '/api/extra-work/records', query: {
          'limit': 100,
          'offset': 0,
        }));
      },
    );
    for (final c in [_categories, _records]) {
      c.addListener(_onChanged);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _categories.load(force: true);
      _records.load(force: true);
    });
  }

  @override
  void dispose() {
    for (final c in [_categories, _records]) {
      c.removeListener(_onChanged);
      c.dispose();
    }
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _reload() {
    _categories.load(force: true);
    _records.load(force: true);
  }

  /// How many assignments each category has picked up.
  Map<String, ({int count, double units, double amount})> get _usage {
    final out = <String, ({int count, double units, double amount})>{};
    for (final r in _records.data ?? const <Map<String, dynamic>>[]) {
      final id = str(r, ['category_id']);
      if (id.isEmpty) continue;
      final prev = out[id] ?? (count: 0, units: 0.0, amount: 0.0);
      out[id] = (
        count: prev.count + 1,
        units: prev.units + numOf(r, ['units']),
        amount: prev.amount + numOf(r, ['amount'], numOf(r, ['rate'])),
      );
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Scaffold(
      body: Column(
        children: [
          AppPageHeader(
            title: 'Training',
            actions: [
              AppExportButton(onExport: _export),
              const SizedBox(width: 4),
            ],
          ),
          AppSyncStatusBar(
            status: _categories.status,
            updatedAt: _categories.lastUpdated,
            label: 'Training',
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
    if (_categories.phase == LoadPhase.failed && _categories.data == null) {
      return AppErrorState(
        message: _categories.error,
        onRetry: () => _categories.load(force: true),
      );
    }
    if (_categories.isLoading && _categories.data == null) {
      return const AppSkeletonList();
    }
    final cats = _categories.data ?? const <Map<String, dynamic>>[];
    final usage = _usage;
    if (cats.isEmpty) {
      return AppEmptyState(
        title: 'No training items',
        message: 'Add the work types staff can be trained on.',
        icon: Icons.school_outlined,
        action: AppButton(
          label: 'Add',
          variant: AppButtonVariant.primary,
          onPressed: () => _edit(),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 92),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: AppNotice(
            message: 'The management API has no training endpoint. These are '
                'the extra-work categories the web app already keeps, with the '
                'assignments made against each one.',
            tone: AppTone.info,
          ),
        ),
        const SizedBox(height: 8),
        for (final c in cats)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: AppCard(
              onTap: () => _edit(c),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          str(c, ['name'], '—'),
                          style: context.texts.titleSmall,
                        ),
                      ),
                      Text(
                        '${Fmt.money(numOf(c, ['rate']))}/${str(c, [
                              'unit'
                            ], 'unit')}',
                        style: context.texts.bodyMedium
                            ?.copyWith(color: context.c.fg2),
                      ),
                    ],
                  ),
                  if (str(c, ['description']).isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      str(c, ['description']),
                      style: context.texts.bodySmall
                          ?.copyWith(color: context.c.fgMuted),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      AppBadge(
                        Fmt.humanise(str(c, ['calculation_method'], 'FIXED')),
                        tone: AppTone.neutral,
                        compact: true,
                      ),
                      AppBadge(
                        '${usage[str(c, ['id'])]?.count ?? 0} assigned',
                        tone: AppTone.brand,
                        compact: true,
                      ),
                      AppBadge(
                        '${Fmt.qty(usage[str(c, ['id'])]?.units ?? 0)} units',
                        tone: AppTone.info,
                        compact: true,
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

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final isEdit = row != null;
    final name = TextEditingController(text: str(row ?? {}, ['name']));
    final rate = TextEditingController(
      text: isEdit ? '${numOf(row, ['rate'])}' : '',
    );
    final unit = TextEditingController(text: str(row ?? {}, ['unit']));
    final description =
        TextEditingController(text: str(row ?? {}, ['description']));
    var method = str(row ?? {}, ['calculation_method'], 'FIXED');
    var error = false;
    StateSetter? inner;

    final saved = await AppDialog.show<bool>(
      context,
      title: isEdit ? 'Edit training item' : 'Add training item',
      body: StatefulBuilder(
        builder: (context, setInner) {
          inner = setInner;
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppTextInput(
                  controller: name,
                  label: 'Name',
                  textCapitalization: TextCapitalization.words,
                  errorText: error && name.text.trim().isEmpty
                      ? 'Name is required'
                      : null,
                ),
                const SizedBox(height: 10),
                AppMoneyInput(
                  controller: rate,
                  label: 'Rate',
                  errorText: error && double.tryParse(rate.text.trim()) == null
                      ? 'Enter a rate'
                      : null,
                ),
                const SizedBox(height: 10),
                AppTextInput(
                  controller: unit,
                  label: 'Unit',
                  hint: 'hours, pieces, day',
                ),
                const SizedBox(height: 10),
                AppSearchableSelect<String>(
                  label: 'Calculation',
                  value: method,
                  searchable: false,
                  clearable: false,
                  options: const [
                    AppSelectOption(
                      value: 'FIXED',
                      label: 'Fixed (rate × units)',
                    ),
                    AppSelectOption(
                      value: 'PER_UNIT',
                      label: 'Per unit',
                    ),
                  ],
                  onChanged: (v) => setInner(() => method = v ?? 'FIXED'),
                ),
                const SizedBox(height: 10),
                AppTextInput(
                  controller: description,
                  label: 'Description',
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
            if (name.text.trim().isEmpty ||
                double.tryParse(rate.text.trim()) == null) {
              inner?.call(() => error = true);
              return;
            }
            Navigator.of(context).pop(true);
          },
        ),
      ],
    );

    for (final c in [name, rate, unit, description]) {
      c.dispose();
    }
    if (saved != true || !mounted) return;

    final services = AppScope.read(context);
    final body = {
      'name': name.text.trim(),
      'rate': double.parse(rate.text),
      'unit': unit.text.trim().isEmpty ? 'unit' : unit.text.trim(),
      'calculation_method': method,
      'description': description.text.trim(),
      'is_active': true,
    };
    final ok = await runMgmtWrite(
      context,
      () => (isEdit
          ? services.api.put(
              mgmt,
              '/api/extra-work/categories/${row['id']}',
              body: body,
            )
          : services.api.post(mgmt, '/api/extra-work/categories', body: body)),
      success: isEdit ? 'Training item updated' : 'Training item added',
    );
    if (ok) _reload();
  }

  Future<void> _export() async {
    final cats = _categories.data ?? const <Map<String, dynamic>>[];
    if (cats.isEmpty) {
      AppToast.warning(context, 'Nothing to export');
      return;
    }
    final usage = _usage;
    final buffer = StringBuffer('item,rate,unit,method,assigned,units\n');
    for (final c in cats) {
      final id = str(c, ['id']);
      buffer.writeln(
        '${str(c, ['name'])},${numOf(c, ['rate'])},${str(c, ['unit'], 'unit')},'
        '${str(c, ['calculation_method'], 'FIXED')},'
        '${usage[id]?.count ?? 0},${usage[id]?.units ?? 0}',
      );
    }
    // The management API has no export route, so the sheet goes to the clipboard.
    await copyExport(context, buffer.toString(), 'Training CSV');
  }
}
