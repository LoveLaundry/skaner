import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/api_config.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/sync_engine.dart';
import '../../core/utils/formatting.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/inputs.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/theme.dart';
import 'bill_model.dart';
import 'quotation_model.dart';
import 'shared_widgets.dart';

/// Why a count did not match. The web app offers exactly this list, and the
/// server stores the raw key, so these strings must not be reworded.
const List<String> gatePassMismatchReasons = [
  'SHORT_RECEIVED',
  'DAMAGED',
  'EXTRA_RECEIVED',
  'COUNTING_ERROR',
  'OTHER',
];

/// Port of `pages/create-gatepass-page.tsx`.
///
/// Two things make this form more than a list of counts. The pass can be linked
/// to a quotation, and any line that is not on that quotation is written back
/// onto it at zero price so the two documents never drift apart. And the
/// operator almost always receives the same hotel's linen in the same order, so
/// the last receipt's lines are one tap away.
class GatepassFormPage extends StatefulWidget {
  const GatepassFormPage({super.key, this.gatepassId});

  final String? gatepassId;

  @override
  State<GatepassFormPage> createState() => _GatepassFormPageState();
}

class _GatepassFormPageState extends State<GatepassFormPage> {
  final _numberCtrl = TextEditingController();
  final _receivedByCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  List<_CountLine> _lines = [_CountLine()];
  String _clientName = '';
  String _quotationId = '';
  Quotation? _quotation;
  DateTime _receivingDate = DateTime.now();

  bool _loading = false;
  bool _saving = false;
  String? _error;

  bool get _isEdit => (widget.gatepassId ?? '').isNotEmpty;

  @override
  void initState() {
    super.initState();
    _clientName = AppScope.read(context).hotels.selectedHotel;
    if (_isEdit) {
      _load();
    } else {
      _numberCtrl.text = _generateNumber();
    }
  }

