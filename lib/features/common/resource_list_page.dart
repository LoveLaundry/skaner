import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/utils/formatting.dart';
import '../../data/resource_controller.dart';
import '../../data/resource_definition.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/data.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/inputs.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/kit/shell_parts.dart';
import '../../ui/theme.dart';
import 'resource_form_page.dart';

/// One list screen for a whole class of modules.
///
/// It is deliberately generic: the operator sees the same search, filter,
/// refresh, offline and pagination behaviour on every collection, and a module
/// only declares its columns and filters.
class ResourceListPage extends StatefulWidget {
  const ResourceListPage({super.key, required this.definition});

  final ResourceDefinition definition;

  @override
  State<ResourceListPage> createState() => _ResourceListPageState();
}

class _ResourceListPageState extends State<ResourceListPage> {
  final _searchCtrl = TextEditingController();
  late final ResourceController<List<Map<String, dynamic>>> _controller;

  String _search = '';
  final Map<String, String> _filterValues = {};
  int _page = 1;
  int _limit = 25;
  int _total = 0;
  String? _hotel;

  @override
  void initState() {
    super.initState();
    final services = AppScope.of(context);
    _limit = widget.definition.defaultLimit;
    _controller = ResourceController(
      key: widget.definition.cacheKey,
      cache: services.cache,
      fetcher: _fetch,
    );
    _controller.addListener(_onLoaded);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reload();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final hotels = AppScope.of(context).hotels;
    hotels.addListener(_onHotelsChanged);
  }

  @override
  void dispose() {
    AppScope.of(context).hotels.removeListener(_onHotelsChanged);
    _searchCtrl.dispose();
    _controller.removeListener(_onLoaded);
    _controller.dispose();
    super.dispose();
  }

  void _onHotelsChanged() {
    if (!mounted) return;
    final next = AppScope.of(context).hotels.queryParam;
    if (next == _hotel) return;
    _hotel = next;
    _reload();
  }

  void _onLoaded() {
    if (!mounted) return;
    final rows = _controller.data;
    if (rows != null) setState(() {});
  }

  Future<List<Map<String, dynamic>>> _fetch() async {
    final services = AppScope.read(context);
    final def = widget.definition;
    final query = <String, dynamic>{
      ...def.baseQuery(hotel: _hotel, limit: _limit, page: _page),
      for (final e in _filterValues.entries)
        if (e.value.isNotEmpty) e.key: e.value,
      if (_search.isNotEmpty && def.searchParam != null)
        def.searchParam!: _search,
    };
    final payload = await services.api.get(
      def.service,
      def.listPath(),
      query: query,
    );
    final rows = asRows(payload);
    _total = _extractTotal(payload, rows.length);
    return rows;
  }

  int _extractTotal(dynamic payload, int fallback) {
    if (payload is Map) {
      final map = Map<String, dynamic>.from(payload);
      for (final k in const ['total', 'count', 'total_count', 'totalCount']) {
        final v = map[k];
        if (v is num) return v.toInt();
        if (v is String) {
          final n = int.tryParse(v);
          if (n != null) return n;
        }
      }
    }
    return fallback;
  }

  Future<void> _reload({bool resetPage = true}) async {
    if (resetPage) setState(() => _page = 1);
    await _controller.load(force: true);
  }

  List<Map<String, dynamic>> get _rows => _controller.data ?? const [];

