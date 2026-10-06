import 'package:flutter/material.dart';

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

/// Port of `pages/create-delivery-page.tsx`.
///
/// The web form used to fire one POST per gate pass, which meant a failure
/// half-way through left some passes delivered and others not with nothing to
/// undo it. It is now a single document: every line carries its own
/// `gate_pass_id` and the server validates and stores the whole delivery
/// atomically against the balance it sees at write time. That is also why this
/// form only ever offers what `/deliveries/available` says is deliverable.
class DeliveryFormPage extends StatefulWidget {
  const DeliveryFormPage({super.key, this.deliveryId, this.gatePassId});

  final String? deliveryId;

  /// Pre-selects one source pass, so "record delivery" from a gate pass lands
  /// with that pass already ticked.
  final String? gatePassId;

  @override
  State<DeliveryFormPage> createState() => _DeliveryFormPageState();
}

class _DeliveryFormPageState extends State<DeliveryFormPage> {
  final _deliveredByCtrl = TextEditingController();
  final _receivedByCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  final Map<String, int> _quantities = {};
  final Set<String> _expanded = {};

  Availability? _available;
  String _search = '';
  DateTime _deliveryDate = Fmt.lktNow();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _fillAll = true;

  bool get _isEdit => (widget.deliveryId ?? '').isNotEmpty;