  @override
  void dispose() {
    _numberCtrl.dispose();
    _receivedByCtrl.dispose();
    _notesCtrl.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  /// The web app seeds `GP-YYYYMMDD-NNNN`; the server does not care, but the
  /// printed slip is easier to file when the number carries the date.
  static String _generateNumber() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final suffix = 1000 + (DateTime.now().millisecondsSinceEpoch % 9000);
    return 'GP-${now.year}${two(now.month)}${two(now.day)}-$suffix';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final payload = await AppScope.read(context)
          .api
          .get(operationsService, GatePassApi.one(widget.gatepassId!));
      final gp = GatePass.fromJson(Map<String, dynamic>.from(payload as Map));
      final date = Fmt.parseDate(gp.receivingDate);
      setState(() {
        _numberCtrl.text = gp.gatePassNumber;
        _receivedByCtrl.text = gp.receivedBy;
        _notesCtrl.text = gp.notes ?? '';
        _clientName = gp.clientName;
        _quotationId = gp.quotationId ?? '';
        _receivingDate = date ?? DateTime.now();
        for (final l in _lines) {
          l.dispose();
        }
        _lines = gp.items.isEmpty
            ? [_CountLine()]
            : gp.items.map(_CountLine.fromItem).toList();
      });
      if (_quotationId.isNotEmpty) _loadQuotation(_quotationId);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadQuotation(String id) async {
    try {
      final payload = await AppScope.read(context)
          .api
          .get(ServiceNames.quotation, QuotationApi.one(id));
      if (!mounted) return;
      setState(
        () => _quotation =
            Quotation.fromJson(Map<String, dynamic>.from(payload as Map)),
      );
    } on ApiException {
      // A linked quotation that cannot be read only costs the item suggestions;
      // the counts themselves are what the operator typed.
    }
  }

  bool get _valid =>
      _numberCtrl.text.trim().isNotEmpty &&
      _clientName.trim().isNotEmpty &&
      _receivedByCtrl.text.trim().isNotEmpty &&
      _lines.isNotEmpty &&
      _lines.every((l) => l.name.trim().isNotEmpty && l.received >= 0);

  /// A line whose name is not on the linked quotation is a new item for that
  /// hotel, and the web app appends it to the quotation at zero price.
  int get _customCount {
    if (_quotation == null) return 0;
    final known = _quotation!.lineItems
        .map((l) => l.itemName.trim().toLowerCase())
        .toSet();
    return _lines
        .where((l) =>
            l.name.trim().isNotEmpty &&
            !known.contains(l.name.trim().toLowerCase()))
        .length;
  }

  /// A number already in use would make two passes indistinguishable on paper.
  Future<String?> _duplicateNumber() async {
    final wanted = _numberCtrl.text.trim().toLowerCase();
    if (wanted.isEmpty || _isEdit) return null;
    try {
      final payload = await AppScope.read(context)
          .api
          .get(operationsService, GatePassApi.list, query: {'limit': 200});
      for (final gp in gatePassesFrom(payload)) {
        if (gp.status == 'CANCELLED') continue;
        if (gp.gatePassNumber.trim().toLowerCase() == wanted) {
          return gp.gatePassNumber;
        }
      }
    } on ApiException {
      return null;
    }
    return null;
  }

  void _setLine(int index, _CountLine Function(_CountLine) change) {
    setState(() => _lines[index] = change(_lines[index]));
  }

  void _addLine() => setState(() => _lines.add(_CountLine()));

  void _removeLine(int index) {
    final removed = _lines.removeAt(index);
    removed.dispose();
    // The web grid always keeps one row; an empty form cannot be submitted.
    if (_lines.isEmpty) _lines.add(_CountLine());
    setState(() {});
  }

  void _repeatLastRow() {
    if (_lines.isEmpty) return;
    final last = _lines.last;
    setState(() => _lines.add(
          _CountLine()
            ..name = last.name
            ..category = last.category
            ..specification = last.specification,
        ));
  }

  Future<void> _pickQuotation() async {
    List<Quotation> all;
    try {
      final payload = await AppScope.read(context).api.get(
        ServiceNames.quotation,
        QuotationApi.list,
        query: {'limit': 200},
      );
      all = quotationsFrom(payload);
    } on ApiException catch (e) {
      if (mounted) AppToast.error(context, e.message);
      return;
    }
    if (!mounted) return;
    final picked = await showModalBottomSheet<Quotation>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _QuotationPickerSheet(all: all),
    );
    if (picked == null || !mounted) return;
    // Linking a quotation sets the client, it does not fill the grid: what came
    // in the door is what the operator counts.
    setState(() {
      _quotation = picked;
      _quotationId = picked.id;
      _clientName = picked.clientName;
    });
  }

  void _clearQuotation() => setState(() {
        _quotation = null;
        _quotationId = '';
      });

