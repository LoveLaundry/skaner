import 'package:flutter/material.dart';

import '../../config/api_config.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/utils/formatting.dart';
import '../../data/resource_controller.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/inputs.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/kit/shell_parts.dart';
import '../../ui/theme.dart';
import 'shop_bill_model.dart';

/// Bill templates — the reusable "same order every time" shortcut.
///
/// There is no React page for this, so the shape comes straight from
/// `shop-bill.service.ts`: list with a search, create, update, duplicate, usage
/// and delete. A template is a frozen bill skeleton, so the editor reuses
/// [ShopBillItemsEditor] and posts the same `items` array a real bill does.
class ShopBillTemplatesPage extends StatefulWidget {
  const ShopBillTemplatesPage({super.key});

  @override
  State<ShopBillTemplatesPage> createState() => _ShopBillTemplatesPageState();
}

class _ShopBillTemplatesPageState extends State<ShopBillTemplatesPage> {
  final _searchCtrl = TextEditingController();
  late final ResourceController<List<Map<String, dynamic>>> _controller;

  String _search = '';

  @override
  void initState() {
    super.initState();
    _controller = ResourceController(
      key: 'bill-templates',
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

  Future<List<Map<String, dynamic>>> _fetch() async {
    final payload = await AppScope.read(context).api.get(
      ServiceNames.bills,
      ShopBillApi.templates(),
      query: {if (_search.isNotEmpty) 'search': _search},
    );
    return asRows(payload);
  }

  Future<void> _reload() => _controller.load(force: true);

  List<Map<String, dynamic>> get _rows => _controller.data ?? const [];

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final c = context.c;
    if (!services.auth.hasPermission(shopBillsPermission)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Bill templates')),
        body: const AppErrorState(
          title: 'Not permitted',
          message: 'You do not have access to shop bills.',
          icon: Icons.lock_outline,
        ),
      );
    }

    final rows = _rows;
    final loading = _controller.isLoading && rows.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bill templates'),
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
            label: 'Bill templates',
          ),
          AppOfflineSyncBar(engine: services.sync),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: AppTextInput(
              controller: _searchCtrl,
              hint: 'Search templates…',
              icon: Icons.search,
              textInputAction: TextInputAction.search,
              onChanged: (v) => setState(() => _search = v.trim()),
              onSubmitted: (_) => _reload(),
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
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                          itemCount: rows.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, i) => _TemplateCard(
                            template: rows[i],
                            onEdit: () => _openEditor(rows[i]),
                            onDuplicate: () => _duplicate(rows[i]),
                            onDelete: () => _delete(rows[i]),
                            onUsage: () => _showUsage(rows[i]),
                          ),
                        ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(null),
        backgroundColor: c.brand,
        foregroundColor: c.onBrand,
        icon: const Icon(Icons.add),
        label: const Text('New template'),
      ),
    );
  }

  Future<void> _openEditor(Map<String, dynamic>? template) async {
    final id = template == null ? null : str(template, const ['id']);
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _TemplateEditor(template: template),
    );
    if (created == true) _reload();
    if (id == null) return;
  }

  Future<void> _duplicate(Map<String, dynamic> template) async {
    final id = str(template, const ['id']);
    if (id.isEmpty) return;
    final services = AppScope.read(context);
    try {
      final result = await services.api.post(
        ServiceNames.bills,
        ShopBillApi.templateDuplicate(id),
      );
      if (!mounted) return;
      if (result is QueuedResponse) {
        AppToast.info(context, 'Queued — will sync when you are back online');
      } else {
        AppToast.success(context, 'Template duplicated');
      }
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      AppToast.error(context, e.message);
    }
  }

  Future<void> _showUsage(Map<String, dynamic> template) async {
    final id = str(template, const ['id']);
    if (id.isEmpty) return;
    List<Map<String, dynamic>> usage = const [];
    var error = false;
    try {
      usage = asRows(
        await AppScope.read(context).api.get(
              ServiceNames.bills,
              ShopBillApi.templateUsage(id),
            ),
      );
    } catch (_) {
      error = true;
    }
    if (!mounted) return;
    await AppDialog.show<void>(
      context,
      title: 'Template usage',
      icon: Icons.insights_outlined,
      body: error
          ? const AppNotice(
              message: 'Usage history is unavailable right now.',
              tone: AppTone.warning,
            )
          : usage.isEmpty
              ? const AppEmptyState(
                  title: 'Never used',
                  message: 'No bill has been created from this template yet.',
                  icon: Icons.history_toggle_off,
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final row in usage)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: FieldRow(
                          str(row, const ['bill_number', 'number', 'id'], '—'),
                          Fmt.date(pick(row, const ['created_at', 'date'])),
                        ),
                      ),
                  ],
                ),
      actions: [
        AppButton(
          label: 'Close',
          variant: AppButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Future<void> _delete(Map<String, dynamic> template) async {
    final id = str(template, const ['id']);
    if (id.isEmpty) return;
    final ok = await AppConfirmDialog.show(
      context,
      title: 'Delete template?',
      message: 'Bills already created from it are not affected.',
      confirmLabel: 'Delete',
      destructive: true,
      icon: Icons.delete_outline,
    );
    if (!ok || !mounted) return;
    final services = AppScope.read(context);
    try {
      final result = await services.api
          .delete(ServiceNames.bills, ShopBillApi.templateOne(id));
      if (!mounted) return;
      if (result is QueuedResponse) {
        AppToast.info(context, 'Queued — will sync when you are back online');
      } else {
        AppToast.success(context, 'Template deleted');
      }
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      AppToast.error(context, e.message);
    }
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
    required this.onUsage,
  });

  final Map<String, dynamic> template;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback onUsage;

  @override
  Widget build(BuildContext context) {
    final lines = billLines(template);
    final client = str(template, const ['client_name', 'client']);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
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
                      str(template, const ['name', 'title'],
                          'Untitled template'),
                      style: context.texts.titleSmall,
                    ),
                    if (client.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        client,
                        style: context.texts.bodySmall
                            ?.copyWith(color: context.c.fgMuted),
                      ),
                    ],
                  ],
                ),
              ),
              AppMenuButton(
                label: '',
                icon: Icons.more_vert,
                items: [
                  AppMenuItem(
                    label: 'Edit',
                    icon: Icons.edit_outlined,
                    onTap: onEdit,
                  ),
                  AppMenuItem(
                    label: 'Duplicate',
                    icon: Icons.copy_all_outlined,
                    onTap: onDuplicate,
                  ),
                  AppMenuItem(
                    label: 'Usage',
                    icon: Icons.insights_outlined,
                    subtitle: 'Bills created from this',
                    onTap: onUsage,
                  ),
                  AppMenuItem(
                    label: 'Delete',
                    icon: Icons.delete_outline,
                    enabled: true,
                    onTap: onDelete,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              AppBadge(
                '${lines.length} item${lines.length == 1 ? '' : 's'}',
                icon: Icons.inventory_2_outlined,
                compact: true,
              ),
              AppBadge(
                'Used ${Fmt.count(intOf(template, const ['use_count']))}×',
                icon: Icons.repeat,
                tone: AppTone.info,
                compact: true,
              ),
              AppBadge(
                Fmt.money(templateGrandTotal(template, lines)),
                icon: Icons.payments_outlined,
                tone: AppTone.success,
                compact: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static double templateGrandTotal(
    Map<String, dynamic> template,
    List<ShopBillLine> lines,
  ) =>
      billGrandTotal(
        subtotal: linesSubtotal(lines),
        discounts: numOf(template, const ['discounts', 'discount']),
        transportFee: numOf(template, const ['transport_fee', 'transport']),
        taxes: numOf(template, const ['taxes', 'tax']),
      );
}

/// Create/edit sheet for one template.
///
/// The same widget serves both: with a template it PATCHes, without one it
/// POSTs. Bill number, status and payment are deliberately absent — a template
/// carries the items and the money knobs, not the state of any single bill.
class _TemplateEditor extends StatefulWidget {
  const _TemplateEditor({this.template});

  final Map<String, dynamic>? template;

  @override
  State<_TemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateEditorState extends State<_TemplateEditor> {
  late final TextEditingController _name =
      TextEditingController(text: str(widget.template ?? {}, const ['name']));
  late final TextEditingController _client = TextEditingController(
      text: str(widget.template ?? {}, const ['client_name', 'client']));
  late final TextEditingController _notes =
      TextEditingController(text: str(widget.template ?? {}, const ['notes']));
  late final TextEditingController _discounts = TextEditingController(
      text: _plain(
          numOf(widget.template ?? {}, const ['discounts', 'discount'])));
  late final TextEditingController _transport = TextEditingController(
      text: _plain(
          numOf(widget.template ?? {}, const ['transport_fee', 'transport'])));
  late final TextEditingController _taxes = TextEditingController(
      text: _plain(numOf(widget.template ?? {}, const ['taxes', 'tax'])));

  List<ShopBillLine> _lines = const [];
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.template != null;

  static String _plain(double v) =>
      v == 0 ? '' : (v == v.roundToDouble() ? v.toInt().toString() : '$v');

  static double _read(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '').trim()) ?? 0;

  @override
  void initState() {
    super.initState();
    _lines = billLines(widget.template ?? {});
  }

  @override
  void dispose() {
    _name.dispose();
    _client.dispose();
    _notes.dispose();
    _discounts.dispose();
    _transport.dispose();
    _taxes.dispose();
    super.dispose();
  }

  double get _grandTotal => billGrandTotal(
        subtotal: linesSubtotal(_lines),
        discounts: _read(_discounts),
        transportFee: _read(_transport),
        taxes: _read(_taxes),
      );

  bool get _canSave =>
      _name.text.trim().isNotEmpty && _lines.isNotEmpty && !_saving;

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final api = AppScope.read(context).api;
    final body = <String, dynamic>{
      'name': _name.text.trim(),
      if (_client.text.trim().isNotEmpty) 'client_name': _client.text.trim(),
      'items': _lines.map((l) => l.toJson()).toList(),
      'discounts': _read(_discounts),
      'transport_fee': _read(_transport),
      'taxes': _read(_taxes),
      if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
    };
    try {
      final id = str(widget.template ?? {}, const ['id']);
      final Object? result = _isEdit && id.isNotEmpty
          ? await api.patch(ServiceNames.bills, ShopBillApi.templateOne(id),
              body: body)
          : await api.post(ServiceNames.bills, ShopBillApi.templates(),
              body: body);
      if (!mounted) return;
      if (result is! QueuedResponse) {
        AppToast.success(
          context,
          _isEdit ? 'Template updated' : 'Template created',
        );
      } else {
        AppToast.info(context, 'Queued — will sync when you are back online');
      }
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AppDialog(
        title: _isEdit ? 'Edit template' : 'New template',
        icon: Icons.bookmark_outline,
        maxWidth: 520,
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppField(
                label: 'Template name',
                required: true,
                child: AppTextInput(
                  controller: _name,
                  hint: 'e.g. Weekly bed linen',
                  icon: Icons.bookmark_border,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: 10),
              AppField(
                label: 'Default client',
                optional: true,
                child: AppTextInput(
                  controller: _client,
                  hint: 'Leave empty to ask each time',
                  icon: Icons.storefront_outlined,
                ),
              ),
              const SizedBox(height: 14),
              Text('Items', style: context.texts.titleSmall),
              const SizedBox(height: 8),
              ShopBillItemsEditor(
                initial: _lines,
                onChanged: (l) => setState(() => _lines = l),
              ),
              const SizedBox(height: 14),
              Text('Money', style: context.texts.titleSmall),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: AppField(
                      label: 'Discounts',
                      child: AppMoneyInput(
                        controller: _discounts,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppField(
                      label: 'Transport',
                      child: AppMoneyInput(
                        controller: _transport,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppField(
                      label: 'Taxes',
                      child: AppMoneyInput(
                        controller: _taxes,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              AppField(
                label: 'Notes',
                optional: true,
                child: AppTextInput(controller: _notes, maxLines: 2),
              ),
              const SizedBox(height: 12),
              TotalRow('Template total', Fmt.money(_grandTotal), strong: true),
              if (_error != null) ...[
                const SizedBox(height: 10),
                AppNotice(message: _error!, tone: AppTone.danger),
              ],
            ],
          ),
        ),
        actions: [
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          AppButton(
            label: _isEdit ? 'Save' : 'Create',
            variant: AppButtonVariant.primary,
            icon: Icons.check,
            loading: _saving,
            onPressed: _canSave ? _save : null,
          ),
        ],
      );
}
