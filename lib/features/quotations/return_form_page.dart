import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/sync_engine.dart';
import '../../data/resource_controller.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/inputs.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/theme.dart';
import '../../core/utils/formatting.dart';
import 'bill_model.dart';
import 'quotation_model.dart';
import 'return_detail_page.dart';
import 'shared_widgets.dart';

/// Port of `pages/create-return-page.tsx`.
///
/// A return is anchored to a gate pass: the operator ticks the pass lines that
/// came back, and any line the pass does not know about is entered as a custom
/// item. The web app has no edit route, so `returnId` is only used when the app
/// opens the form for a record that already exists.
class ReturnFormPage extends StatefulWidget {
  const ReturnFormPage({super.key, this.returnId});

  final String? returnId;

  @override
  State<ReturnFormPage> createState() => _ReturnFormPageState();
}

class _ReturnFormPageState extends State<ReturnFormPage> {
  final _gpSearchCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  late final ResourceController<List<GatePass>> _gatePasses;

  GatePass? _gatePass;
  final List<Delivery> _deliveries = [];
  String _deliveryId = '';

  final Map<int, ReturnLine> _gpLines = {};
  final List<ReturnLine> _customLines = [];

  String _adjustmentType = 'NONE';
  double _adjustmentAmount = 0;
  String _adjustmentNotes = '';

  final bool _loadingGatePasses = true;
  bool _loadingDeliveries = false;
  bool _loadingExisting = false;
  bool _saving = false;
  String? _error;

  bool get _isEdit => (widget.returnId ?? '').isNotEmpty;

