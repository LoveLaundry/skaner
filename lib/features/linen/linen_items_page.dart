import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models/json.dart' as json;
import '../../core/models/linen.dart';
import '../../core/utils/formatting.dart';
import '../../data/resource_controller.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/data.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/inputs.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/kit/shell_parts.dart';
import '../management/_management_shared.dart';
import '_linen_shared.dart';
import 'linen_tracking_detail_page.dart';
import '../../ui/theme.dart';

/// Port of `features/linen/pages/linen-inventory.tsx`.
///
/// Each row is one tagged piece — the linen document — so "items" here means
/// the individual garments rather than the batches they are washed in. The list
/// is server-paged 50 at a time and filtered by the four keys the endpoint
/// accepts, and the export goes to the clipboard because a phone has nowhere to
/// drop a file.
class LinenItemsPage extends StatefulWidget {
  const LinenItemsPage({super.key});

  @override
  State<LinenItemsPage> createState() => _LinenItemsPageState();
}

class _LinenItemsPageState extends State<LinenItemsPage> {
  static const int _perPage = 50;

  final _searchCtrl = TextEditingController();
  late final ResourceController<List<LinenItem>> _controller;

  Timer? _debounce;
  String _search = '';
  String _category = '';
  String _status = '';
  String _condition = '';
  int _page = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _controller = ResourceController(
      key: 'linen-items',
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
    _debounce?.cancel();
    _searchCtrl.dispose();
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<List<LinenItem>> _fetch() async {
    final payload = await AppScope.read(context).api.get(
      linenService,
      LinenApi.list,
      query: {
        if (_search.isNotEmpty) 'search': _search,
        if (_category.isNotEmpty) 'category': _category,
        if (_status.isNotEmpty) 'status': _status,
        if (_condition.isNotEmpty) 'condition': _condition,
        'skip': _page * _perPage,
        'limit': _perPage,
      },
    );
    final list = json.unwrapList(payload);
    _total = list.total;
    return list.items.map(LinenItem.fromJson).toList();
  }

  Future<void> _reload() => _controller.load(force: true);

  void _onSearch(String value) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() {
        _search = value.trim();
        _page = 0;
      });
      _reload();
    });
  }

  bool get _hasFilters =>
      _search.isNotEmpty ||
      _category.isNotEmpty ||
      _status.isNotEmpty ||
      _condition.isNotEmpty;

  List<LinenItem> get _rows => _controller.data ?? const [];

  int get _totalPages => pageCount(_total, _perPage);

  void _setStatus(String value) {
    setState(() {
      _status = _status == value ? '' : value;
      _page = 0;
    });
    _reload();
  }

  void _clearFilters() {
    _searchCtrl.clear();
    setState(() {
      _search = '';
      _category = '';
      _status = '';
      _condition = '';
      _page = 0;
    });
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final c = context.c;
    final rows = _rows;
    final loading = _controller.isLoading && rows.isEmpty;

    return Scaffold(
      body: Column(
        children: [
          AppPageHeader(
            title: 'Linen items',
            actions: [
              AppButton.icon(
                icon: Icons.file_download_outlined,
                tooltip: 'Copy as CSV',
                onPressed: rows.isEmpty ? null : () => _export(rows),
              ),
              AppButton.icon(
                icon: Icons.refresh,
                tooltip: 'Refresh',
                loading: _controller.isLoading,
                onPressed: _reload,
              ),
            ],
          ),
          AppSyncStatusBar(
            status: _controller.status,
            updatedAt: _controller.lastUpdated,
            label: 'Linen items',
          ),
          AppOfflineSyncBar(engine: services.sync),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: AppTextInput(
              controller: _searchCtrl,
              hint: 'Search linen ID, type, client…',
              icon: Icons.search,
              onChanged: _onSearch,
              suffix: _searchCtrl.text.isEmpty
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
          const SizedBox(height: 8),
          _FilterStrip(
            category: _category,
            status: _status,
            condition: _condition,
            onCategory: (v) {
              setState(() {
                _category = v == _category ? '' : v;
                _page = 0;
              });
              _reload();
            },
            onStatus: _setStatus,
            onCondition: (v) {
              setState(() {
                _condition = v == _condition ? '' : v;
                _page = 0;
              });
              _reload();
            },
          ),
          if (_hasFilters)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
              child: Row(
                children: [
                  Text(
                    '${Fmt.count(rows.length)} on this page of '
                    '${Fmt.count(_total)}',
                    style: context.texts.labelSmall?.copyWith(color: c.fgMuted),
                  ),
                  const Spacer(),
                  AppButton(
                    label: 'Reset',
                    variant: AppButtonVariant.ghost,
                    size: AppButtonSize.xs,
                    icon: Icons.filter_alt_off_outlined,
                    onPressed: _clearFilters,
                  ),
                ],
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              color: c.brand,
              onRefresh: _reload,
              child: _controller.phase == LoadPhase.failed && rows.isEmpty
                  ? AppErrorState(message: _controller.error, onRetry: _reload)
                  : loading
                      ? const AppSkeletonList()
                      : rows.isEmpty
                          ? ListView(
                              children: [
                                SizedBox(
                                  height:
                                      MediaQuery.of(context).size.height * 0.4,
                                  child: AppEmptyState(
                                    title: 'No linen found',
                                    message: _hasFilters
                                        ? 'Try adjusting your filters.'
                                        : 'Generate new linen tags to fill the inventory.',
                                    icon: Icons.inventory_2_outlined,
                                    action: _hasFilters
                                        ? AppButton(
                                            label: 'Clear filters',
                                            variant: AppButtonVariant.secondary,
                                            onPressed: _clearFilters,
                                          )
                                        : null,
                                  ),
                                ),
                              ],
                            )
                          : AppDataTable<LinenItem>(
                              columns: const [
                                AppDataColumn<LinenItem>(
                                  label: 'Type',
                                  value: _type,
                                ),
                                AppDataColumn<LinenItem>(
                                  label: 'Client',
                                  value: _client,
                                ),
                                AppDataColumn<LinenItem>(
                                  label: 'Condition',
                                  value: _conditionLabel,
                                ),
                                AppDataColumn<LinenItem>(
                                  label: 'Washes',
                                  value: _washes,
                                ),
                                AppDataColumn<LinenItem>(
                                  label: 'Last scan',
                                  value: _lastScan,
                                ),
                              ],
                              rows: rows,
                              onRowTap: _open,
                              rowLeading: (_, item) => Padding(
                                padding: const EdgeInsets.only(top: 1),
                                child: Icon(
                                  linenStatusIcon(item.status),
                                  size: 18,
                                  color: linenStatusTone(item.status)
                                      .dot(context.c),
                                ),
                              ),
                              rowTrailing: (_, item) => Padding(
                                padding: const EdgeInsets.only(top: 1),
                                child: LinenStatusBadge(status: item.status),
                              ),
                            ),
            ),
          ),
          if (rows.isNotEmpty && _totalPages > 1)
            AppPagination(
              page: _page + 1,
              total: _totalPages,
              onPage: (p) {
                setState(() => _page = p - 1);
                _reload();
              },
            ),
        ],
      ),
    );
  }

  static String _type(LinenItem l) => l.itemType;

  static String _client(LinenItem l) => l.clientName;

  static String _conditionLabel(LinenItem l) => l.conditionLabel;

  static String _washes(LinenItem l) => Fmt.qty(l.washCount);

  static String _lastScan(LinenItem l) => Fmt.date(l.lastScannedDate);

  void _export(List<LinenItem> rows) {
    final header = [
      'Linen ID',
      'Category',
      'Item Type',
      'Client',
      'Status',
      'Condition',
      'Wash Count',
      'Last Scan',
    ];
    final body = [
      for (final l in rows)
        [
          l.linenId,
          l.category,
          l.itemType,
          l.clientName,
          linenStatusValues[l.status] ?? '',
          l.condition,
          '${l.washCount}',
          l.lastScannedDate ?? '',
        ],
    ];
    final csv = [
      header,
      ...body,
    ].map((r) => r.map((cell) => '"$cell"').join(',')).join('\n');
    copyExport(context, csv, 'Linen inventory');
  }

  void _open(LinenItem item) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(
      builder: (_) => LinenTrackingDetailPage(docId: item.id),
    ))
        .then((_) {
      if (mounted) _reload();
    });
  }
}