  @override
  void initState() {
    super.initState();
    _deliveredByCtrl.text = AppScope.read(context).hotels.selectedHotel;
    if (_isEdit) {
      _loadExisting();
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _deliveredByCtrl.dispose();
    _receivedByCtrl.dispose();
    _notesCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final hotel = AppScope.read(context).hotels.queryParam;
      final payload = await AppScope.read(context).api.get(
        operationsService,
        DeliveryApi.available,
        query: {if (hotel != null) 'client_name': hotel},
      );
      if (!mounted) return;
      final availability =
          Availability.fromJson(Map<String, dynamic>.from(payload as Map));
      setState(() {
        _available = availability;
        // The entry flow opens on a gate pass, so start from just that pass
        // rather than making the operator find it in the list.
        final pre = widget.gatePassId;
        for (final gp in availability.gatePasses) {
          if (pre == null || gp.gatePassId == pre) {
            _expanded.add(gp.gatePassId);
            if (pre != null && gp.gatePassId == pre) {
              for (final item in gp.items.where((i) => i.isDeliverable)) {
                _quantities[_key(item)] = item.availableQty;
              }
            }
          }
        }
        _fillAll = pre == null;
        if (_fillAll) _fillEveryPending();
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  /// The same identity the server balances on: `name||specification`.
  static String _key(AvailableItem item) =>
      '${item.itemName}||${item.specification.trim()}';

  void _fillEveryPending() {
    for (final gp in _available?.gatePasses ?? const <AvailableGatePass>[]) {
      for (final item in gp.items) {
        if (item.isDeliverable) _quantities[_key(item)] = item.availableQty;
      }
    }
  }

  void _setQty(String key, double value) =>
      setState(() => _quantities[key] = value < 0 ? 0 : value.round());

  Future<void> _loadExisting() async {
    setState(() => _loading = true);
    try {
      final payload = await AppScope.read(context)
          .api
          .get(operationsService, DeliveryApi.one(widget.deliveryId!));
      final d = Delivery.fromJson(Map<String, dynamic>.from(payload as Map));
      setState(() {
        _deliveredByCtrl.text = d.deliveredBy;
        _receivedByCtrl.text = d.receivedBy;
        _notesCtrl.text = d.notes ?? '';
        _deliveryDate = Fmt.parseDate(d.deliveryDate) ?? Fmt.lktNow();
        for (final line in d.items) {
          _quantities['${line.itemName}||${line.specification.trim()}'] =
              line.quantity;
        }
      });
      // Corrections never destroy the original quantities; the server keeps the
      // history, so the form only has to set the corrected values.
      if (mounted) await _load();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  /// One delivery belongs to exactly one hotel. A selection spanning two cannot
  /// be stored as a single document, so it is caught here rather than as a
  /// server rejection.
  List<String> get _hotels {
    final names = <String>{};
    for (final row in _activeLines) {
      final name = row.pass.clientName.trim();
      if (name.isNotEmpty) names.add(name);
    }
    return names.toList();
  }

  List<({AvailableItem item, AvailableGatePass pass})> get _activeLines {
    final out = <({AvailableItem item, AvailableGatePass pass})>[];
    for (final gp in _available?.gatePasses ?? const <AvailableGatePass>[]) {
      if (!_expanded.contains(gp.gatePassId)) continue;
      for (final item in gp.items) {
        if ((_quantities[_key(item)] ?? 0) > 0) {
          out.add((item: item, pass: gp));
        }
      }
    }
    return out;
  }

  List<DeliveryLine> get _lines => [
        for (final row in _activeLines)
          DeliveryLine(
            itemName: row.item.itemName,
            specification: row.item.specification,
            quantity: _quantities[_key(row.item)] ?? 0,
            gatePassId: row.pass.gatePassId,
          ),
      ];

  bool get _valid {
    final lines = _lines;
    if (lines.isEmpty) return false;
    if (_deliveryDate == DateTime(0)) {
      return false;
    }
    if (_deliveredByCtrl.text.trim().isEmpty) return false;
    if (_receivedByCtrl.text.trim().isEmpty) return false;
    if (_hotels.length > 1) return false;
    return true;
  }

  /// The server re-validates every line, so this is a convenience that saves a
  /// round trip, not the guarantee.
  bool get _overAllocated {
    for (final row in _activeLines) {
      if ((_quantities[_key(row.item)] ?? 0) > row.item.availableQty) {
        return true;
      }
    }
    return false;
  }

  int get _totalPieces => _lines.fold(0, (sum, l) => sum + l.quantity);

  Future<void> _save() async {
    if (!_valid) return;
    setState(() => _saving = true);
    final hotel = _hotels.isEmpty ? '' : _hotels.first;
    final lines = _lines;
    try {
      final api = AppScope.read(context).api;
      Object result;
      if (_isEdit) {
        // A recorded delivery is corrected in place, and every original value
        // is kept by the server in the correction history.
        result = await api.patch(
          operationsService,
          DeliveryApi.items(widget.deliveryId!),
          body: {
            'items': [
              for (final l in lines)
                {
                  'item_name': l.itemName,
                  if (l.specification.trim().isNotEmpty)
                    'specification': l.specification.trim(),
                  if ((l.gatePassId ?? '').isNotEmpty)
                    'gate_pass_id': l.gatePassId,
                  'quantity': l.quantity,
                },
            ],
            'reason': _notesCtrl.text.trim().isEmpty
                ? 'Quantity correction'
                : _notesCtrl.text.trim(),
          },
        );
      } else {
        result = await api.post(
          operationsService,
          DeliveryApi.list,
          body: Delivery(
            clientName: hotel,
            deliveryDate: Fmt.isoDate(_deliveryDate),
            deliveredBy: _deliveredByCtrl.text.trim(),
            receivedBy: _receivedByCtrl.text.trim(),
            notes: _notesCtrl.text.trim(),
            items: lines,
          ).createJson(),
        );
      }
      if (!mounted) return;
      QueryCacheInvalidator.instance.invalidate('deliveries');
      QueryCacheInvalidator.instance.invalidate('gatepasses');
      Navigator.of(context).pop(true);
      AppToast.success(
        context,
        result is QueuedResponse
            ? 'Saved — will sync when back online'
            : _isEdit
                ? 'Delivery corrected'
                : 'Delivery recorded',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.error(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    if (!canView(services, deliveriesPermission)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Delivery')),
        body: opsNotPermitted('deliveries'),
      );
    }
    final c = context.c;
    final passes = (_available?.gatePasses ?? const <AvailableGatePass>[])
        .where((gp) => gp.totalAvailableQty > 0)
        .toList();
    final needle = _search.trim().toLowerCase();
    final visible = passes.where((gp) {
      if (needle.isEmpty) return true;
      return '${gp.gatePassNumber} ${gp.clientName} '
              '${gp.items.map((i) => i.itemName).join(' ')}'
          .toLowerCase()
          .contains(needle);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Correct delivery' : 'Record delivery'),
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
                            onPressed: _isEdit ? _loadExisting : _load,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_hotels.length > 1) ...[
                        const AppNotice(
                          message:
                              'A single delivery cannot mix clients or hotels. '
                              'Keep the selection to one client at a time.',
                          tone: AppTone.danger,
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_overAllocated) ...[
                        const AppNotice(
                          message: 'A line is above what the server says is '
                              'available. It will be rejected on save.',
                          tone: AppTone.warning,
                        ),
                        const SizedBox(height: 12),
                      ],
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: AppField(
                              label: 'Delivery date',
                              required: true,
                              child: AppDateField(
                                value: _deliveryDate,
                                onChanged: (d) {
                                  if (d != null) {
                                    setState(() => _deliveryDate = d);
                                  }
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: AppField(
                              label: 'Delivered by',
                              required: true,
                              child: AppTextInput(
                                controller: _deliveredByCtrl,
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AppField(
                        label: 'Received by (at the hotel)',
                        required: true,
                        child: AppTextInput(
                          controller: _receivedByCtrl,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'What is deliverable',
                              style: context.texts.titleSmall,
                            ),
                          ),
                          AppButton(
                            label: _fillAll ? 'Clear all' : 'Fill all',
                            size: AppButtonSize.xs,
                            variant: AppButtonVariant.ghost,
                            icon: _fillAll ? Icons.clear_all : Icons.done_all,
                            onPressed: () {
                              setState(() {
                                if (_fillAll) {
                                  _quantities.clear();
                                } else {
                                  _fillEveryPending();
                                }
                                _fillAll = !_fillAll;
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Only what the server reports as available. Totals below '
                        'are the numbers it will accept.',
                        style:
                            context.texts.bodySmall?.copyWith(color: c.fgMuted),
                      ),
                      const SizedBox(height: 10),
                      AppTextInput(
                        controller: _searchCtrl,
                        hint: 'Search by gate pass, client, item…',
                        icon: Icons.search,
                        onChanged: (v) => setState(() => _search = v),
                      ),
                      const SizedBox(height: 10),
                      if (passes.isEmpty)
                        const AppEmptyState(
                          title: 'Nothing is deliverable',
                          message:
                              'No gate pass has an outstanding balance for this '
                              'hotel. Everything received has already gone out.',
                          icon: Icons.inventory_2_outlined,
                          compact: true,
                        )
                      else if (visible.isEmpty)
                        const AppEmptyState(
                          title: 'No matches',
                          message: 'Try a different search.',
                          icon: Icons.search_off_outlined,
                          compact: true,
                        )
                      else
                        for (final gp in visible) ...[
                          _passCard(gp),
                          const SizedBox(height: 8),
                        ],
                      const SizedBox(height: 4),
                      AppField(
                        label: 'Notes',
                        optional: true,
                        child: AppTextInput(
                          controller: _notesCtrl,
                          maxLines: 2,
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
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_lines.length} lines · ${Fmt.qty(_totalPieces)} pcs',
                                style: context.texts.bodySmall
                                    ?.copyWith(color: c.fgMuted),
                              ),
                              if (_hotels.isNotEmpty)
                                Text(
                                  _hotels.length == 1
                                      ? _hotels.first
                                      : '${_hotels.length} hotels selected',
                                  style: context.texts.bodySmall?.copyWith(
                                      color: _hotels.length == 1
                                          ? c.fgMuted
                                          : c.danger),
                                ),
                            ],
                          ),
                        ),
                        AppButton(
                          label:
                              _isEdit ? 'Save correction' : 'Record delivery',
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

  Widget _passCard(AvailableGatePass gp) {
    final c = context.c;
    final open = _expanded.contains(gp.gatePassId);
    final picked = gp.items
        .where((i) => (_quantities[_key(i)] ?? 0) > 0)
        .fold<int>(0, (sum, i) => sum + (_quantities[_key(i)] ?? 0));
    return AppCard(
      padding: EdgeInsets.zero,
      onTap: () => setState(() {
        if (open) {
          _expanded.remove(gp.gatePassId);
        } else {
          _expanded.add(gp.gatePassId);
        }
      }),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        gp.gatePassNumber.isEmpty ? '—' : gp.gatePassNumber,
                        style: context.texts.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${gp.clientName} · ${Fmt.date(gp.receivingDate)}',
                        style:
                            context.texts.bodySmall?.copyWith(color: c.fgMuted),
                      ),
                    ],
                  ),
                ),
                if (picked > 0)
                  AppBadge(
                    '${Fmt.qty(picked)} of ${Fmt.qty(gp.totalAvailableQty)}',
                    tone: AppTone.success,
                    compact: true,
                  ),
                Icon(open ? Icons.expand_less : Icons.expand_more, size: 20),
              ],
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  for (final item in gp.items) ...[
                    _itemRow(gp, item),
                    if (item != gp.items.last) const Divider(height: 12),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _itemRow(AvailableGatePass gp, AvailableItem item) {
    final c = context.c;
    final key = _key(item);
    final qty = _quantities[key] ?? 0;
    final over = qty > item.availableQty;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.specification.isEmpty
                    ? item.itemName
                    : '${item.itemName} — ${item.specification}',
                style: context.texts.bodyMedium,
              ),
              Text(
                '${Fmt.qty(item.availableQty)} available of '
                '${Fmt.qty(item.receivedQty)} received'
                '${item.rewashed ? ' · re-wash' : ''}',
                style: context.texts.bodySmall?.copyWith(
                  color: over ? c.danger : c.fgMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 116,
          child: QtyStepper(
            value: qty.toDouble(),
            max: item.availableQty.toDouble(),
            onChanged: (v) => _setQty(key, v),
          ),
        ),
      ],
    );
  }
}