  @override
  void initState() {
    super.initState();
    _gatePasses = ResourceController(
      key: 'gatepasses',
      cache: AppScope.read(context).cache,
      fetcher: _fetchGatePasses,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _gatePasses.load(force: true);
      if (_isEdit) _loadExisting();
    });
  }

  @override
  void dispose() {
    _gpSearchCtrl.dispose();
    _notesCtrl.dispose();
    _gatePasses.dispose();
    super.dispose();
  }

  Future<List<GatePass>> _fetchGatePasses() async {
    final hotel = AppScope.read(context).hotels.queryParam;
    final payload = await AppScope.read(context).api.get(
      operationsService,
      GatePassApi.list,
      query: {
        if (hotel != null) 'client_name': hotel,
        'limit': 100,
      },
    );
    return gatePassesFrom(payload);
  }

  /// A return that is being edited keeps the pass it was recorded against; the
  /// form restores the ticked lines by name and specification, because the
  /// server does not echo the gate-pass line index.
  Future<void> _loadExisting() async {
    setState(() => _loadingExisting = true);
    try {
      final payload = await AppScope.read(context)
          .api
          .get(operationsService, ReturnApi.one(widget.returnId!));
      final record =
          ReturnRecord.fromJson(Map<String, dynamic>.from(payload as Map));
      final adjustment = record.billAdjustment;
      if (!mounted) return;
      setState(() {
        _deliveryId = record.deliveryId;
        _adjustmentType = adjustment.adjustmentType;
        _adjustmentAmount = adjustment.amount;
        _adjustmentNotes = adjustment.notes;
        _notesCtrl.text = record.notes ?? '';
        _loadingExisting = false;
      });
      final passes = await _loadPassesForEdit(record.gatePassId);
      if (passes == null || !mounted) return;
      setState(() {
        for (final line in record.items) {
          final index = passes.items.indexWhere(
            (i) =>
                i.itemName.trim() == line.itemName.trim() &&
                i.specification.trim() == line.specification.trim(),
          );
          if (index >= 0 && !_gpLines.containsKey(index)) {
            _gpLines[index] = line;
          } else {
            _customLines.add(line);
          }
        }
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loadingExisting = false;
        });
      }
    }
  }

  /// The picker list only shows the current hotel's recent passes, so an older
  /// record may name one that is not in it.
  Future<GatePass?> _loadPassesForEdit(String gatePassId) async {
    try {
      final payload = await AppScope.read(context).api.get(
            operationsService,
            GatePassApi.one(gatePassId),
          );
      final pass = GatePass.fromJson(Map<String, dynamic>.from(payload as Map));
      if (!mounted) return null;
      setState(() => _gatePass = pass);
      return pass;
    } on ApiException {
      return null;
    }
  }

  List<GatePass> get _filteredPasses {
    final needle = _gpSearchCtrl.text.trim().toLowerCase();
    final all = _gatePasses.data ?? const <GatePass>[];
    if (needle.isEmpty) return all;
    return all.where((p) {
      return p.gatePassNumber.toLowerCase().contains(needle) ||
          p.clientName.toLowerCase().contains(needle);
    }).toList();
  }

  /// Deliveries are only offered for the selected pass, and only once one is
  /// selected; the link is optional on the wire.
  Future<void> _selectPass(GatePass pass) async {
    setState(() {
      _gatePass = pass;
      _gpLines.clear();
      _deliveryId = '';
      _deliveries.clear();
      _error = null;
    });
    _gpSearchCtrl.clear();
    if (pass.id.isEmpty) return;
    setState(() => _loadingDeliveries = true);
    try {
      final hotel = AppScope.read(context).hotels.queryParam;
      final payload = await AppScope.read(context).api.get(
        operationsService,
        DeliveryApi.list,
        query: {
          'gate_pass_id': pass.id,
          if (hotel != null) 'client_name': hotel,
          'limit': 50,
        },
      );
      if (!mounted) return;
      setState(() {
        _deliveries
          ..clear()
          ..addAll(deliveriesFrom(payload));
        _loadingDeliveries = false;
      });
    } on ApiException {
      if (mounted) setState(() => _loadingDeliveries = false);
    }
  }

  void _clearPass() {
    setState(() {
      _gatePass = null;
      _gpLines.clear();
      _deliveries.clear();
      _deliveryId = '';
    });
  }

  void _toggleGpLine(int index) {
    setState(() {
      if (_gpLines.containsKey(index)) {
        _gpLines.remove(index);
      } else {
        _gpLines[index] = ReturnLine(
          returnedQty: 1,
          reason: 'WRONG_ITEM',
          condition: 'GOOD',
          action: 'RECEIVE_BACK',
        );
      }
    });
  }

  void _updateGpLine(int index, ReturnLine line) {
    setState(() => _gpLines[index] = line);
  }

  void _addCustomLine() {
    setState(() {
      _customLines.add(
        ReturnLine(
          returnedQty: 1,
          reason: 'WRONG_ITEM',
          condition: 'GOOD',
          action: 'RECEIVE_BACK',
        ),
      );
    });
  }

  bool get _hasItems {
    if (_gpLines.isNotEmpty) return true;
    return _customLines.any((l) => l.itemName.trim().isNotEmpty);
  }

  bool get _valid {
    if (_gatePass == null) return false;
    if (!_hasItems) return false;
    for (final l in _customLines) {
      if (l.itemName.trim().isEmpty) continue;
      if (l.returnedQty < 1) return false;
    }
    return true;
  }

  /// The wire shape the web app posts: pass lines in gate-pass order first,
  /// then the custom lines, each with the reason/condition/action the operator
  /// chose. Resend tracking is the server's to set.
  List<ReturnLine> get _payloadLines {
    final pass = _gatePass;
    if (pass == null) return const [];
    final lines = <ReturnLine>[];
    final indices = _gpLines.keys.toList()..sort();
    for (final i in indices) {
      final item = pass.items[i];
      final line = _gpLines[i]!;
      lines.add(
        ReturnLine(
          itemName: item.itemName,
          specification: item.specification,
          returnedQty: line.returnedQty,
          reason: line.reason,
          condition: line.condition,
          action: line.action,
          notes: line.notes,
        ),
      );
    }
    for (final l in _customLines) {
      if (l.itemName.trim().isEmpty) continue;
      lines.add(l);
    }
    return lines;
  }

  Future<void> _save() async {
    final pass = _gatePass;
    if (pass == null) {
      setState(() => _error = 'Select a gate pass');
      return;
    }
    if (!_hasItems) {
      setState(() => _error = 'Select at least one item to return');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final record = ReturnRecord(
      gatePassId: pass.id,
      deliveryId: _deliveryId,
      clientName: pass.clientName,
      items: _payloadLines,
      billAdjustment: BillAdjustment(
        adjustmentType: _adjustmentType,
        amount: _adjustmentAmount,
        notes: _adjustmentNotes,
      ),
      notes: _notesCtrl.text.trim(),
    );
    try {
      final result = _isEdit
          ? await AppScope.read(context).api.patch(
              operationsService,
              ReturnApi.one(widget.returnId!),
              body: {
                'items': record.createJson()['items'],
                if (_adjustmentType != 'NONE')
                  'bill_adjustment': record.billAdjustment.toJson(),
                if (record.notes!.isNotEmpty) 'notes': record.notes,
              },
            )
          : await AppScope.read(context).api.post(
              operationsService, ReturnApi.list,
              body: record.createJson());
      if (!mounted) return;
      QueryCacheInvalidator.instance.invalidate('returns');
      final key = result is QueuedResponse
          ? ''
          : ReturnRecord.fromJson(
              Map<String, dynamic>.from(result as Map),
            ).key;
      if (key.isNotEmpty) {
        await Navigator.of(context).pushReplacement<void, void>(
          MaterialPageRoute(builder: (_) => ReturnDetailPage(returnId: key)),
        );
        return;
      }
      Navigator.of(context).pop(true);
      AppToast.success(
        context,
        result is QueuedResponse
            ? 'Saved — will sync when back online'
            : 'Return recorded',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    if (!canView(services, gatePassesPermission)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Record return')),
        body: opsNotPermitted('returns'),
      );
    }
    final pass = _gatePass;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit return' : 'Record return'),
      ),
      body: _loadingExisting
          ? const AppLoader()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _passCard(),
                const SizedBox(height: 12),
                if (pass != null) _deliveryCard(),
                const SizedBox(height: 12),
                _itemsCard(),
                const SizedBox(height: 12),
                _adjustmentCard(),
                const SizedBox(height: 12),
                AppCard(
                  child: AppField(
                    label: 'Notes',
                    optional: true,
                    child: AppTextInput(
                      controller: _notesCtrl,
                      hint: 'Optional notes about this return…',
                      maxLines: 3,
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  AppNotice(message: _error!, tone: AppTone.danger),
                ],
                const SizedBox(height: 18),
                AppButton(
                  label: _isEdit ? 'Save changes' : 'Record return',
                  variant: AppButtonVariant.primary,
                  block: true,
                  loading: _saving,
                  onPressed: _valid ? _save : null,
                ),
              ],
            ),
    );
  }

  Widget _passCard() {
    final pass = _gatePass;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Gate pass', style: context.texts.titleSmall),
          const SizedBox(height: 10),
          if (_loadingGatePasses)
            const AppSkeleton(height: 40)
          else ...[
            AppTextInput(
              controller: _gpSearchCtrl,
              hint: 'Search gate pass number or client…',
              icon: Icons.search,
              onChanged: (_) => setState(() {}),
              suffix: _gpSearchCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      tooltip: 'Clear search',
                      onPressed: () {
                        _gpSearchCtrl.clear();
                        setState(() {});
                      },
                    ),
            ),
            const SizedBox(height: 8),
            if (_filteredPasses.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No gate passes found',
                  style: context.texts.bodySmall
                      ?.copyWith(color: context.c.fgMuted),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _filteredPasses.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: context.c.line,
                  ),
                  itemBuilder: (_, i) {
                    final p = _filteredPasses[i];
                    final selected = pass?.id == p.id && p.id.isNotEmpty;
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      selected: selected,
                      selectedTileColor: context.c.warningSoft,
                      onTap: () => _selectPass(p),
                      title: Text(
                        p.gatePassNumber,
                        style: context.texts.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '${p.clientName} · ${p.items.length} item types · '
                        '${p.items.fold<int>(0, (s, i) => s + i.receivedQty)} pcs',
                        style: context.texts.bodySmall
                            ?.copyWith(color: context.c.fgMuted),
                      ),
                    );
                  },
                ),
              ),
          ],
          if (pass != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
              decoration: BoxDecoration(
                color: context.c.warningSoft,
                border: Border.all(color: context.c.warningBorder),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: context.texts.bodySmall,
                        children: [
                          const TextSpan(text: 'Selected: '),
                          TextSpan(
                            text: pass.gatePassNumber,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextSpan(text: ' — ${pass.clientName}'),
                        ],
                      ),
                    ),
                  ),
                  AppButton(
                    label: 'Clear',
                    size: AppButtonSize.xs,
                    variant: AppButtonVariant.ghost,
                    onPressed: _clearPass,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _deliveryCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const OpsIcon(Icons.local_shipping_outlined, tone: AppTone.info),
              const SizedBox(width: 8),
              Text('Link delivery', style: context.texts.titleSmall),
              const Spacer(),
              Text(
                'Optional',
                style:
                    context.texts.bodySmall?.copyWith(color: context.c.fgFaint),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_loadingDeliveries)
            const AppSkeleton(height: 32)
          else if (_deliveries.isEmpty)
            Text(
              'No deliveries recorded for this pass.',
              style:
                  context.texts.bodySmall?.copyWith(color: context.c.fgMuted),
            )
          else
            AppSearchableSelect<String>(
              value: _deliveryId.isEmpty ? null : _deliveryId,
              hint: 'No delivery linked',
              searchable: false,
              clearable: true,
              options: [
                for (final d in _deliveries)
                  AppSelectOption<String>(
                    value: d.id,
                    label:
                        '${d.id.isEmpty ? '—' : Fmt.truncate(d.id, 8).toUpperCase()} · '
                        '${d.deliveredBy.isEmpty ? '—' : d.deliveredBy} · '
                        '${d.items.length} items',
                  ),
              ],
              onChanged: (v) => setState(() => _deliveryId = v ?? ''),
            ),
        ],
      ),
    );
  }

  Widget _itemsCard() {
    final pass = _gatePass;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Returned items', style: context.texts.titleSmall),
              const Spacer(),
              AppButton(
                label: 'Custom item',
                size: AppButtonSize.xs,
                variant: AppButtonVariant.outline,
                icon: Icons.add,
                onPressed: _addCustomLine,
              ),
            ],
          ),
          if (pass != null && pass.items.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'From gate pass — tick items being returned:',
              style: context.texts.bodySmall?.copyWith(
                  color: context.c.fgMuted, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < pass.items.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _gatePassLineRow(pass.items[i], i),
            ],
          ],
          if (_customLines.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Custom items:',
              style: context.texts.bodySmall?.copyWith(
                  color: context.c.fgMuted, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < _customLines.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _customLineRow(i),
            ],
          ],
          if (!_hasItems) ...[
            const SizedBox(height: 12),
            Text(
              pass == null
                  ? 'Select a gate pass first, or add custom items'
                  : 'Tick items above or add a custom item',
              textAlign: TextAlign.center,
              style:
                  context.texts.bodySmall?.copyWith(color: context.c.fgMuted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _gatePassLineRow(GatePassItem item, int index) {
    final selected = _gpLines[index];
    final line = selected ?? const ReturnLine(returnedQty: 1);
    final maxQty = item.receivedQty > 0 ? item.receivedQty : 1;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: selected == null ? context.c.surface : context.c.warningSoft,
        border: Border.all(
          color: selected == null ? context.c.line : context.c.warningBorder,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => _toggleGpLine(index),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: selected != null,
                  onChanged: (_) => _toggleGpLine(index),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              item.itemName,
                              style: context.texts.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (item.specification.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            AppBadge(
                              item.specification,
                              tone: AppTone.neutral,
                              compact: true,
                            ),
                          ],
                        ],
                      ),
                      Text(
                        'Received: ${item.receivedQty} · Client: ${item.clientQty}',
                        style: context.texts.bodySmall
                            ?.copyWith(color: context.c.fgMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (selected != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: AppField(
                    label: 'Qty',
                    child: AppTextInput(
                      initialValue: '${line.returnedQty}',
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (v) {
                        final q = int.tryParse(v.trim()) ?? 1;
                        _updateGpLine(
                          index,
                          ReturnLine(
                            itemName: line.itemName,
                            specification: line.specification,
                            returnedQty: q.clamp(1, maxQty),
                            reason: line.reason,
                            condition: line.condition,
                            action: line.action,
                            notes: line.notes,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppField(
                    label: 'Reason',
                    child: AppSearchableSelect<String>(
                      value: line.reason,
                      searchable: false,
                      options: returnReasonOptions,
                      onChanged: (v) => _updateGpLine(
                        index,
                        _copyWith(line, reason: v ?? 'OTHER'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: AppField(
                    label: 'Condition',
                    child: AppSearchableSelect<String>(
                      value: line.condition,
                      searchable: false,
                      options: returnConditionOptions,
                      onChanged: (v) => _updateGpLine(
                        index,
                        _copyWith(line, condition: v ?? 'GOOD'),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppField(
                    label: 'Action',
                    child: AppSearchableSelect<String>(
                      value: line.action,
                      searchable: false,
                      options: returnActionOptions,
                      onChanged: (v) => _updateGpLine(
                        index,
                        _copyWith(line, action: v ?? 'RECEIVE_BACK'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            AppField(
              label: 'Notes',
              optional: true,
              child: AppTextInput(
                initialValue: line.notes,
                onChanged: (v) =>
                    _updateGpLine(index, _copyWith(line, notes: v)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _customLineRow(int index) {
    final line = _customLines[index];
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: context.c.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Custom item',
                style: context.texts.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: context.c.fgMuted,
                ),
              ),
              const Spacer(),
              AppButton.icon(
                icon: Icons.delete_outline,
                tooltip: 'Remove',
                size: AppButtonSize.iconSm,
                variant: AppButtonVariant.dangerGhost,
                onPressed: () => setState(() => _customLines.removeAt(index)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: AppField(
                  label: 'Item name',
                  child: AppTextInput(
                    hint: 'e.g. Towel, Bed Sheet',
                    initialValue: line.itemName,
                    onChanged: (v) => _setCustom(index, line, itemName: v),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppField(
                  label: 'Specification',
                  optional: true,
                  child: AppTextInput(
                    hint: 'e.g. White, King',
                    initialValue: line.specification,
                    onChanged: (v) => _setCustom(index, line, specification: v),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: AppField(
                  label: 'Qty',
                  child: AppTextInput(
                    initialValue: '${line.returnedQty}',
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (v) {
                      final q = int.tryParse(v.trim()) ?? 1;
                      if (q < 1) return;
                      _setCustom(index, line, returnedQty: q);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppField(
                  label: 'Reason',
                  child: AppSearchableSelect<String>(
                    value: line.reason,
                    searchable: false,
                    options: returnReasonOptions,
                    onChanged: (v) =>
                        _setCustom(index, line, reason: v ?? 'OTHER'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: AppField(
                  label: 'Condition',
                  child: AppSearchableSelect<String>(
                    value: line.condition,
                    searchable: false,
                    options: returnConditionOptions,
                    onChanged: (v) =>
                        _setCustom(index, line, condition: v ?? 'GOOD'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppField(
                  label: 'Action',
                  child: AppSearchableSelect<String>(
                    value: line.action,
                    searchable: false,
                    options: returnActionOptions,
                    onChanged: (v) =>
                        _setCustom(index, line, action: v ?? 'RECEIVE_BACK'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AppField(
            label: 'Notes',
            optional: true,
            child: AppTextInput(
              hint: 'Optional notes',
              initialValue: line.notes,
              onChanged: (v) => _setCustom(index, line, notes: v),
            ),
          ),
        ],
      ),
    );
  }

  static ReturnLine _copyWith(
    ReturnLine line, {
    int? returnedQty,
    String? reason,
    String? condition,
    String? action,
    String? notes,
  }) =>
      ReturnLine(
        itemName: line.itemName,
        specification: line.specification,
        returnedQty: returnedQty ?? line.returnedQty,
        reason: reason ?? line.reason,
        condition: condition ?? line.condition,
        action: action ?? line.action,
        notes: notes ?? line.notes,
      );

  void _setCustom(
    int index,
    ReturnLine line, {
    String? itemName,
    String? specification,
    int? returnedQty,
    String? reason,
    String? condition,
    String? action,
    String? notes,
  }) {
    setState(() {
      _customLines[index] = ReturnLine(
        itemName: itemName ?? line.itemName,
        specification: specification ?? line.specification,
        returnedQty: returnedQty ?? line.returnedQty,
        reason: reason ?? line.reason,
        condition: condition ?? line.condition,
        action: action ?? line.action,
        notes: notes ?? line.notes,
      );
    });
  }

  Widget _adjustmentCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bill adjustment', style: context.texts.titleSmall),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: AppField(
                  label: 'Type',
                  child: AppSearchableSelect<String>(
                    value: _adjustmentType,
                    searchable: false,
                    options: returnAdjustmentOptions,
                    onChanged: (v) =>
                        setState(() => _adjustmentType = v ?? 'NONE'),
                  ),
                ),
              ),
              if (_adjustmentType != 'NONE') ...[
                const SizedBox(width: 8),
                Expanded(
                  child: AppField(
                    label: 'Amount (LKR)',
                    child: AppTextInput(
                      initialValue: _adjustmentAmount == 0
                          ? ''
                          : _adjustmentAmount.toStringAsFixed(2),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (v) => setState(
                        () =>
                            _adjustmentAmount = double.tryParse(v.trim()) ?? 0,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (_adjustmentType != 'NONE') ...[
            const SizedBox(height: 8),
            AppField(
              label: 'Adjustment notes',
              optional: true,
              child: AppTextInput(
                hint: 'Reason for adjustment',
                initialValue: _adjustmentNotes,
                onChanged: (v) => setState(() => _adjustmentNotes = v),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