  /// Client-side fallback so a module that has no server-side search still
  /// narrows as the operator types.
  List<Map<String, dynamic>> get _visibleRows {
    if (_search.isEmpty) return _rows;
    final def = widget.definition;
    final q = _search.toLowerCase();
    final fields = def.searchFields.isEmpty
        ? [def.titleField, ...def.columns.map((c) => c.label)]
        : def.searchFields;
    return _rows.where((r) {
      for (final f in fields) {
        final v = r[f];
        if (v != null && '$v'.toLowerCase().contains(q)) return true;
      }
      return false;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final def = widget.definition;
    final t = context.texts;
    final canWrite = def.permission == null || services.auth.hasPermission(def.permission!);
    final canRead = def.readPermission == null ||
        services.auth.hasPermission(def.readPermission!);

    if (!canRead) {
      return Scaffold(
        appBar: AppBar(title: Text(def.plural)),
        body: const AppErrorState(
          title: 'Not permitted',
          message: 'You do not have access to this module.',
          icon: Icons.lock_outline,
        ),
      );
    }

    final rows = _visibleRows;
    return Scaffold(
      appBar: AppBar(
        title: Text(def.plural),
        actions: [
          if (def.canCreate && canWrite)
            AppButton.icon(
              icon: Icons.add,
              tooltip: def.createLabel,
              variant: AppButtonVariant.primary,
              onPressed: () => _openForm(null),
            ),
        ],
      ),
      body: Column(
        children: [
          AppSyncStatusBar(
            status: _controller.status,
            updatedAt: _controller.lastUpdated,
            label: def.plural,
          ),
          AppOfflineSyncBar(engine: services.sync),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: AppTextInput(
              controller: _searchCtrl,
              hint: 'Search ${def.plural.toLowerCase()}…',
              icon: Icons.search,
              onChanged: (v) => setState(() {
                _search = v.trim();
                _page = 1;
              }),
              suffix: _search.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _search = '');
                      },
                    ),
            ),
          ),
          if (def.filters.isNotEmpty)
            AppToolbar(
              children: _filterChips(context, def),
            ),
          if (_filterValues.isNotEmpty || _search.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Text('${Fmt.count(rows.length)} shown',
                      style: t.labelSmall
                          ?.copyWith(color: context.c.fgMuted)),
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
                        _filterValues.clear();
                      });
                      _reload();
                    },
                  ),
                ],
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              color: context.c.brand,
              onRefresh: () => _reload(resetPage: false),
              child: _controller.phase == LoadPhase.failed && rows.isEmpty
                  ? AppErrorState(
                      message: _controller.error,
                      onRetry: () => _reload(),
                    )
                  : _controller.isLoading && rows.isEmpty
                      ? const AppSkeletonList()
                      : AppDataTable<Map<String, dynamic>>(
                          rows: rows,
                          loading: _controller.isLoading && rows.isNotEmpty,
                          emptyTitle: def.emptyTitle ?? 'No ${def.plural.toLowerCase()} yet',
                          emptyMessage: def.emptyMessage,
                          emptyIcon: def.icon ?? Icons.inbox_outlined,
                          columns: [
                            AppDataColumn<Map<String, dynamic>>(
                              label: def.titleField,
                              value: (r) => asString(r[def.titleField]),
                              minWidth: 120,
                            ),
                            for (final c in def.columns)
                              AppDataColumn<Map<String, dynamic>>(
                                label: c.label,
                                value: c.value,
                                minWidth: c.minWidth,
                              ),
                          ],
                          onRowTap: (r) => _openDetail(r),
                          rowLeading: (ctx, r) => _toneDot(ctx, def, r) ?? const SizedBox.shrink(),
                        ),
            ),
          ),
          if (_total > _limit)
            AppPagination(
              page: _page,
              total: pageCount(_total, _limit),
              onPage: (p) {
                setState(() => _page = p);
                _reload(resetPage: false);
              },
            ),
        ],
      ),
      floatingActionButton: def.canCreate && canWrite
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(null),
              backgroundColor: context.c.brand,
              foregroundColor: context.c.onBrand,
              icon: const Icon(Icons.add),
              label: Text(def.createLabel),
            )
          : null,
    );
  }

  static Widget? _toneDot(
    BuildContext context,
    ResourceDefinition def,
    Map<String, dynamic> row,
  ) {
    final resolver = def.toneResolver;
    if (resolver == null) return null;
    final tone = resolver(row) ?? AppTone.neutral;
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: tone.dot(context.c), shape: BoxShape.circle),
      ),
    );
  }

  List<Widget> _filterChips(BuildContext context, ResourceDefinition def) {
    final out = <Widget>[];
    for (final f in def.filters) {
      final options = [
        const ResourceSelectOption(value: '', label: 'All'),
        ...f.values,
        ...f.statusValues,
      ];
      final current = _filterValues[f.name] ?? '';
      for (final o in options) {
        out.add(
          AppFilterChip(
            label: o.label,
            selected: current == o.value,
            onTap: () {
              setState(() {
                if (o.value.isEmpty) {
                  _filterValues.remove(f.name);
                } else {
                  _filterValues[f.name] = o.value;
                }
              });
              _reload();
            },
          ),
        );
      }
    }
    return out;
  }

  Future<void> _openForm(Map<String, dynamic>? row) async {
    final services = AppScope.read(context);
    final def = widget.definition;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ResourceFormPage(
          definition: def,
          record: row,
          hotelName: services.hotels.selectedHotel,
        ),
      ),
    );
    if (saved == true) _reload();
  }

  void _openDetail(Map<String, dynamic> row) {
    final services = AppScope.read(context);
    final def = widget.definition;
    final canWrite = def.permission == null || services.auth.hasPermission(def.permission!);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _RecordDetailPage(
          definition: def,
          record: row,
          canWrite: canWrite,
          onChanged: () => _reload(resetPage: false),
        ),
      ),
    );
  }
}

