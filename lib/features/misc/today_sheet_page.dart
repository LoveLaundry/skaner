import 'package:flutter/material.dart';

import '../../../config/api_config.dart';
import '../../../state/app_scope.dart';

/// One-screen daily entry — the mobile port of the web `/today-sheet`.
///
/// Every shop is a card with received and delivered line editors; delivery
/// lines default to AUTO (server-side FIFO across open gate passes) or a
/// specific source pass. Expenses at the bottom allocate per shop or shared.
/// One "Save Day" posts `/today-sheet/commit` then the expense lines.
class TodaySheetPage extends StatefulWidget {
  const TodaySheetPage({super.key});

  @override
  State<TodaySheetPage> createState() => _TodaySheetPageState();
}

class _RecvLine {
  final TextEditingController item = TextEditingController();
  final TextEditingController spec = TextEditingController();
  final TextEditingController qty = TextEditingController();
  final TextEditingController unit = TextEditingController(text: 'pcs');
}

class _DelLine {
  final TextEditingController item = TextEditingController();
  final TextEditingController spec = TextEditingController();
  final TextEditingController qty = TextEditingController();
  String gatePassId = ''; // '' = AUTO/FIFO
  _DelLine();
}

class _ExpLine {
  final TextEditingController category = TextEditingController();
  final TextEditingController amount = TextEditingController();
  String clientName = ''; // '' = shared
  _ExpLine();
}

class _ClientDraft {
  final List<_RecvLine> receives = [];
  final List<_DelLine> deliveries = [];
  final TextEditingController receivedBy = TextEditingController();
}

class _TodaySheetPageState extends State<TodaySheetPage> {
  final String _date = _isoToday();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _clients = [];
  final Map<String, _ClientDraft> _drafts = {};
  final List<_ExpLine> _expenses = [_ExpLine()];
  List<Map<String, dynamic>> _recordedExpenses = const [];
  bool _saving = false;

