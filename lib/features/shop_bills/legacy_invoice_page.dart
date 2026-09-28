import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:printing/printing.dart';

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

/// Port of `features/shop-bills/pages/legacy-invoice-page.tsx`.
///
/// This is the paper-bill aggregator: an operator types the old bill dates,
/// numbers and amounts from a client's paper file, saves them as a
/// [LegacyInvoice], and prints a consolidated sheet. The signature is captured
/// on the device at print time and only ever lives in the printed output — the
/// stored invoice keeps the money, never the ink.
class LegacyInvoicePage extends StatefulWidget {
  const LegacyInvoicePage({super.key});

  @override
  State<LegacyInvoicePage> createState() => _LegacyInvoicePageState();
}

class _LegacyInvoicePageState extends State<LegacyInvoicePage> {
  final _shopName = TextEditingController();
  final _description = TextEditingController();
  final _searchCtrl = TextEditingController();

  late final ResourceController<List<Map<String, dynamic>>> _controller;

  final List<_EntryDraft> _rows = [_EntryDraft()];
  Map<String, dynamic>? _saved;
  String _search = '';
  bool _saving = false;
  bool _printing = false;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _controller = ResourceController(
      key: 'legacy-invoices',
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
    _shopName.dispose();
    _description.dispose();
    _searchCtrl.dispose();
    for (final row in _rows) {
      row.dispose();
    }
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
      ShopBillApi.legacy(),
      query: {if (_search.isNotEmpty) 'search': _search},
    );
    return asRows(payload);
  }

  Future<void> _reload() => _controller.load(force: true);

  List<Map<String, dynamic>> get _invoices => _controller.data ?? const [];

  /// Only rows that carry something are real entries — the React page applies
  /// the same filter before posting, so the grand total always matches the
  /// server's `total_entries`.
  List<Map<String, dynamic>> get _entries {
    final rows = <Map<String, dynamic>>[];
    for (final row in _rows) {
      final billNumber = row.billNumber.text.trim();
      final amount = row.parsedAmount;
      if (billNumber.isEmpty && amount <= 0) continue;
      rows.add({
        if (row.date != null) 'date': Fmt.isoDate(row.date!),
        if (billNumber.isNotEmpty) 'bill_number': billNumber,
        'amount': amount,
      });
    }
    return rows;
  }

  double get _grandTotal =>
      _entries.fold<double>(0, (sum, e) => sum + numOf(e, const ['amount']));

  bool get _canSave =>
      _shopName.text.trim().isNotEmpty &&
      _entries.isNotEmpty &&
      _grandTotal > 0 &&
      !_saving;

  void _addRow() => setState(() => _rows.add(_EntryDraft()));

  void _removeRow(int index) {
    if (_rows.length <= 1) return;
    final removed = _rows.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  void _clearForm() {
    _shopName.clear();
    _description.clear();
    for (final row in _rows) {
      row.dispose();
    }
    _rows
      ..clear()
      ..add(_EntryDraft());
    setState(() => _saved = null);
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    final services = AppScope.read(context);
    try {
      final payload = await services.api.post(
        ServiceNames.bills,
        ShopBillApi.legacy(),
        body: {
          'shop_name': _shopName.text.trim(),
          if (_description.text.trim().isNotEmpty)
            'description': _description.text.trim(),
          'entries': _entries,
        },
      );
      if (!mounted) return;
      final invoice = asMap(payload);
      setState(() {
        _saved = invoice;
        _saving = false;
      });
      if (payload is QueuedResponse) {
        setState(() => _saving = false);
        AppToast.info(context, 'Queued — will sync when you are back online');
      } else {
        AppToast.success(
          context,
          'Invoice ${str(invoice, const ['invoice_number'], '')} saved',
        );
        _clearForm();
        setState(() => _saved = invoice);
      }
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.error(context, e.message);
    }
  }

  Future<void> _delete(Map<String, dynamic> invoice) async {
    final id = str(invoice, const ['id']);
    if (id.isEmpty) return;
    final ok = await AppConfirmDialog.show(
      context,
      title: 'Delete legacy invoice?',
      message: 'Invoice ${str(invoice, const ['invoice_number'], '')} and its '
          'entries will be removed permanently.',
      confirmLabel: 'Delete',
      destructive: true,
      icon: Icons.delete_outline,
    );
    if (!ok || !mounted) return;
    setState(() => _busyId = id);
    final services = AppScope.read(context);
    try {
      final result =
          await services.api.delete(ServiceNames.bills, ShopBillApi.legacyOne(id));
      if (!mounted) return;
      if (result is QueuedResponse) {
        AppToast.info(context, 'Queued — will sync when you are back online');
      } else {
        AppToast.success(context, 'Invoice deleted');
        if (_saved != null && str(_saved!, const ['id']) == id) {
          setState(() => _saved = null);
        }
        _reload();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      AppToast.error(context, e.message);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  /// Prints the saved invoice, asking for the laundry signature first — the
  /// React page does the same: capture the signature, then print.
  Future<void> _print(Map<String, dynamic> invoice) async {
    final signature = await _askSignature();
    if (signature == null || !mounted) return;
    setState(() => _printing = true);
    try {
      await Printing.layoutPdf(
        onLayout: (_) => _render(invoice, signature),
        name: 'Invoice-${str(invoice, const ['shop_name'], 'Invoice')}',
      );
      if (!mounted) return;
      AppToast.success(context, 'Sent to printer');
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Could not print: $e');
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  /// `null` means the operator cancelled; an empty string means "print with no
  /// signature", which is a legitimate choice for a reprint.
  Future<String?> _askSignature() {
    String? data;
    return AppDialog.show<String>(
      context,
      title: 'Laundry sign',
      icon: Icons.draw_outlined,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sign before printing. Leave blank to reprint without a signature.',
            style: context.texts.bodySmall?.copyWith(color: context.c.fgMuted),
          ),
          const SizedBox(height: 10),
          AppSignaturePad(
            onChanged: (v) => data = v,
            height: 150,
          ),
        ],
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: 'Print',
          variant: AppButtonVariant.primary,
          icon: Icons.print_outlined,
          onPressed: () => Navigator.of(context).pop(data ?? ''),
        ),
      ],
    );
  }

  /// Rasterises the off-screen [LegacySheet] so the print output is exactly the
  /// preview the operator saw.
  Future<Uint8List> _render(
    Map<String, dynamic> invoice,
    String signature,
  ) async {
    final bytes = await showDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      builder: (_) => _PrintHost(invoice: invoice, signature: signature),
    );
    return bytes ?? Uint8List(0);
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final c = context.c;
    if (!services.auth.hasPermission(shopBillsPermission)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Legacy invoice')),
        body: const AppErrorState(
          title: 'Not permitted',
          message: 'You do not have access to shop bills.',
          icon: Icons.lock_outline,
        ),
      );
    }

    final invoices = _invoices;
    final loading = _controller.isLoading && invoices.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Legacy invoice'),
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
            label: 'Legacy invoices',
          ),
          AppOfflineSyncBar(engine: services.sync),
          Expanded(
            child: RefreshIndicator(
              color: c.brand,
              onRefresh: _reload,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                children: [
                  const _LegacyBanner(),
                  if (_saved != null) ...[
                    const SizedBox(height: 12),
                    _SavedBanner(
                      invoice: _saved!,
                      onPrint: () => _print(_saved!),
                      onNew: _clearForm,
                    ),
                  ],
                  const SizedBox(height: 14),
                  AppCard(
                    title: 'New legacy invoice',
                    subtitle: 'Aggregate old paper bills, save, then print.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppField(
                          label: 'Shop / hotel name',
                          required: true,
                          child: AppTextInput(
                            controller: _shopName,
                            hint: 'Enter shop or hotel name',
                            icon: Icons.storefront_outlined,
                            textCapitalization: TextCapitalization.words,
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(height: 12),
                        AppField(
                          label: 'Description',
                          optional: true,
                          child: AppTextInput(
                            controller: _description,
                            hint: 'e.g. Laundry services for July 2026',
                            maxLines: 2,
                            textCapitalization: TextCapitalization.sentences,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Bill entries',
                                style: context.texts.titleSmall,
                              ),
                            ),
                            Text(
                              '${_entries.length} of ${_rows.length}',
                              style: context.texts.labelSmall
                                  ?.copyWith(color: c.fgFaint),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Old bill date, number and amount. Blank rows are ignored.',
                          style: context.texts.labelSmall
                              ?.copyWith(color: c.fgMuted),
                        ),
                        const SizedBox(height: 10),
                        _EntryHeader(),
                        for (var i = 0; i < _rows.length; i++) ...[
                          const SizedBox(height: 6),
                          _EntryRow(
                            index: i,
                            draft: _rows[i],
                            canRemove: _rows.length > 1,
                            onRemove: () => _removeRow(i),
                            onChanged: () => setState(() {}),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: AppButton(
                            label: 'Add entry',
                            size: AppButtonSize.sm,
                            variant: AppButtonVariant.outline,
                            icon: Icons.add,
                            onPressed: _addRow,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TotalRow(
                          'Grand total',
                          Fmt.money(_grandTotal),
                          strong: true,
                          accent: true,
                        ),
                        const SizedBox(height: 14),
                        AppButton(
                          label: 'Save invoice',
                          variant: AppButtonVariant.primary,
                          size: AppButtonSize.lg,
                          expand: true,
                          icon: Icons.save_outlined,
                          loading: _saving,
                          onPressed: _canSave ? _save : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  AppCard(
                    title: 'Saved invoices',
                    subtitle:
                        'Every legacy invoice you create is stored and can '
                        'be reprinted anytime.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppTextInput(
                          controller: _searchCtrl,
                          hint: 'Search by shop / hotel…',
                          icon: Icons.search,
                          textInputAction: TextInputAction.search,
                          onChanged: (v) => setState(() => _search = v.trim()),
                          onSubmitted: (_) => _reload(),
                        ),
                        const SizedBox(height: 12),
                        if (loading)
                          const AppSkeletonList()
                        else if (invoices.isEmpty)
                          const AppEmptyState(
                            title: 'No legacy invoices',
                            message: 'Saved paper bills appear here.',
                            icon: Icons.description_outlined,
                          )
                        else
                          for (final invoice in invoices)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _SavedRow(
                                invoice: invoice,
                                busy: _busyId == str(invoice, const ['id']),
                                printing: _printing,
                                onLoad: () => setState(() => _saved = invoice),
                                onPrint: () => _print(invoice),
                                onDelete: () => _delete(invoice),
                              ),
                            ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One editable legacy-bill row. Mirrors `InvoiceRow` in the React page.
class _EntryDraft {
  final billNumber = TextEditingController();
  final amount = TextEditingController();
  DateTime? date = DateTime.now();

  double get parsedAmount =>
      double.tryParse(amount.text.replaceAll(',', '').trim()) ?? 0;

  void dispose() {
    billNumber.dispose();
    amount.dispose();
  }
}

class _LegacyBanner extends StatelessWidget {
  const _LegacyBanner();

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.c.brandSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.local_laundry_service_outlined,
                  size: 20, color: context.c.brand),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'LOVE LAUNDRY',
                    style: context.texts.titleSmall?.copyWith(
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'and dry cleaning experts',
                    style: context.texts.labelSmall
                        ?.copyWith(color: context.c.fgMuted),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Legacy Invoice — aggregate old paper bills, save, then print.',
                    style: context.texts.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _SavedBanner extends StatelessWidget {
  const _SavedBanner({
    required this.invoice,
    required this.onPrint,
    required this.onNew,
  });

  final Map<String, dynamic> invoice;
  final VoidCallback onPrint;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) => AppCard(
        accent: true,
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline,
                size: 20, color: context.c.success),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Invoice ${str(invoice, const [
                          'invoice_number'
                        ], '')} saved',
                    style: context.texts.titleSmall,
                  ),
                  Text(
                    'Ready to print or reopen below.',
                    style: context.texts.labelSmall
                        ?.copyWith(color: context.c.fgMuted),
                  ),
                ],
              ),
            ),
            AppButton(
              label: 'Print',
              size: AppButtonSize.sm,
              variant: AppButtonVariant.outline,
              icon: Icons.print_outlined,
              onPressed: onPrint,
            ),
            const SizedBox(width: 6),
            AppButton(
              label: 'New',
              size: AppButtonSize.sm,
              variant: AppButtonVariant.ghost,
              onPressed: onNew,
            ),
          ],
        ),
      );
}

class _EntryHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final style = context.texts.labelSmall?.copyWith(
      color: context.c.fgFaint,
      letterSpacing: 0.6,
    );
    return Row(
      children: [
        Expanded(flex: 4, child: Text('BILL DATE', style: style)),
        const SizedBox(width: 8),
        Expanded(flex: 4, child: Text('BILL NUMBER', style: style)),
        const SizedBox(width: 8),
        Expanded(flex: 3, child: Text('AMOUNT', style: style)),
        const SizedBox(width: 36),
      ],
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.index,
    required this.draft,
    required this.canRemove,
    required this.onRemove,
    required this.onChanged,
  });

  final int index;
  final _EntryDraft draft;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 4,
            child: AppDateField(
              value: draft.date,
              onChanged: (v) {
                draft.date = v;
                onChanged();
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: AppTextInput(
              controller: draft.billNumber,
              hint: 'e.g. BL-001',
              textInputAction: TextInputAction.next,
              onChanged: (_) => onChanged(),
              onSubmitted: (_) {
                // The React grid moves to the next field on Enter and appends a
                // row on the last one; appending only from the last row keeps
                // that shortcut without trapping the operator.
                onChanged();
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: AppMoneyInput(
              controller: draft.amount,
              onChanged: (_) => onChanged(),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 32,
            height: 32,
            child: canRemove
                ? IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    tooltip: 'Remove entry ${index + 1}',
                    onPressed: onRemove,
                  )
                : null,
          ),
        ],
      );
}

class _SavedRow extends StatelessWidget {
  const _SavedRow({
    required this.invoice,
    required this.busy,
    required this.printing,
    required this.onLoad,
    required this.onPrint,
    required this.onDelete,
  });

  final Map<String, dynamic> invoice;
  final bool busy;
  final bool printing;
  final VoidCallback onLoad;
  final VoidCallback onPrint;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        decoration: BoxDecoration(
          color: context.c.surface2,
          border: Border.all(color: context.c.line),
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    str(invoice, const ['shop_name', 'client_name'], '—'),
                    style: context.texts.titleSmall,
                  ),
                  Text(
                    [
                      'No. ${str(invoice, const ['invoice_number'], '—')}',
                      '${Fmt.count(intOf(invoice, const [
                            'total_entries'
                          ]))} entries',
                      Fmt.money(numOf(invoice, const ['grand_total'])),
                    ].join(' · '),
                    style: context.texts.labelSmall
                        ?.copyWith(color: context.c.fgMuted),
                  ),
                  if (str(invoice, const ['description']).trim().isNotEmpty)
                    Text(
                      str(invoice, const ['description']),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.bodySmall,
                    ),
                ],
              ),
            ),
            AppButton.icon(
              icon: Icons.visibility_outlined,
              tooltip: 'Open',
              size: AppButtonSize.sm,
              onPressed: onLoad,
            ),
            AppButton.icon(
              icon: Icons.print_outlined,
              tooltip: 'Print',
              size: AppButtonSize.sm,
              loading: printing,
              onPressed: onPrint,
            ),
            AppButton.icon(
              icon: Icons.delete_outline,
              tooltip: 'Delete',
              size: AppButtonSize.sm,
              variant: AppButtonVariant.ghost,
              loading: busy,
              onPressed: onDelete,
            ),
          ],
        ),
      );
}