/// Read-only field view plus the row's actions. Complex modules route to their
/// own detail screen instead; this one covers plain collections.
class _RecordDetailPage extends StatefulWidget {
  const _RecordDetailPage({
    required this.definition,
    required this.record,
    required this.canWrite,
    required this.onChanged,
  });

  final ResourceDefinition definition;
  final Map<String, dynamic> record;
  final bool canWrite;
  final Future<void> Function() onChanged;

  @override
  State<_RecordDetailPage> createState() => _RecordDetailPageState();
}

class _RecordDetailPageState extends State<_RecordDetailPage> {
  late Map<String, dynamic> _record = Map.of(widget.record);

  @override
  Widget build(BuildContext context) {
    final def = widget.definition;
    final c = context.c;
    final t = context.texts;
    final tone = def.toneResolver?.call(_record) ?? AppTone.neutral;

    return Scaffold(
      appBar: AppBar(
          title: Text(asString(_record[def.titleField])),
        actions: [
          if (widget.canWrite && def.canEdit)
            AppButton.icon(
              icon: Icons.edit_outlined,
              tooltip: def.formTitleForEdit,
              onPressed: _edit,
            ),
          if (widget.canWrite && def.canDelete)
            AppButton.icon(
              icon: Icons.delete_outline,
              tooltip: 'Delete',
              variant: AppButtonVariant.dangerGhost,
              onPressed: _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [
          if (def.statusParam.isNotEmpty &&
              _record[def.statusParam] != null) ...[
            AppBadge(
              asString(_record[def.statusParam]).replaceAll('_', ' '),
              tone: tone,
            ),
            const SizedBox(height: 14),
          ],
          for (final f in def.formFields)
            if (_record.containsKey(f.name) && f.visibleWhen?.call(_record) != false)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 116,
                      child: Text(
                        f.label,
                        style: t.labelSmall?.copyWith(color: c.fgFaint),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        _display(f, _record[f.name]),
                        style: t.bodyMedium?.copyWith(color: c.fg),
                      ),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Clipboard.setData(
              ClipboardData(text: Fmt.isoDateTime(DateTime.now())),
            ),
            icon: const Icon(Icons.copy_all_outlined, size: 16),
            label: const Text('Copy record id'),
          ),
        ],
      ),
    );
  }

  String _display(ResourceField f, dynamic v) {
    if (v == null || '$v'.isEmpty) return '—';
    return switch (f.type) {
      ResourceFieldType.money => Fmt.money(asDouble(v)),
      ResourceFieldType.number => Fmt.qty(asDouble(v)),
      ResourceFieldType.date || ResourceFieldType.dateTime => Fmt.dateTime(v),
      _ => '$v',
    };
  }

  Future<void> _edit() async {
    final services = AppScope.read(context);
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ResourceFormPage(
          definition: widget.definition,
          record: _record,
          hotelName: services.hotels.selectedHotel,
        ),
      ),
    );
    if (saved == true) {
      setState(() => _record = Map.of(_record));
      await widget.onChanged();
    }
  }

  Future<void> _delete() async {
    final def = widget.definition;
    final confirmed = await AppConfirmDialog.show(
      context,
      title: 'Delete ${def.singular}?',
      message:
          'This removes ${asString(_record[def.titleField])} permanently. If the '
          'device is offline the delete is queued and replayed later.',
      confirmLabel: 'Delete',
      destructive: true,
      icon: Icons.delete_outline,
    );
    if (!confirmed || !mounted) return;

    final services = AppScope.read(context);
    // Some services key records by `_id`; reading only `id` would put the
    // literal string "null" into the delete URL.
    final id = asString(pick(_record, ['id', '_id']));
    if (id.isEmpty) {
      AppToast.error(context,
          'This record has no identifier, so it cannot be deleted');
      return;
    }
    try {
      final result = await services.api.delete(def.service, def.recordPath(id));
      services.cache.invalidateResource(def.cacheKey);
      if (!mounted) return;
      if (result is QueuedResponse) {
        AppToast.info(context, 'Delete queued for sync');
      } else {
        AppToast.success(context, '${def.singular} deleted');
      }
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) AppToast.error(context, e.message);
    }
  }
}