  static String _isoToday() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${two(n.month)}-${two(n.day)}';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = AppScope.read(context);
      final data = await s.api.get(
        ServiceNames.bills,
        '/today-sheet',
        query: {'date': _date},
      );
      if (!mounted) return;
      final clients = (data is Map<String, dynamic> ? data['clients'] : null);
      _clients = (clients is List)
          ? clients.whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[];
      _drafts.clear();
      for (final c in _clients) {
        final name = (c['client_name'] ?? '').toString();
        final draft = _ClientDraft();
        // Pre-fill delivered lines from deliverable inventory so the operator
        // only types quantities; AUTO stays the default source.
        final passes = c['pending_passes'];
        if (passes is List) {
          for (final p in passes.whereType<Map<String, dynamic>>()) {
            final items = p['deliverable_items'];
            if (items is List) {
              for (final i in items.whereType<Map<String, dynamic>>()) {
                final line = _DelLine();
                line.item.text = (i['item_name'] ?? '').toString();
                line.spec.text = (i['specification'] ?? '').toString();
                draft.deliveries.add(line);
              }
            }
          }
        }
        _drafts[name] = draft;
      }
      try {
        final expData = await s.api.get(
          ServiceNames.management,
          '/api/expenses',
          query: {'start_date': _date, 'end_date': _date, 'limit': 200},
        );
        final items = expData is Map<String, dynamic> ? expData['items'] : null;
        _recordedExpenses = items is List
            ? items.whereType<Map<String, dynamic>>().toList()
            : const [];
      } catch (_) {
        _recordedExpenses = const [];
      }
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load the today sheet.';
      });
    }
  }

  _ClientDraft _draftFor(String name) =>
      _drafts.putIfAbsent(name, _ClientDraft.new);

  List<String> _itemNames() {
    final names = <String>{};
    for (final c in _clients) {
      for (final key in ['pending_passes', 'receives']) {
        final list = c[key];
        if (list is! List) continue;
        for (final row in list.whereType<Map<String, dynamic>>()) {
          final items = row['items'] ?? row['deliverable_items'];
          if (items is List) {
            for (final i in items.whereType<Map<String, dynamic>>()) {
              final n = (i['item_name'] ?? '').toString().trim();
              if (n.isNotEmpty) names.add(n);
            }
          }
        }
      }
    }
    return names.toList()..sort();
  }

  Future<void> _save() async {
    final s = AppScope.read(context);
    final receives = <Map<String, dynamic>>[];
    final deliveries = <Map<String, dynamic>>[];

    for (final c in _clients) {
      final name = (c['client_name'] ?? '').toString();
      final d = _draftFor(name);
      final rItems = d.receives
          .where((l) => l.item.text.trim().isNotEmpty && double.tryParse(l.qty.text) != null && double.parse(l.qty.text) > 0)
          .map((l) => {
                'item_name': l.item.text.trim(),
                'specification': l.spec.text.trim().isEmpty ? null : l.spec.text.trim(),
                'unit': l.unit.text.trim().isEmpty ? null : l.unit.text.trim(),
                'quantity': double.parse(l.qty.text),
              })
          .toList();
      if (rItems.isNotEmpty) {
        receives.add({'client_name': name, 'items': rItems});
      }
      final dItems = d.deliveries
          .where((l) => l.item.text.trim().isNotEmpty && double.tryParse(l.qty.text) != null && double.parse(l.qty.text) > 0)
          .map((l) => {
                'item_name': l.item.text.trim(),
                'specification': l.spec.text.trim().isEmpty ? null : l.spec.text.trim(),
                'quantity': double.parse(l.qty.text),
                if (l.gatePassId.isNotEmpty) 'gate_pass_id': l.gatePassId,
              })
          .toList();
      if (dItems.isNotEmpty) {
        deliveries.add({
          'client_name': name,
          'items': dItems,
          if (d.receivedBy.text.trim().isNotEmpty) 'received_by': d.receivedBy.text.trim(),
        });
      }
    }

    final expItems = _expenses
        .where((e) => e.category.text.trim().isNotEmpty && double.tryParse(e.amount.text) != null && double.parse(e.amount.text) > 0)
        .toList();

    if (receives.isEmpty && deliveries.isEmpty && expItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing entered yet')),
      );
      return;
    }

    setState(() => _saving = true);
    var failures = 0;
    try {
      if (receives.isNotEmpty || deliveries.isNotEmpty) {
        final res = await s.api.post(ServiceNames.bills, '/today-sheet/commit',
            body: {'date': _date, 'receives': receives, 'deliveries': deliveries});
        final results = res is Map<String, dynamic> ? res['results'] : null;
        if (results is List) {
          failures += results.where((r) => r is Map && r['ok'] == false).length;
        }
      }
      for (final e in expItems) {
        try {
          await s.api.post(ServiceNames.management, '/api/expenses', body: {
            'date': _date,
            'category_name': e.category.text.trim(),
            'amount': double.parse(e.amount.text),
            'client_name': e.clientName.isEmpty ? null : e.clientName,
            'allocation': e.clientName.isEmpty ? 'SHARED' : 'SHOP',
          });
        } catch (_) {
          failures++;
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(failures == 0 ? 'Day saved' : '$failures row(s) failed — check entries'),
      ));
      if (failures == 0) _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed — please retry')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemNames = _itemNames();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Today Sheet'),
        actions: [
          IconButton(
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            tooltip: 'Save Day',
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      Text('$_date — enter received & delivered per shop, then Save Day',
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 8),
                      for (final c in _clients) _clientCard(c, itemNames),
                      if (_clients.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: Text('No active shops for this day')),
                        ),
                      _expensesCard(),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _save,
        icon: const Icon(Icons.save_outlined),
        label: const Text('Save Day'),
      ),
    );
  }

  Widget _clientCard(Map<String, dynamic> c, List<String> itemNames) {
    final name = (c['client_name'] ?? '').toString();
    final d = _draftFor(name);
    final passes = (c['pending_passes'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .where((p) => ((p['total_available_qty'] as num?) ?? 0) > 0)
            .toList() ??
        const <Map<String, dynamic>>[];
    final avail = (c['available_qty'] as num?)?.toStringAsFixed(0) ?? '0';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(name,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                ),
                Text('$avail on hand',
                    style: const TextStyle(fontSize: 11, color: Colors.black54)),
              ],
            ),
            TextField(
              controller: d.receivedBy,
              decoration: const InputDecoration(
                hintText: 'Client rep (delivery sign-off)',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            _sectionLabel('Received today'),
            for (final l in d.receives) _recvRow(l, itemNames, () => setState(() => d.receives.remove(l))),
            TextButton.icon(
              onPressed: () => setState(() => d.receives.add(_RecvLine())),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add received line'),
            ),
            const SizedBox(height: 4),
            _sectionLabel('Delivered today'),
            for (final l in d.deliveries)
              _delRow(l, itemNames, passes, () => setState(() => d.deliveries.remove(l))),
            TextButton.icon(
              onPressed: () => setState(() => d.deliveries.add(_DelLine())),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add delivered line'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 2),
        child: Text(text.toUpperCase(),
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.black45, letterSpacing: 0.5)),
      );

  Widget _field(TextEditingController ctrl, String hint,
      {double? width, TextInputType? keyboard, List<String>? suggestions}) {
    final decoration = InputDecoration(
      hintText: hint,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
    );
    Widget field = TextField(
      controller: ctrl,
      keyboardType: keyboard,
      decoration: decoration,
    );
    if (suggestions != null && suggestions.isNotEmpty) {
      field = Autocomplete<String>(
        optionsBuilder: (v) => v.text.trim().isEmpty
            ? const Iterable<String>.empty()
            : suggestions.where((n) => n.toLowerCase().contains(v.text.toLowerCase())),
        onSelected: (v) => ctrl.text = v,
        fieldViewBuilder: (_, textCtrl, focus, onSubmit) {
          // Keep the caller's controller as the source of truth.
          if (textCtrl.text != ctrl.text) {
            textCtrl.value = ctrl.value;
          }
          return TextField(
            controller: textCtrl,
            focusNode: focus,
            keyboardType: keyboard,
            decoration: decoration,
            onChanged: (v) => ctrl.text = v,
          );
        },
      );
    }
    return SizedBox(width: width, child: field);
  }

  Widget _recvRow(_RecvLine l, List<String> itemNames, VoidCallback onRemove) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(flex: 3, child: _field(l.item, 'Item', suggestions: itemNames)),
          const SizedBox(width: 6),
          Expanded(flex: 2, child: _field(l.spec, 'Spec')),
          const SizedBox(width: 6),
          SizedBox(width: 64, child: _field(l.qty, 'Qty', keyboard: TextInputType.number)),
          const SizedBox(width: 6),
          SizedBox(width: 56, child: _field(l.unit, 'Unit')),
          IconButton(icon: const Icon(Icons.close, size: 16), onPressed: onRemove),
        ],
      ),
    );
  }

  Widget _delRow(_DelLine l, List<String> itemNames, List<Map<String, dynamic>> passes, VoidCallback onRemove) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(flex: 3, child: _field(l.item, 'Item', suggestions: itemNames)),
              const SizedBox(width: 6),
              Expanded(flex: 2, child: _field(l.spec, 'Spec')),
              const SizedBox(width: 6),
              SizedBox(width: 70, child: _field(l.qty, 'Qty', keyboard: TextInputType.number)),
              const SizedBox(width: 6),
              IconButton(icon: const Icon(Icons.close, size: 16), onPressed: onRemove),
            ],
          ),
          DropdownButtonFormField<String>(
            initialValue: l.gatePassId,
            isDense: true,
            decoration: const InputDecoration(
              labelText: 'Source pass (AUTO = FIFO)',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(value: '', child: Text('AUTO · FIFO')),
              for (final p in passes)
                DropdownMenuItem(
                  value: (p['gate_pass_id'] ?? '').toString(),
                  child: Text('${p['gate_pass_number']} · ${p['total_available_qty']} left',
                      overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() => l.gatePassId = v ?? ''),
          ),
        ],
      ),
    );
  }

  Widget _expensesCard() {
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_recordedExpenses.isNotEmpty) ...[
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ALREADY RECORDED TODAY (${_recordedExpenses.length})',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.black45, letterSpacing: 0.5)),
                    for (final e in _recordedExpenses)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                (e['category_name'] ?? e['description'] ?? 'Expense').toString(),
                                style: const TextStyle(fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '${e['allocation'] == 'SHOP' && (e['client_name'] ?? '').toString().isNotEmpty ? '${e['client_name']} · ' : ''}LKR ${e['amount'] ?? 0}',
                              style: const TextStyle(fontSize: 11, color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            Row(
              children: [
                const Expanded(
                  child: Text('EXPENSES TODAY',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.black45, letterSpacing: 0.5)),
                ),
                TextButton.icon(
                  onPressed: () => setState(() => _expenses.add(_ExpLine())),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add expense'),
                ),
              ],
            ),
            for (final e in _expenses)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(flex: 3, child: _field(e.category, 'Category (Electricity, Water…)')),
                    const SizedBox(width: 6),
                    SizedBox(width: 90, child: _field(e.amount, 'Amount', keyboard: TextInputType.number)),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        initialValue: e.clientName,
                        isDense: true,
                        decoration: const InputDecoration(
                          labelText: 'Allocate to',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(value: '', child: Text('Shared')),
                          for (final c in _clients)
                            DropdownMenuItem(
                              value: (c['client_name'] ?? '').toString(),
                              child: Text((c['client_name'] ?? '').toString(), overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged: (v) => setState(() => e.clientName = v ?? ''),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () => setState(() => _expenses.remove(e)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