  Future<void> _save() async {
    if (!_valid) return;
    final clash = await _duplicateNumber();
    if (clash != null) {
      if (mounted) {
        AppToast.error(context, 'Gate pass number $clash already exists');
      }
      return;
    }
    if (!mounted) return;
    setState(() => _saving = true);
    final gatePass = GatePass(
      id: widget.gatepassId ?? '',
      gatePassNumber: _numberCtrl.text.trim(),
      clientName: _clientName.trim(),
      receivingDate: Fmt.isoDate(_receivingDate),
      receivedBy: _receivedByCtrl.text.trim(),
      status: 'RECEIVED',
      notes: _notesCtrl.text.trim(),
      quotationId: _quotationId.isEmpty ? null : _quotationId,
      items: [
        for (final l in _lines)
          GatePassItem(
            itemName: l.name,
            category: l.category,
            specification: l.specification,
            clientQty: l.client,
            receivedQty: l.received,
            difference: l.received - l.client,
            mismatchReason: l.mismatchReason,
            mismatchNotes: l.mismatchNotes,
            rewashed: l.rewashed,
          ),
      ],
    );

    try {
      final services = AppScope.read(context);
      if (!_isEdit && _customCount > 0 && _quotation != null) {
        await _appendCustomItemsToQuotation(gatePass);
      }
      final result = _isEdit
          ? await services.api.patch(
              operationsService,
              GatePassApi.one(widget.gatepassId!),
              body: gatePass.updateJson(),
            )
          : await services.api.post(
              operationsService,
              GatePassApi.list,
              body: gatePass.createJson(),
            );
      if (!mounted) return;
      QueryCacheInvalidator.instance.invalidate('gatepasses');
      Navigator.of(context).pop(true);
      AppToast.success(
        context,
        result is QueuedResponse
            ? 'Saved — will sync when back online'
            : _isEdit
                ? 'Gate pass updated'
                : 'Gate pass recorded',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.error(context, e.message);
    }
  }

  /// Best-effort: a failure here must not block the gate pass, which is the
  /// document the hotel actually needs.
  Future<void> _appendCustomItemsToQuotation(GatePass pass) async {
    final q = _quotation!;
    final known =
        q.lineItems.map((l) => l.itemName.trim().toLowerCase()).toSet();
    final custom = pass.items
        .where((i) => !known.contains(i.itemName.trim().toLowerCase()))
        .toList();
    if (custom.isEmpty) return;
    try {
      await AppScope.read(context).api.patch(
        ServiceNames.quotation,
        QuotationApi.one(q.id),
        body: {
          'client_name': q.clientName,
          'quotation_title': q.displayTitle,
          'line_items': [
            for (final item in q.lineItems) item.toJson(),
            for (final item in custom)
              {
                'item_name': item.itemName,
                if (item.category.trim().isNotEmpty) 'category': item.category,
                'unit_price': 0,
                'notes': 'Auto-added from gate pass',
              },
          ],
        },
      );
    } on ApiException {
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    if (!canView(services, gatePassesPermission)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gate pass')),
        body: opsNotPermitted('gate passes'),
      );
    }
    final c = context.c;
    final suggestions = _suggestions;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit gate pass' : 'New gate pass'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: AppButton(
              label: 'Save',
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
                      if (_error != null) ...[
                        AppNotice(
                          message: _error!,
                          tone: AppTone.danger,
                          action: AppButton(
                            label: 'Retry',
                            size: AppButtonSize.xs,
                            variant: AppButtonVariant.secondary,
                            onPressed: _load,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      AppField(
                        label: 'Gate pass number',
                        required: true,
                        child: AppTextInput(
                          controller: _numberCtrl,
                          mono: true,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(height: 12),
                      HotelPicker(
                        hotels: AppScope.of(context).hotels.hotels,
                        value: _clientName,
                        onChanged: (v) => setState(() => _clientName = v ?? ''),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: AppField(
                              label: 'Receiving date',
                              required: true,
                              child: AppDateField(
                                value: _receivingDate,
                                onChanged: (d) {
                                  if (d != null) {
                                    setState(() => _receivingDate = d);
                                  }
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: AppField(
                              label: 'Received by',
                              required: true,
                              child: AppTextInput(
                                controller: _receivedByCtrl,
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AppField(
                        label: 'Linked quotation',
                        optional: true,
                        child: _quotation == null
                            ? AppButton(
                                label: 'Link a quotation',
                                variant: AppButtonVariant.secondary,
                                icon: Icons.link,
                                onPressed: _pickQuotation,
                              )
                            : AppCard(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    const OpsIcon(Icons.description_outlined,
                                        size: 34),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _quotation!.displayTitle,
                                            style: context.texts.bodyMedium
                                                ?.copyWith(
                                                    fontWeight:
                                                        FontWeight.w600),
                                          ),
                                          Text(
                                            _quotation!.clientName,
                                            style: context.texts.bodySmall
                                                ?.copyWith(color: c.fgMuted),
                                          ),
                                        ],
                                      ),
                                    ),
                                    AppButton.icon(
                                      icon: Icons.close,
                                      tooltip: 'Unlink',
                                      size: AppButtonSize.iconSm,
                                      onPressed: _clearQuotation,
                                    ),
                                  ],
                                ),
                              ),
                      ),
                      if (_customCount > 0) ...[
                        const SizedBox(height: 8),
                        AppNotice(
                          message:
                              '$_customCount item${_customCount > 1 ? 's' : ''} '
                              'not on the linked quotation. They will be added to '
                              'it at zero price when this pass is saved.',
                          tone: AppTone.info,
                        ),
                      ],
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Items received',
                              style: context.texts.titleSmall,
                            ),
                          ),
                          AppButton(
                            label: 'Repeat last',
                            size: AppButtonSize.xs,
                            variant: AppButtonVariant.ghost,
                            icon: Icons.content_copy,
                            onPressed: _repeatLastRow,
                          ),
                          AppButton(
                            label: 'Add row',
                            size: AppButtonSize.xs,
                            variant: AppButtonVariant.secondary,
                            icon: Icons.add,
                            onPressed: _addLine,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (var i = 0; i < _lines.length; i++) ...[
                        _CountEditor(
                          key: ValueKey(i),
                          line: _lines[i],
                          suggestions: suggestions,
                          onChanged: () => setState(() {}),
                          onNameChanged: (name) =>
                              _setLine(i, (l) => l..name = name),
                          onRemove: () => _removeLine(i),
                          removable: _lines.length > 1,
                        ),
                        const SizedBox(height: 8),
                      ],
                      const SizedBox(height: 4),
                      AppField(
                        label: 'Notes',
                        optional: true,
                        child: AppTextInput(
                          controller: _notesCtrl,
                          maxLines: 3,
                        ),
                      ),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    decoration: BoxDecoration(
                      color: c.surface,
                      border: Border(top: BorderSide(color: c.line)),
                    ),
                    child: Row(
                      children: [
                        Text(
                          '${_lines.where((l) => l.name.trim().isNotEmpty).length} '
                          'items · ${_lines.fold<int>(0, (s, l) => s + l.received)} pcs',
                          style: context.texts.bodySmall
                              ?.copyWith(color: c.fgMuted),
                        ),
                        const Spacer(),
                        AppButton(
                          label: 'Save gate pass',
                          variant: AppButtonVariant.primary,
                          icon: Icons.check,
                          loading: _saving,
                          onPressed: _valid ? _save : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  /// Item names from the linked quotation, so the common case is a tap rather
  /// than typing. A name that is not on the list is still allowed — the hotel
  /// counts what it counts.
  List<String> get _suggestions {
    final q = _quotation;
    if (q == null) return const [];
    return [
      for (final line in q.lineItems)
        if (line.specifications.isEmpty)
          line.itemName
        else
          for (final s in line.specifications)
            '${line.itemName} — ${s.specification}',
    ];
  }
}

/// One editable count line. The controllers are owned here so switching a name
/// from the suggestion list cannot leave the field showing the old text.
class _CountLine {
  _CountLine();

  factory _CountLine.fromItem(GatePassItem item) => _CountLine()
    ..name = item.itemName
    ..category = item.category
    ..specification = item.specification
    ..client = item.clientQty
    ..received = item.receivedQty
    ..mismatchReason = item.mismatchReason
    ..mismatchNotes = item.mismatchNotes
    ..rewashed = item.rewashed;

  String name = '';
  String category = '';
  String specification = '';
  int client = 0;
  int received = 0;
  String mismatchReason = '';
  String mismatchNotes = '';
  bool rewashed = false;

  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _clientCtrl = TextEditingController(text: '0');
  final TextEditingController _receivedCtrl = TextEditingController(text: '0');
  final TextEditingController _notesCtrl = TextEditingController();

  TextEditingController get nameCtrl => _nameCtrl;
  TextEditingController get clientCtrl => _clientCtrl;
  TextEditingController get receivedCtrl => _receivedCtrl;
  TextEditingController get notesCtrl => _notesCtrl;

  void dispose() {
    _nameCtrl.dispose();
    _clientCtrl.dispose();
    _receivedCtrl.dispose();
    _notesCtrl.dispose();
  }
}

class _CountEditor extends StatelessWidget {
  const _CountEditor({
    super.key,
    required this.line,
    required this.suggestions,
    required this.onChanged,
    required this.onNameChanged,
    required this.onRemove,
    required this.removable,
  });

  final _CountLine line;
  final List<String> suggestions;
  final VoidCallback onChanged;
  final ValueChanged<String> onNameChanged;
  final VoidCallback onRemove;
  final bool removable;

  static int _intOf(String raw) => int.tryParse(raw.trim()) ?? 0;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final difference = line.received - line.client;
    final hasMismatch = difference != 0;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppTextInput(
                  controller: line.nameCtrl,
                  hint: 'Item name',
                  onChanged: (v) {
                    onNameChanged(v);
                    onChanged();
                  },
                ),
              ),
              if (removable) ...[
                const SizedBox(width: 6),
                AppButton.icon(
                  icon: Icons.delete_outline,
                  tooltip: 'Remove row',
                  size: AppButtonSize.iconSm,
                  variant: AppButtonVariant.dangerGhost,
                  onPressed: onRemove,
                ),
              ],
            ],
          ),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 26,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: suggestions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) => AppFilterChip(
                  label: suggestions[i],
                  selected: line.name.trim() == suggestions[i],
                  onTap: () {
                    final name = suggestions[i].split(' — ').first;
                    final spec = suggestions[i].contains(' — ')
                        ? suggestions[i].split(' — ').last
                        : '';
                    line.nameCtrl.text = name;
                    line.specification = spec;
                    onNameChanged(name);
                    onChanged();
                  },
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: AppField(
                  label: 'Client count',
                  child: AppTextInput(
                    controller: line.clientCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (v) {
                      line.client = _intOf(v);
                      onChanged();
                    },
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppField(
                  label: 'Received',
                  required: true,
                  child: AppTextInput(
                    controller: line.receivedCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (v) {
                      line.received = _intOf(v);
                      onChanged();
                    },
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 72,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Difference',
                      style:
                          context.texts.labelSmall?.copyWith(color: c.fgFaint),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      difference > 0 ? '+$difference' : '$difference',
                      style: context.texts.titleSmall?.copyWith(
                        color: !hasMismatch
                            ? c.fgMuted
                            : difference < 0
                                ? c.warning
                                : c.info,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Row(
            children: [
              Checkbox(
                value: line.rewashed,
                onChanged: (v) {
                  line.rewashed = v ?? false;
                  onChanged();
                },
              ),
              Expanded(
                child: Text(
                  'Re-wash — not billed',
                  style: context.texts.bodySmall?.copyWith(color: c.fgMuted),
                ),
              ),
            ],
          ),
          if (hasMismatch) ...[
            const SizedBox(height: 4),
            AppField(
              label: 'Reason',
              required: true,
              child: AppSearchableSelect<String>(
                value: line.mismatchReason.isEmpty ? null : line.mismatchReason,
                searchable: false,
                options: [
                  for (final r in gatePassMismatchReasons)
                    AppSelectOption<String>(value: r, label: humaniseStatus(r)),
                ],
                onChanged: (v) {
                  line.mismatchReason = v ?? '';
                  onChanged();
                },
              ),
            ),
            const SizedBox(height: 8),
            AppField(
              label: 'Mismatch notes',
              optional: true,
              child: AppTextInput(
                controller: line.notesCtrl,
                onChanged: (v) {
                  line.mismatchNotes = v;
                  onChanged();
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuotationPickerSheet extends StatefulWidget {
  const _QuotationPickerSheet({required this.all});

  final List<Quotation> all;

  @override
  State<_QuotationPickerSheet> createState() => _QuotationPickerSheetState();
}

class _QuotationPickerSheetState extends State<_QuotationPickerSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needle = _query.trim().toLowerCase();
    final rows = widget.all
        .where((q) =>
            needle.isEmpty ||
            '${q.clientName} ${q.displayTitle}'.toLowerCase().contains(needle))
        .toList();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  'Link a quotation',
                  style: context.texts.titleMedium,
                ),
                const Spacer(),
                AppButton.icon(
                  icon: Icons.close,
                  tooltip: 'Close',
                  size: AppButtonSize.iconSm,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 10),
            AppTextInput(
              controller: _searchCtrl,
              hint: 'Search by client or title…',
              icon: Icons.search,
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: rows.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: AppEmptyState(
                        title: 'No quotations found',
                        message: 'Try a different search.',
                        icon: Icons.description_outlined,
                        compact: true,
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final q = rows[i];
                        return ListTile(
                          title: Text(q.displayTitle),
                          subtitle: Text(
                            '${q.clientName} · ${Fmt.date(q.createdAt)}',
                          ),
                          trailing: QuotationStatusBadge(status: q.status),
                          onTap: () => Navigator.of(context).pop(q),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