/// Hosts the printable sheet off-screen and resolves with its bytes.
///
/// `Printing.layoutPdf` needs bytes synchronously from `onLayout`, and Flutter
/// has no synchronous widget pump, so the sheet is measured in a real (but
/// transparent, non-dismissible) route first.
class _PrintHost extends StatefulWidget {
  const _PrintHost({required this.invoice, required this.signature});

  final Map<String, dynamic> invoice;
  final String signature;

  @override
  State<_PrintHost> createState() => _PrintHostState();
}

class _PrintHostState extends State<_PrintHost> {
  final GlobalKey _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
  }

  Future<void> _capture() async {
    final boundary =
        _key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null || !mounted) return;
    final image = await boundary.toImage(pixelRatio: 3.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (!mounted) return;
    final bytes = data?.buffer.asUint8List() ?? Uint8List(0);
    Navigator.of(context).pop(bytes);
  }

  @override
  Widget build(BuildContext context) => Center(
        child: RepaintBoundary(
          key: _key,
          child: _LegacySheet(
            invoice: widget.invoice,
            signature: widget.signature,
          ),
        ),
      );
}

class _LegacySheet extends StatelessWidget {
  const _LegacySheet({required this.invoice, required this.signature});

  final Map<String, dynamic> invoice;
  final String signature;