/// Category, status and condition are separate axes, so each gets its own
/// menu rather than one chip row with eleven statuses crammed into it.
class _FilterStrip extends StatelessWidget {
  const _FilterStrip({
    required this.category,
    required this.status,
    required this.condition,
    required this.onCategory,
    required this.onStatus,
    required this.onCondition,
  });

  final String category;
  final String status;
  final String condition;
  final ValueChanged<String> onCategory;
  final ValueChanged<String> onStatus;
  final ValueChanged<String> onCondition;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          AppMenuButton(
            label:
                _label('Category', category, (v) => LinenCategory.labelOf(v)),
            icon: Icons.category_outlined,
            variant: _variant(category),
            items: [
              for (final c in LinenCategory.all)
                AppMenuItem(
                  label: c.label,
                  onTap: () => onCategory(c.value),
                ),
            ],
          ),
          const SizedBox(width: 8),
          AppMenuButton(
            label: _label('Status', status, (v) {
              final s = linenStatusFrom(v);
              return v.isEmpty ? '' : (linenStatusLabels[s] ?? v);
            }),
            icon: Icons.tune,
            variant: _variant(status),
            items: [
              for (final s in LinenStatus.values)
                AppMenuItem(
                  label: linenStatusLabels[s]!,
                  onTap: () => onStatus(linenStatusValues[s]!),
                ),
            ],
          ),
          const SizedBox(width: 8),
          AppMenuButton(
            label: _label(
                'Condition', condition, (v) => LinenCondition.labelOf(v)),
            icon: Icons.verified_outlined,
            variant: _variant(condition),
            items: [
              for (final c in LinenCondition.all)
                AppMenuItem(label: c.label, onTap: () => onCondition(c.value)),
            ],
          ),
        ],
      ),
    );
  }

  static AppButtonVariant _variant(String value) =>
      value.isEmpty ? AppButtonVariant.secondary : AppButtonVariant.outline;

  static String _label(
    String caption,
    String value,
    String Function(String) resolve,
  ) =>
      value.isEmpty ? caption : '$caption: ${resolve(value)}';
}
