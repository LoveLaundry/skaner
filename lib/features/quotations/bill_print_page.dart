import 'package:flutter/material.dart';

import '../../core/api/api_exception.dart';
import '../../core/utils/formatting.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/feedback.dart';
import 'bill_model.dart';
import 'print_paper.dart';
import 'quotation_model.dart';
import 'shared_widgets.dart';

/// Port of `components/bill-print-template.tsx`.
///
/// The bill is what the hotel takes away, so the sheet is deliberately plain:
/// line totals, then every adjustment the server applied, then the signatures.
class BillPrintPage extends StatefulWidget {
  const BillPrintPage({super.key, required this.billId});

  final String billId;

  @override
  State<BillPrintPage> createState() => _BillPrintPageState();
}

class _BillPrintPageState extends State<BillPrintPage> with OpsPrintMixin {
  BillRecord? _bill;
  bool _loading = true;
  String? _error;

  @override
  String get paperName => 'bill-${_bill?.id ?? widget.billId}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final payload = await AppScope.read(context)
          .api
          .get(operationsService, BillApi.one(widget.billId));
      if (!mounted) return;
      setState(() {
        _bill = BillRecord.fromJson(Map<String, dynamic>.from(payload as Map));
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    if (!canView(services, billsPermission)) {
      return PaperPageScaffold(
        title: 'Print bill',
        child: opsNotPermitted('bills'),
      );
    }
    return PaperPageScaffold(
      title: 'Print bill',
      actions: _bill == null ? const [] : paperActions,
      child: _loading
          ? const AppLoader(label: 'Preparing print layout')
          : _error != null
              ? AppErrorState(message: _error, onRetry: _load)
              : Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 32),
                    child: RepaintBoundary(
                      key: paperKey,
                      child: PaperSheet(child: _sheet(_bill!)),
                    ),
                  ),
                ),
    );
  }

  Widget _sheet(BillRecord b) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CompanyLetterhead(),
          const PaperRule(gap: 12),
          Center(
            child: Text(
              'BILL',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
                color: Paper.ink,
              ),
            ),
          ),
          const PaperRule(gap: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PaperField(label: 'Client', value: b.clientName),
                    const SizedBox(height: 8),
                    PaperField(label: 'Title', value: b.displayTitle),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    PaperField(label: 'Date', value: Fmt.date(b.createdAt)),
                    const SizedBox(height: 8),
                    PaperField(label: 'Bill #', value: b.id),
                  ],
                ),
              ),
            ],
          ),
          const PaperRule(gap: 12),
          PaperTable(
            headers: const ['NO.', 'DESCRIPTION', 'QTY', 'AMOUNT (LKR)'],
            flexes: const [1, 6, 2, 3],
            aligns: const [
              CrossAxisAlignment.start,
              CrossAxisAlignment.start,
              CrossAxisAlignment.end,
              CrossAxisAlignment.end,
            ],
            emptyText: 'No items on this bill',
            rows: [
              for (var i = 0; i < b.items.length; i++)
                PaperRow([
                  '${i + 1}.',
                  b.items[i].itemName,
                  Fmt.qty(b.items[i].quantity),
                  b.items[i].lineTotal.toStringAsFixed(2),
                ],
                    subtitle: b.items[i].category.trim().isEmpty
                        ? ''
                        : b.items[i].category.trim()),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (b.notes != null && b.notes!.trim().isNotEmpty)
                      PaperNote('Notes', b.notes!.trim()),
                    const SizedBox(height: 10),
                    Text(
                      'Total Items: ${b.itemCount} · '
                      'Total Quantity: ${Fmt.qty(b.totalQuantity)}',
                      style: Paper.small,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              SizedBox(
                width: 190,
                child: Column(
                  children: [
                    PaperTotal('Sub total', b.totalAmount.toStringAsFixed(2)),
                    if (b.discounts > 0)
                      PaperTotal(
                        'Discount',
                        '- ${b.discounts.toStringAsFixed(2)}',
                      ),
                    if (b.transportFee > 0)
                      PaperTotal(
                        'Transport',
                        '+ ${b.transportFee.toStringAsFixed(2)}',
                      ),
                    if (b.taxes > 0)
                      PaperTotal('Taxes', '+ ${b.taxes.toStringAsFixed(2)}'),
                    if (b.additionalCharges > 0)
                      PaperTotal(
                        'Other charges',
                        '+ ${b.additionalCharges.toStringAsFixed(2)}',
                      ),
                    Container(height: 1, color: Paper.ink),
                    PaperTotal(
                      'Grand total',
                      b.grand.toStringAsFixed(2),
                      strong: true,
                    ),
                    PaperTotal('Paid', b.paidAmount.toStringAsFixed(2)),
                    PaperTotal(
                      'Outstanding',
                      b.owed.toStringAsFixed(2),
                      strong: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const PaperRule(gap: 6),
          const PaperSignatureRow(),
        ],
      );
}