  static const _ink = Color(0xFF101828);
  static const _muted = Color(0xFF98A2B3);
  static const _rule = Color(0xFFE4E7EC);

  static List<Map<String, dynamic>> entriesOf(Map<String, dynamic> invoice) {
    final raw = pick(invoice, const ['entries']);
    if (raw is List) return asRows(raw);
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final entries = entriesOf(invoice);
    final total = numOf(invoice, const ['grand_total']);
    final description = str(invoice, const ['description']);
    final number = str(invoice, const ['invoice_number']);

    return Container(
      width: 420,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
      child: DefaultTextStyle(
        style: const TextStyle(color: _ink, fontSize: 11.5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'LOVE LAUNDRY',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                          color: _ink,
                        ),
                      ),
                      const Text(
                        'and dry cleaning experts',
                        style: TextStyle(color: _muted, fontSize: 10.5),
                      ),
                    ],
                  ),
                ),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'INVOICE',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.6,
                        color: _ink,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text('Invoice No:',
                        style: TextStyle(color: _muted, fontSize: 10)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                number.isEmpty ? '—' : number,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
            const SizedBox(height: 16),
            Container(height: 1, color: _rule),
            const SizedBox(height: 12),
            _SheetField('Bill To', str(invoice, const ['shop_name'], '—')),
            if (description.trim().isNotEmpty)
              _SheetField('Description', description),
            const SizedBox(height: 14),
            Row(
              children: [
                const Expanded(
                  flex: 4,
                  child: Text('BILL DATE',
                      style: TextStyle(
                          fontSize: 9.5,
                          letterSpacing: 0.8,
                          color: _muted,
                          fontWeight: FontWeight.w700)),
                ),
                const Expanded(
                  flex: 4,
                  child: Text('BILL NUMBER',
                      style: TextStyle(
                          fontSize: 9.5,
                          letterSpacing: 0.8,
                          color: _muted,
                          fontWeight: FontWeight.w700)),
                ),
                Expanded(
                  flex: 3,
                  child: Text('AMOUNT',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 9.5,
                          letterSpacing: 0.8,
                          color: _muted,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(height: 1, color: _rule),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No entries.', style: TextStyle(color: _muted)),
              )
            else
              for (final entry in entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: Text(Fmt.date(pick(entry, const ['date']))),
                      ),
                      Expanded(
                        flex: 4,
                        child: Text(
                          str(entry, const ['bill_number'], '—'),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          Fmt.money(numOf(entry, const ['amount'])),
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
            const SizedBox(height: 8),
            Container(height: 1, color: _rule),
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(child: SizedBox()),
                const Text(
                  'Grand Total',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                ),
                const SizedBox(width: 14),
                Text(
                  Fmt.money(total),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 26),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                          height: 40,
                          decoration: const BoxDecoration(
                            border: Border(bottom: BorderSide(color: _ink)),
                          )),
                      const SizedBox(height: 3),
                      const Text("Customer's Signature",
                          style: TextStyle(color: _muted, fontSize: 9.5)),
                    ],
                  ),
                ),
                const SizedBox(width: 26),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 40,
                        child: signature.trim().isEmpty
                            ? null
                            : Image.memory(
                                _decode(signature),
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const SizedBox(),
                              ),
                      ),
                      Container(height: 1, color: _ink),
                      const SizedBox(height: 3),
                      const Text('Laundry Sign',
                          style: TextStyle(color: _muted, fontSize: 9.5)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The pad hands back a `data:` URL; only the payload is needed here.
  static Uint8List _decode(String data) {
    final comma = data.indexOf(',');
    final payload = comma >= 0 ? data.substring(comma + 1) : data;
    return base64Decode(payload);
  }
}

class _SheetField extends StatelessWidget {
  const _SheetField(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 9.5,
                letterSpacing: 0.8,
                color: _LegacySheet._muted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(value,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
