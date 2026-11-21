import 'package:flutter/material.dart';

import '../../config/api_config.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/models/json.dart';
import '../../core/utils/formatting.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/inputs.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/theme.dart';
import 'quotation_form_page.dart';
import 'quotation_model.dart';
import 'quotation_print_page.dart';
import 'shared_widgets.dart';

/// Port of `features/quotations/pages/quotation-detail-page.tsx`.
///
/// The detail screen is where an order is actually run: the status endpoint
/// drives one forward step at a time, and the tags endpoint cuts the tracking
/// labels that hang on the garments.
class QuotationDetailPage extends StatefulWidget {
  const QuotationDetailPage({super.key, required this.quotationId});

  final String quotationId;

  @override
  State<QuotationDetailPage> createState() => _QuotationDetailPageState();
}

class _QuotationDetailPageState extends State<QuotationDetailPage> {
  Quotation? _quotation;
  List<GarmentTag> _tags = const [];
  bool _loading = true;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final services = AppScope.read(context);
      final payload = await services.api
          .get(ServiceNames.quotation, QuotationApi.one(widget.quotationId));
      if (!mounted) return;
      setState(() {
        _quotation =
            Quotation.fromJson(Map<String, dynamic>.from(payload as Map));
        _error = null;
      });
      await _loadTags();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadTags() async {
    try {
      final payload = await AppScope.read(context).api.get(
            ServiceNames.quotation,
            QuotationApi.tags(widget.quotationId),
          );
      if (!mounted) return;
      setState(() {
        _tags = asMapList((payload as Map)['tags'])
            .map(GarmentTag.fromJson)
            .toList();
      });
    } on ApiException {
      // Tags are auxiliary; a failure here must not blank the quotation.
    }
  }

  Future<void> _advance(QuotationStatus next) async {
    setState(() => _working = true);
    try {
      final result = await AppScope.read(context).api.post(
        ServiceNames.quotation,
        QuotationApi.status(widget.quotationId),
        body: {'status': quotationStatusValues[next], 'note': ''},
      );
      if (!mounted) return;
      if (result is QueuedResponse) {
        AppToast.info(context, 'Queued — will sync when back online');
      } else {
        AppToast.success(
          context,
          'Moved to ${quotationStatusLabels[next]}',
        );
      }
      await _load();
    } on ApiException catch (e) {
      if (mounted) AppToast.error(context, e.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// The web page has no count prompt: it sends `count: 1` and offers a
  /// per-item toggle, so each press cuts one label or one per line.
  Future<void> _createTags(
      {required bool perItem, required String label}) async {
    setState(() => _working = true);
    try {
      await AppScope.read(context).api.post(
        ServiceNames.quotation,
        QuotationApi.tags(widget.quotationId),
        body: {
          'count': 1,
          'per_item': perItem,
          if (label.trim().isNotEmpty) 'label': label.trim(),
        },
      );
      if (!mounted) return;
      AppToast.success(context, 'Tags generated');
      await _loadTags();
    } on ApiException catch (e) {
      if (mounted) AppToast.error(context, e.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _delete() async {
    final q = _quotation;
    if (q == null) return;
    final ok = await AppConfirmDialog.show(
      context,
      title: 'Delete quotation?',
      message: 'Deleting "${q.displayTitle}" for ${q.clientName} is permanent.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await AppScope.read(context)
          .api
          .delete(ServiceNames.quotation, QuotationApi.one(q.id));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) AppToast.error(context, e.message);
    }
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => QuotationFormPage(quotationId: widget.quotationId),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _print() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => QuotationPrintPage(quotationId: widget.quotationId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _quotation;
    final services = AppScope.of(context);
    if (!canView(services, quotationsReadPermission)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Quotation')),
        body: opsNotPermitted('quotations'),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quotation'),
        actions: [
          AppButton.icon(
            icon: Icons.print_outlined,
            tooltip: 'Print',
            onPressed: q == null ? null : _print,
          ),
          AppButton.icon(
            icon: Icons.edit_outlined,
            tooltip: 'Edit',
            onPressed: q != null && q.canEdit ? _edit : null,
          ),
          AppButton.icon(
            icon: Icons.delete_outline,
            tooltip: 'Delete',
            variant: AppButtonVariant.dangerGhost,
            onPressed: q != null && q.canEdit ? _delete : null,
          ),
        ],
      ),
      body: _loading
          ? const AppLoader()
          : _error != null
              ? AppErrorState(message: _error, onRetry: _load)
              : q == null
                  ? const AppEmptyState(
                      title: 'Quotation not found',
                      icon: Icons.search_off,
                    )
                  : RefreshIndicator(
                      color: context.c.brand,
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                        children: [
                          AppCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            q.clientName,
                                            style: context.texts.titleMedium,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            q.displayTitle,
                                            style: context.texts.bodySmall
                                                ?.copyWith(
                                                    color: context.c.fgMuted),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    QuotationStatusBadge(status: q.status),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                const Divider(height: 1),
                                const SizedBox(height: 10),
                                OpsKeyValue(
                                  label: 'Created',
                                  value: Fmt.dateTime(q.createdAt),
                                ),
                                OpsKeyValue(
                                  label: 'Last updated',
                                  value: Fmt.dateTime(q.updatedAt),
                                ),
                                OpsKeyValue(
                                  label: 'Type',
                                  value: q.isShop ? 'Shop' : 'Hotel',
                                ),
                                OpsKeyValue(
                                  label: 'Items',
                                  value: Fmt.count(q.itemCount),
                                ),
                                OpsKeyValue(
                                  label: 'Rate total',
                                  value: Fmt.money(q.rateTotal),
                                ),
                              ],
                            ),
                          ),
                          if (q.nextStatuses.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            _StatusStepper(
                              quotation: q,
                              working: _working,
                              onAdvance: _advance,
                            ),
                          ] else ...[
                            const SizedBox(height: 14),
                            AppNotice(
                              message: q.status == QuotationStatus.delivered
                                  ? 'This order was delivered. Its history stays '
                                      'here for the record.'
                                  : 'This order was cancelled and cannot move on.',
                              tone: q.status == QuotationStatus.delivered
                                  ? AppTone.success
                                  : AppTone.danger,
                            ),
                          ],
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Price list',
                                  style: context.texts.titleSmall,
                                ),
                              ),
                              Text(
                                Fmt.money(q.rateTotal),
                                style: context.texts.titleSmall
                                    ?.copyWith(color: context.c.fgMuted),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (q.lineItems.isEmpty)
                            const AppEmptyState(
                              title: 'No items',
                              message: 'This price list is empty.',
                              icon: Icons.list_alt_outlined,
                              compact: true,
                            )
                          else
                            for (final item in q.lineItems) ...[
                              _LineCard(item: item),
                              const SizedBox(height: 8),
                            ],
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Garment tags',
                                  style: context.texts.titleSmall,
                                ),
                              ),
                              AppButton(
                                label: 'Per item',
                                size: AppButtonSize.xs,
                                variant: AppButtonVariant.ghost,
                                icon: Icons.sell_outlined,
                                onPressed: _working
                                    ? null
                                    : () =>
                                        _createTags(perItem: true, label: ''),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _TagPanel(
                            tags: _tags,
                            working: _working,
                            onGenerate: (label) => _createTags(
                              perItem: false,
                              label: label,
                            ),
                          ),
                          if (q.statusHistory.isNotEmpty) ...[
                            const SizedBox(height: 18),
                            Text(
                              'Status history',
                              style: context.texts.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            for (final entry in q.statusHistory)
                              _HistoryRow(entry: entry),
                          ],
                        ],
                      ),
                    ),
    );
  }
}

