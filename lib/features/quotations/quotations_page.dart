import 'package:flutter/material.dart';

import '../../config/api_config.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/sync_engine.dart';
import '../../core/utils/formatting.dart';
import '../../data/resource_controller.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/inputs.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/kit/shell_parts.dart';
import '../../ui/theme.dart';
import 'quotation_detail_page.dart';
import 'quotation_form_page.dart';
import 'quotation_model.dart';
import 'shared_widgets.dart';

/// Port of `features/quotations/pages/quotations-page.tsx`.
///
/// Quotation status is the spine of the whole feature — an order walks
/// received → washing → pressing → folding → packing → ready → out for
/// delivery → delivered — so the list is grouped by that status rather than by
/// date, and the summary strip counts the same buckets the sections show.
class QuotationsPage extends StatefulWidget {
  const QuotationsPage({super.key});

  @override
  State<QuotationsPage> createState() => _QuotationsPageState();
}

class _QuotationsPageState extends State<QuotationsPage> {
  final _searchCtrl = TextEditingController();
  late final ResourceController<List<Quotation>> _controller;

  String _search = '';
  String _tag = '';
  String _status = '';

  @override
  void initState() {
    super.initState();
    _controller = ResourceController(
      key: 'quotations',
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

  Future<List<Quotation>> _fetch() async {
    final services = AppScope.read(context);
    final payload = await services.api.get(
      ServiceNames.quotation,
      QuotationApi.list,
      query: {
        if (_search.isNotEmpty) 'search': _search,
        if (_status.isNotEmpty) 'status': _status,
        if (_tag.isNotEmpty) 'tag': _tag,
      },
    );
    return quotationsFrom(payload);
  }

  Future<void> _reload() => _controller.load(force: true);

  List<Quotation> get _rows => _controller.data ?? const [];

  bool get _hasFilters =>
      _search.isNotEmpty || _status.isNotEmpty || _tag.isNotEmpty;

  List<OpsSection<Quotation>> get _sections {
    final all = _rows;
    final open = all.where((q) => !q.isClosed).toList();
    final ready = open
        .where((q) =>
            q.status == QuotationStatus.ready ||
            q.status == QuotationStatus.outForDelivery)
        .toList();
    final inProgress = open
        .where((q) =>
            q.status == QuotationStatus.received ||
            q.status == QuotationStatus.washing ||
            q.status == QuotationStatus.pressing ||
            q.status == QuotationStatus.folding ||
            q.status == QuotationStatus.packing)
        .toList();
    final draft = open.where((q) => q.status == QuotationStatus.draft).toList();
    final closed = all.where((q) => q.isClosed).toList();
    return [
      OpsSection<Quotation>(
        key: 'ready',
        label: 'Out for delivery',
        icon: Icons.local_shipping_outlined,
        tone: AppTone.success,
        items: ready,
      ),
      OpsSection<Quotation>(
        key: 'in_progress',
        label: 'In progress',
        icon: Icons.local_laundry_service_outlined,
        tone: AppTone.info,
        items: inProgress,
      ),
      OpsSection<Quotation>(
        key: 'draft',
        label: 'Draft',
        icon: Icons.edit_note_outlined,
        tone: AppTone.neutral,
        items: draft,
      ),
      OpsSection<Quotation>(
        key: 'closed',
        label: 'Closed',
        icon: Icons.history,
        tone: AppTone.neutral,
        items: closed,
      ),
    ];
  }

  List<OpsMetric> get _metrics {
    final all = _rows;
    final today = Fmt.today();
    return [
      OpsMetric(
        id: 'total',
        label: 'Quotations',
        value: '${all.length}',
        icon: Icons.description_outlined,
        tone: AppTone.info,
      ),
      OpsMetric(
        id: 'today',
        label: 'Created today',
        value: '${all.where((q) => Fmt.isoDate(q.createdAt) == today).length}',
        icon: Icons.today_outlined,
        tone: AppTone.info,
      ),
      OpsMetric(
        id: 'open',
        label: 'Open',
        value: '${all.where((q) => !q.isClosed).length}',
        icon: Icons.pending_actions_outlined,
        tone: AppTone.warning,
      ),
      OpsMetric(
        id: 'ready',
        label: 'Ready',
        value:
            '${all.where((q) => q.status == QuotationStatus.ready || q.status == QuotationStatus.outForDelivery).length}',
        icon: Icons.check_circle_outline,
        tone: AppTone.success,
      ),
      OpsMetric(
        id: 'cancelled',
        label: 'Cancelled',
        value:
            '${all.where((q) => q.status == QuotationStatus.cancelled).length}',
        icon: Icons.cancel_outlined,
        tone: AppTone.danger,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final c = context.c;
    final rows = _rows;
    final loading = _controller.isLoading && rows.isEmpty;
    final canWrite = services.auth.hasPermission(quotationsReadPermission);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quotations'),
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
            label: 'Quotations',
          ),
          AppOfflineSyncBar(engine: services.sync),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: AppTextInput(
              controller: _searchCtrl,
              hint: 'Search by client or title…',
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
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                AppFilterChip(
                  label: 'All',
                  selected: _tag.isEmpty && _status.isEmpty,
                  count: rows.length,
                  onTap: () {
                    setState(() {
                      _tag = '';
                      _status = '';
                    });
                    _reload();
                  },
                ),
                for (final tag in const ['hotel', 'shop']) ...[
                  const SizedBox(width: 8),
                  AppFilterChip(
                    label: tag == 'shop' ? 'Shop' : 'Hotel',
                    selected: _tag == tag,
                    count: rows.where((q) => q.tag == tag).length,
                    onTap: () {
                      setState(() => _tag = _tag == tag ? '' : tag);
                      _reload();
                    },
                  ),
                ],
                for (final status in [
                  QuotationStatus.draft,
                  QuotationStatus.received,
                  QuotationStatus.washing,
                  QuotationStatus.pressing,
                  QuotationStatus.folding,
                  QuotationStatus.packing,
                  QuotationStatus.ready,
                  QuotationStatus.outForDelivery,
                  QuotationStatus.delivered,
                  QuotationStatus.cancelled,
                ]) ...[
                  const SizedBox(width: 8),
                  AppFilterChip(
                    label: quotationStatusLabels[status]!,
                    selected: _status == quotationStatusValues[status],
                    count: rows.where((q) => q.status == status).length,
                    onTap: () {
                      setState(() => _status =
                          _status == quotationStatusValues[status]
                              ? ''
                              : quotationStatusValues[status]!);
                      _reload();
                    },
                  ),
                ],
              ],
            ),
          ),
          CompactMetrics(items: _metrics),
          if (_hasFilters)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
              child: Row(
                children: [
                  Text(
                    '${Fmt.count(rows.length)} shown',
                    style: context.texts.labelSmall?.copyWith(color: c.fgMuted),
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
                        _tag = '';
                        _status = '';
                      });
                      _reload();
                    },
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
                                    title: _hasFilters
                                        ? 'No quotations match'
                                        : 'No quotations yet',
                                    message: _hasFilters
                                        ? 'Try a different search, tag or status.'
                                        : 'Create the first quotation to start an order.',
                                    icon: Icons.description_outlined,
                                    action: _hasFilters
                                        ? AppButton(
                                            label: 'Clear filters',
                                            variant: AppButtonVariant.secondary,
                                            onPressed: () {
                                              _searchCtrl.clear();
                                              setState(() {
                                                _search = '';
                                                _tag = '';
                                                _status = '';
                                              });
                                              _reload();
                                            },
                                          )
                                        : canWrite
                                            ? AppButton(
                                                label: 'New quotation',
                                                variant:
                                                    AppButtonVariant.primary,
                                                icon: Icons.add,
                                                onPressed: _openCreate,
                                              )
                                            : null,
                                  ),
                                ),
                              ],
                            )
                          : OpsSectionList<Quotation>(
                              sections: _sections,
                              itemBuilder: (context, q) => _QuotationCard(
                                quotation: q,
                                canWrite: canWrite,
                                onOpen: () => _openDetail(q.id),
                                onEdit: () => _openEdit(q.id),
                                onDelete: () => _confirmDelete(q),
                              ),
                            ),
            ),
          ),
        ],
      ),
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              onPressed: _openCreate,
              backgroundColor: c.brand,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('New quotation'),
            )
          : null,
    );
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const QuotationFormPage()),
    );
    if (!mounted) return;
    if (created == true) _reload();
  }

  Future<void> _openEdit(String id) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => QuotationFormPage(quotationId: id)),
    );
    if (!mounted) return;
    if (saved == true) _reload();
  }

  Future<void> _openDetail(String id) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => QuotationDetailPage(quotationId: id)),
    );
    if (mounted) _reload();
  }

  Future<void> _confirmDelete(Quotation q) async {
    final ok = await AppConfirmDialog.show(
      context,
      title: 'Delete quotation?',
      message:
          'Deleting "${q.displayTitle}" for ${q.clientName} is permanent and '
          'cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      final result = await AppScope.read(context)
          .api
          .delete(ServiceNames.quotation, QuotationApi.one(q.id));
      if (!mounted) return;
      QueryCacheInvalidator.instance.invalidate(_controller.key);
      await _controller.refresh();
      if (!mounted) return;
      AppToast.info(
        context,
        result is QueuedResponse
            ? 'Queued — will sync when back online'
            : 'Quotation deleted',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      AppToast.error(context, e.message);
    }
  }
}

