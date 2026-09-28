import 'package:flutter/material.dart';

import '../../config/api_config.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/utils/formatting.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/inputs.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/theme.dart';
import 'quotation_model.dart';

/// Port of `features/quotations/pages/quotation-form-page.tsx`.
///
/// The document is a price list: every line carries a rate and never a
/// quantity, so the running total at the bottom is the agreed rate total and not
/// an amount. Quantities are entered later on the bill, where the actual
/// garments are counted in.
class QuotationFormPage extends StatefulWidget {
  const QuotationFormPage({super.key, this.quotationId});

  final String? quotationId;

  @override
  State<QuotationFormPage> createState() => _QuotationFormPageState();
}

class _QuotationFormPageState extends State<QuotationFormPage> {
  final _clientCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();

  final List<_DraftLine> _lines = [];
  String _tag = 'shop';
  String? _clientError;
  String? _lineError;

  bool _loading = false;
  bool _saving = false;
  bool _dirty = false;

  bool get _isEdit => widget.quotationId != null;

  @override
  void initState() {
    super.initState();
    _lines.add(_DraftLine());
    if (_isEdit) _load();
  }

  @override
  void dispose() {
    _clientCtrl.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final payload = await AppScope.read(context)
          .api
          .get(ServiceNames.quotation, QuotationApi.one(widget.quotationId!));
      if (!mounted) return;
      final q = Quotation.fromJson(Map<String, dynamic>.from(payload as Map));
      setState(() {
        _clientCtrl.text = q.clientName;
        _titleCtrl.text = q.displayTitle;
        _tag = q.tag ?? 'shop';
        _lines
          ..clear()
          ..addAll(
            q.lineItems.isEmpty
                ? [_DraftLine()]
                : q.lineItems.map(_DraftLine.fromItem).toList(),
          );
      });
    } on ApiException catch (e) {
      if (mounted) AppToast.error(context, e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  void _addLine() {
    setState(() {
      _lines.add(_DraftLine());
      _markDirty();
    });
  }

  void _removeLine(int i) {
    setState(() {
      if (_lines.length == 1) {
        _lines[0] = _DraftLine();
      } else {
        _lines.removeAt(i);
      }
      _markDirty();
    });
  }

  double get _rateTotal =>
      _lines.fold<double>(0, (sum, l) => sum + l.unitPrice);

  bool get _valid {
    if (_clientCtrl.text.trim().isEmpty) return false;
    return _lines.any((l) => l.itemName.trim().isNotEmpty);
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final client = _clientCtrl.text.trim();
    if (client.isEmpty) {
      setState(() => _clientError = 'Client / hotel name is required');
      return;
    }
    if (!_valid) {
      setState(() => _lineError = 'Add at least one item with a rate');
      return;
    }
    setState(() {
      _saving = true;
      _clientError = null;
      _lineError = null;
    });

    final items = _lines
        .where((l) => l.itemName.trim().isNotEmpty)
        .map((l) => l.toItem())
        .toList();

    // An edit must not silently walk the order backwards, so `status` is sent
    // only on create, where it is the one legal value. An existing document
    // keeps whatever stage the status endpoint last put it in.
    final payload = <String, dynamic>{
      'client_name': client,
      'quotation_title': _titleCtrl.text.trim().isEmpty
          ? 'Price List'
          : _titleCtrl.text.trim(),
      'line_items': [for (final item in items) item.toJson()],
      'tag': _tag,
      if (!_isEdit) 'status': quotationStatusValues[QuotationStatus.draft],
    };

    try {
      final services = AppScope.read(context);
      final result = _isEdit
          ? await services.api.patch(
              ServiceNames.quotation, QuotationApi.one(widget.quotationId!),
              body: payload)
          : await services.api
              .post(ServiceNames.quotation, QuotationApi.list, body: payload);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      AppToast.success(
        context,
        result is QueuedResponse
            ? 'Saved — will sync when back online'
            : _isEdit
                ? 'Quotation updated'
                : 'Quotation created',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      final field = e.fieldErrors['client_name'];
      setState(() {
        if (field != null) _clientError = field;
        _saving = false;
      });
      if (field == null) AppToast.error(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await AppConfirmDialog.show(
          context,
          title: 'Discard changes?',
          message: 'This quotation has unsaved changes.',
          confirmLabel: 'Discard',
          destructive: true,
        );
        if (leave && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEdit ? 'Edit quotation' : 'New quotation'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: AppButton(
                label: _isEdit ? 'Update' : 'Create',
                size: AppButtonSize.sm,
                variant: AppButtonVariant.primary,
                loading: _saving,
                onPressed: _valid ? _save : null,
              ),
            ),
          ],
        ),
        body: _loading
            ? const AppLoader()
            : Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      children: [
                        AppCard(
                          title: _isEdit
                              ? 'Update pricing for this client'
                              : 'Create a price list for a hotel or client',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AppField(
                                label: 'Client / hotel name',
                                required: true,
                                error: _clientError,
                                child: AppTextInput(
                                  controller: _clientCtrl,
                                  hint: 'Name of the hotel or client',
                                  icon: Icons.apartment_outlined,
                                  textCapitalization: TextCapitalization.words,
                                  errorText: _clientError,
                                  onChanged: (_) {
                                    setState(() => _clientError = null);
                                    _markDirty();
                                  },
                                ),
                              ),
                              const SizedBox(height: 14),
                              AppField(
                                label: 'Quotation title',
                                hint: 'Optional',
                                child: AppTextInput(
                                  controller: _titleCtrl,
                                  hint: 'Defaults to "Price List"',
                                  icon: Icons.title_outlined,
                                  textCapitalization: TextCapitalization.words,
                                  onChanged: (_) => _markDirty(),
                                ),
                              ),
                              const SizedBox(height: 14),
                              AppField(
                                label: 'Type',
                                child: _TagToggle(
                                  value: _tag,
                                  onChanged: (v) {
                                    setState(() => _tag = v);
                                    _markDirty();
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Price list items',
                                style: context.texts.titleSmall,
                              ),
                            ),
                            AppBadge(
                              '${_lines.length}',
                              tone: AppTone.neutral,
                              compact: true,
                            ),
                            const SizedBox(width: 8),
                            AppButton.icon(
                              icon: Icons.add,
                              tooltip: 'Add item',
                              size: AppButtonSize.iconSm,
                              variant: AppButtonVariant.secondary,
                              onPressed: _addLine,
                            ),
                          ],
                        ),
                        if (_lineError != null) ...[
                          const SizedBox(height: 8),
                          AppNotice(message: _lineError!, tone: AppTone.danger),
                        ],
                        const SizedBox(height: 8),
                        for (var i = 0; i < _lines.length; i++) ...[
                          _LineEditor(
                            index: i,
                            line: _lines[i],
                            onChanged: () {
                              setState(() => _lineError = null);
                              _markDirty();
                            },
                            onRemove: () => _removeLine(i),
                          ),
                          const SizedBox(height: 10),
                        ],
                        const SizedBox(height: 6),
                        AppCard(
                          child: Row(
                            children: [
                              Text(
                                'Rate total',
                                style: context.texts.titleSmall,
                              ),
                              const Spacer(),
                              Text(
                                Fmt.money(_rateTotal),
                                style: context.texts.titleMedium
                                    ?.copyWith(color: c.brandText),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        AppNotice(
                          message:
                              'Rates only — quantities are entered on the bill '
                              'when the garments are counted in.',
                          tone: AppTone.info,
                        ),
                      ],
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: AppButton(
                        label:
                            _isEdit ? 'Update quotation' : 'Create quotation',
                        variant: AppButtonVariant.primary,
                        icon: Icons.check,
                        block: true,
                        loading: _saving,
                        onPressed: _valid ? _save : null,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _TagToggle extends StatelessWidget {
  const _TagToggle({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surfaceSunken,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          for (final option in const [
            ('shop', 'Shop / walk-in', Icons.storefront_outlined),
            ('hotel', 'Hotel (private)', Icons.apartment_outlined),
          ])
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(Radii.md),
                onTap: () => onChanged(option.$1),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: value == option.$1 ? c.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(Radii.md),
                    border: Border.all(
                      color: value == option.$1 ? c.brand : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        option.$3,
                        size: 15,
                        color: value == option.$1 ? c.brand : c.fgMuted,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          option.$2,
                          style: context.texts.labelMedium?.copyWith(
                            color: value == option.$1 ? c.brandText : c.fg2,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LineEditor extends StatefulWidget {
  const _LineEditor({
    required this.index,
    required this.line,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final _DraftLine line;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  State<_LineEditor> createState() => _LineEditorState();
}

class _LineEditorState extends State<_LineEditor> {
  late final TextEditingController _name =
      TextEditingController(text: widget.line.itemName);
  late final TextEditingController _category =
      TextEditingController(text: widget.line.category);
  late final TextEditingController _price =
      TextEditingController(text: Fmt.amount(widget.line.unitPrice));
  late final TextEditingController _notes =
      TextEditingController(text: widget.line.notes);

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _price.dispose();
    _notes.dispose();
    for (final spec in widget.line.specs) {
      spec.dispose();
    }
    super.dispose();
  }

  void _commit() {
    widget.line
      ..itemName = _name.text
      ..category = _category.text
      ..unitPrice = double.tryParse(_price.text.replaceAll(',', '')) ?? 0
      ..notes = _notes.text;
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Item ${widget.index + 1}',
                style: context.texts.labelMedium?.copyWith(color: c.fgMuted),
              ),
              const Spacer(),
              AppButton.icon(
                icon: Icons.delete_outline,
                tooltip: 'Remove item',
                size: AppButtonSize.iconSm,
                variant: AppButtonVariant.dangerGhost,
                onPressed: widget.onRemove,
              ),
            ],
          ),
          const SizedBox(height: 6),
          AppTextInput(
            controller: _name,
            hint: 'Item name (e.g. Bed sheet)',
            onChanged: (_) => _commit(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: AppTextInput(
                  controller: _category,
                  hint: 'Category',
                  onChanged: (_) => _commit(),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 132,
                child: AppTextInput(
                  controller: _price,
                  hint: 'Rate',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  suffix: const Text('LKR'),
                  onChanged: (_) => _commit(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AppTextInput(
            controller: _notes,
            hint: 'Notes',
            maxLines: 1,
            onChanged: (_) => _commit(),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                'Specifications',
                style: context.texts.labelSmall?.copyWith(color: c.fgMuted),
              ),
              const Spacer(),
              AppButton(
                label: 'Add variant',
                size: AppButtonSize.xs,
                variant: AppButtonVariant.ghost,
                icon: Icons.add,
                onPressed: () {
                  setState(() => widget.line.specs.add(_DraftSpec()));
                  _commit();
                },
              ),
            ],
          ),
          for (var s = 0; s < widget.line.specs.length; s++) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: AppTextInput(
                    controller: widget.line.specs[s].ctrl,
                    hint: 'Variant (e.g. King)',
                    onChanged: (_) => _commit(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: AppTextInput(
                    controller: widget.line.specs[s].priceCtrl,
                    hint: 'Rate',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => _commit(),
                  ),
                ),
                const SizedBox(width: 6),
                AppButton.icon(
                  icon: Icons.close,
                  tooltip: 'Remove variant',
                  size: AppButtonSize.iconSm,
                  onPressed: () {
                    final removed = widget.line.specs.removeAt(s);
                    removed.dispose();
                    _commit();
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One editable line, holding its own controllers so a rebuild of the list does
/// not reset the field the operator is typing in.
class _DraftLine {
  _DraftLine();

  factory _DraftLine.fromItem(QuotationLineItem item) {
    final line = _DraftLine()
      ..itemName = item.itemName
      ..category = item.category
      ..unitPrice = item.unitPrice
      ..notes = item.notes;
    for (final spec in item.specifications) {
      line.specs.add(_DraftSpec(spec.specification, spec.unitPrice));
    }
    return line;
  }

  String itemName = '';
  String category = '';
  double unitPrice = 0;
  String notes = '';
  final List<_DraftSpec> specs = [];

  QuotationLineItem toItem() => QuotationLineItem(
        itemName: itemName.trim(),
        category: category.trim(),
        unitPrice: unitPrice,
        notes: notes.trim(),
        specifications: [
          for (final spec in specs)
            if (spec.text.trim().isNotEmpty)
              QuotationSpecification(
                specification: spec.text.trim(),
                unitPrice: spec.price,
              ),
        ],
      );
}

class _DraftSpec {
  _DraftSpec([String text = '', double price = 0])
      : ctrl = TextEditingController(text: text),
        priceCtrl = TextEditingController(text: Fmt.amount(price));

  final TextEditingController ctrl;
  final TextEditingController priceCtrl;

  String get text => ctrl.text;
  double get price => double.tryParse(priceCtrl.text.replaceAll(',', '')) ?? 0;

  void dispose() {
    ctrl.dispose();
    priceCtrl.dispose();
  }
}