class _StatusStepper extends StatelessWidget {
  const _StatusStepper({
    required this.quotation,
    required this.working,
    required this.onAdvance,
  });

  final Quotation quotation;
  final bool working;
  final ValueChanged<QuotationStatus> onAdvance;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final forward = quotation.nextStatuses
        .where((s) => s != QuotationStatus.cancelled)
        .toList();
    final cancel = quotation.nextStatuses.contains(QuotationStatus.cancelled);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Move this order on',
              style: context.texts.labelMedium?.copyWith(color: c.fg2)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final next in forward)
                      AppButton(
                        label: quotationStatusLabels[next]!,
                        icon: Icons.arrow_forward,
                        size: AppButtonSize.sm,
                        variant: AppButtonVariant.primary,
                        loading: working,
                        onPressed: () => onAdvance(next),
                      ),
                  ],
                ),
              ),
              if (cancel) ...[
                const SizedBox(width: 8),
                AppButton(
                  label: 'Cancel order',
                  icon: Icons.cancel_outlined,
                  size: AppButtonSize.sm,
                  variant: AppButtonVariant.danger,
                  onPressed: working
                      ? null
                      : () => onAdvance(QuotationStatus.cancelled),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({required this.item});

  final QuotationLineItem item;

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
                child: Text(item.itemName, style: context.texts.titleSmall),
              ),
              const SizedBox(width: 10),
              Text(
                Fmt.money(item.unitPrice),
                style: context.texts.titleSmall?.copyWith(color: c.brandText),
              ),
            ],
          ),
          if (item.category.trim().isNotEmpty ||
              item.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              [
                if (item.category.trim().isNotEmpty) item.category.trim(),
                if (item.notes.trim().isNotEmpty) item.notes.trim(),
              ].join(' · '),
              style: context.texts.bodySmall?.copyWith(color: c.fgMuted),
            ),
          ],
          if (item.specifications.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final spec in item.specifications)
                  AppBadge(
                    '${spec.specification} · ${Fmt.money(spec.unitPrice)}',
                    tone: AppTone.neutral,
                    compact: true,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TagPanel extends StatefulWidget {
  const _TagPanel({
    required this.tags,
    required this.working,
    required this.onGenerate,
  });

  final List<GarmentTag> tags;
  final bool working;
  final ValueChanged<String> onGenerate;

  @override
  State<_TagPanel> createState() => _TagPanelState();
}

class _TagPanelState extends State<_TagPanel> {
  final _label = TextEditingController();

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: AppTextInput(
                  controller: _label,
                  hint: 'Label prefix (optional)',
                ),
              ),
              const SizedBox(width: 8),
              AppButton(
                label: 'Generate',
                size: AppButtonSize.sm,
                variant: AppButtonVariant.secondary,
                loading: widget.working,
                onPressed: () => widget.onGenerate(_label.text.trim()),
              ),
            ],
          ),
          if (widget.tags.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            for (final tag in widget.tags)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.qr_code_2_outlined, size: 16, color: c.fgMuted),
                    const SizedBox(width: 8),
                    Text(
                      tag.code,
                      style: context.texts.bodyMedium
                          ?.copyWith(fontFamily: 'monospace'),
                    ),
                    const Spacer(),
                    if ((tag.label ?? '').isNotEmpty)
                      AppBadge(tag.label!, tone: AppTone.info, compact: true),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final QuotationStatusEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final status = quotationStatusFrom(entry.status);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 5),
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: quotationStatusTone(status).dot(c),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  quotationStatusLabels[status]!,
                  style: context.texts.bodyMedium,
                ),
                Text(
                  Fmt.dateTime(entry.changedAt),
                  style: context.texts.labelSmall?.copyWith(color: c.fgFaint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