class _QuotationCard extends StatelessWidget {
  const _QuotationCard({
    required this.quotation,
    required this.canWrite,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  final Quotation quotation;
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
                      quotation.clientName,
                      style: context.texts.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      quotation.displayTitle,
                      style:
                          context.texts.bodySmall?.copyWith(color: c.fgMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              QuotationStatusBadge(status: quotation.status),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              AppBadge(
                '${quotation.itemCount} items',
                tone: AppTone.neutral,
                compact: true,
              ),
              if (quotation.tag != null) ...[
                const SizedBox(width: 6),
                AppBadge(
                  quotation.isShop ? 'Shop' : 'Hotel',
                  tone: quotation.isShop ? AppTone.warning : AppTone.info,
                  compact: true,
                ),
              ],
              const Spacer(),
              Text(
                Fmt.date(quotation.createdAt),
                style: context.texts.labelSmall?.copyWith(color: c.fgFaint),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Rates total ${Fmt.money(quotation.rateTotal)}',
                  style: context.texts.bodySmall?.copyWith(color: c.fgMuted),
                ),
              ),
              EntityCardActions(
                canWrite: canWrite,
                onOpen: onOpen,
                onEdit: quotation.canEdit ? onEdit : null,
                onDelete: quotation.canEdit ? onDelete : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
