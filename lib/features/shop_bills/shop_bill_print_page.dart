import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:printing/printing.dart';

import '../../config/api_config.dart';
import '../../core/api/api_exception.dart';
import '../../core/utils/formatting.dart';
import '../../data/resource_controller.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/theme.dart';
import '../quotations/print_paper.dart';
import 'shop_bill_model.dart';

/// A print-optimised shop bill.
///
/// The server owns the printable document, so this screen pulls
/// `/shop-bills/{id}/print-data` first and only falls back to the bill document
/// itself when that route is unavailable. Either way the widget tree below is
/// the single `RepaintBoundary` that `Printing.layoutPdf` captures, so what the
/// operator previews is byte-for-byte what the printer receives.
class ShopBillPrintPage extends StatefulWidget {
  const ShopBillPrintPage({super.key, required this.billId});

  final String billId;

  @override
  State<ShopBillPrintPage> createState() => _ShopBillPrintPageState();
}

class _ShopBillPrintPageState extends State<ShopBillPrintPage> {
  final GlobalKey _sheetKey = GlobalKey();

  Map<String, dynamic> _bill = const {};
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final services = AppScope.read(context);
    try {
      Map<String, dynamic> bill;
      try {
        bill = asMap(
          await services.api.get(
            ServiceNames.bills,
            ShopBillApi.printData(widget.billId),
          ),
        );
      } catch (_) {
        // The print-data route is an enrichment, not a requirement: a bill
        // without it must still print.
        bill = asMap(
          await services.api.get(
            ServiceNames.bills,
            ShopBillApi.one(widget.billId),
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _bill = bill;
        _loading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  /// Preview first when the platform can rasterise a PDF, otherwise share the
  /// raw bytes to whatever handles PDFs the device has.
  Future<void> _print() async {
    final boundary =
        _sheetKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final printed = await Printing.layoutPdf(
        onLayout: (_) async {
          final image = await boundary.toImage(pixelRatio: 3.0);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          return data!.buffer.asUint8List();
        },
        name: billNumber(_bill),
      );
      if (!printed) {
        final image = await boundary.toImage(pixelRatio: 3.0);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        await Printing.sharePdf(
          bytes: data!.buffer.asUint8List(),
          filename: '${billNumber(_bill)}.pdf',
        );
      }
      if (!mounted) return;
      AppToast.success(context, 'Sent to printer');
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Could not print: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    final boundary =
        _sheetKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final image = await boundary.toImage(pixelRatio: 3.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      await Printing.sharePdf(
        bytes: data!.buffer.asUint8List(),
        filename: '${billNumber(_bill)}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, 'Could not share: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    if (!services.auth.hasPermission(shopBillsPermission)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Print shop bill')),
        body: const AppErrorState(
          title: 'Not permitted',
          message: 'You do not have access to shop bills.',
          icon: Icons.lock_outline,
        ),
      );
    }
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Print shop bill')),
        body: const AppLoader(label: 'Preparing bill…'),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Print shop bill')),
        body: AppErrorState(message: _error, onRetry: _load),
      );
    }

    return Scaffold(
      backgroundColor: context.c.canvas,
      appBar: AppBar(
        title: const Text('Print shop bill'),
        actions: [
          AppButton.icon(
            icon: Icons.ios_share,
            tooltip: 'Share PDF',
            loading: _busy,
            onPressed: _share,
          ),
          AppButton.icon(
            icon: Icons.print_outlined,
            tooltip: 'Print',
            variant: AppButtonVariant.primary,
            loading: _busy,
            onPressed: _print,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        child: Center(
          child: RepaintBoundary(
            key: _sheetKey,
            child: _PrintSheet(bill: _bill),
          ),
        ),
      ),
    );
  }
}

/// A4-proportioned invoice. Deliberately unstyled Material primitives: paper
/// should not inherit the app's dark surface tokens.
class _PrintSheet extends StatelessWidget {
  const _PrintSheet({required this.bill});

  final Map<String, dynamic> bill;

  static const _ink = Paper.ink;
  static const _muted = Paper.muted;
  static const _rule = Paper.rule;

  @override
  Widget build(BuildContext context) {
    final lines = billLines(bill);
    final company = asMap(pick(bill, const ['company', 'business', 'shop']));
    final grand = billGrandTotalOf(bill);
    final paid = billPaid(bill);

    return Container(
      width: 420,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
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
                      Text(
                        str(
                            company,
                            const ['name', 'business_name', 'company_name'],
                            'Love Laundry'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                        ),
                      ),
                      if (str(company, const ['address', 'address_line'])
                          .trim()
                          .isNotEmpty)
                        Text(str(company, const ['address']),
                            style: const TextStyle(color: _muted)),
                      if (str(company, const ['phone', 'contact'])
                          .trim()
                          .isNotEmpty)
                        Text(str(company, const ['phone']),
                            style: const TextStyle(color: _muted)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'SHOP BILL',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(billNumber(bill),
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    Text(
                        'Created ${Fmt.dateTime(pick(bill, const [
                              'created_at'
                            ]))}',
                        style: const TextStyle(color: _muted, fontSize: 10.5)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(height: 1, color: _rule),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _PaperField(
                    'Billed to',
                    billClient(bill),
                    Fmt.humanise(billPaymentStatus(bill)),
                  ),
                ),
                Expanded(
                  child: _PaperField(
                    'Delivery date',
                    Fmt.date(pick(bill, const ['delivery_date'])),
                    'Status: ${Fmt.humanise(billStatus(bill))}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _PaperTable(lines: lines),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (billNotes(bill).trim().isNotEmpty) ...[
                        const Text('Notes',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 10.5)),
                        const SizedBox(height: 3),
                        Text(billNotes(bill),
                            style:
                                const TextStyle(color: _muted, fontSize: 10.5)),
                      ],
                    ],
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: Column(
                    children: [
                      _PaperTotal('Subtotal', Fmt.money(linesSubtotal(lines))),
                      if (billDiscounts(bill) > 0)
                        _PaperTotal(
                            'Discounts', '- ${Fmt.money(billDiscounts(bill))}'),
                      if (billTransportFee(bill) > 0)
                        _PaperTotal('Transport',
                            '+ ${Fmt.money(billTransportFee(bill))}'),
                      if (billTaxes(bill) > 0)
                        _PaperTotal('Taxes', '+ ${Fmt.money(billTaxes(bill))}'),
                      const SizedBox(height: 4),
                      Container(height: 1, color: _rule),
                      const SizedBox(height: 4),
                      _PaperTotal('Grand total', Fmt.money(grand),
                          strong: true),
                      _PaperTotal('Paid', Fmt.money(paid)),
                      _PaperTotal(
                        'Outstanding',
                        Fmt.money(billOutstanding(bill)),
                        strong: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(height: 1, color: _rule),
            const SizedBox(height: 8),
            const Text(
              'Thank you for your business.',
              style: TextStyle(color: _muted, fontSize: 10.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaperField extends StatelessWidget {
  const _PaperField(this.label, this.value, this.sub);

  final String label;
  final String value;
  final String sub;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 9.5,
              letterSpacing: 0.8,
              color: _PrintSheet._muted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          ),
          if (sub.trim().isNotEmpty)
            Text(sub,
                style:
                    const TextStyle(color: _PrintSheet._muted, fontSize: 10.5)),
        ],
      );
}

class _PaperTotal extends StatelessWidget {
  const _PaperTotal(this.label, this.value, {this.strong = false});

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: strong ? _PrintSheet._ink : _PrintSheet._muted,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
                fontSize: strong ? 12.5 : 11,
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: TextStyle(
                fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
                fontSize: strong ? 12.5 : 11,
              ),
            ),
          ],
        ),
      );
}

class _PaperTable extends StatelessWidget {
  const _PaperTable({required this.lines});

  final List<ShopBillLine> lines;

  @override
  Widget build(BuildContext context) {
    const head = TextStyle(
      fontSize: 9.5,
      letterSpacing: 0.8,
      color: _PrintSheet._muted,
      fontWeight: FontWeight.w700,
    );
    return Column(
      children: [
        Container(height: 1, color: _PrintSheet._rule),
        const SizedBox(height: 6),
        Row(
          children: [
            const Expanded(flex: 4, child: Text('ITEM', style: head)),
            const Expanded(
                flex: 2,
                child: Text('QTY', style: head, textAlign: TextAlign.right)),
            const Expanded(
                flex: 2,
                child: Text('RATE', style: head, textAlign: TextAlign.right)),
            const Expanded(
                flex: 2,
                child: Text('TOTAL', style: head, textAlign: TextAlign.right)),
          ],
        ),
        const SizedBox(height: 6),
        Container(height: 1, color: _PrintSheet._rule),
        if (lines.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text('No items on this bill.',
                style: TextStyle(color: _PrintSheet._muted)),
          )
        else
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(line.itemName,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        if (line.specification.trim().isNotEmpty)
                          Text(line.specification,
                              style: const TextStyle(
                                  color: _PrintSheet._muted, fontSize: 10)),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(Fmt.qty(line.quantity),
                        textAlign: TextAlign.right),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(Fmt.money(line.unitPrice),
                        textAlign: TextAlign.right),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      Fmt.money(line.total),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
        Container(height: 1, color: _PrintSheet._rule),
      ],
    );
  }
}
