import 'package:flutter/material.dart';

import '../../config/api_config.dart';
import '../../core/api/api_exception.dart';
import '../../core/utils/formatting.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/feedback.dart';
import 'print_paper.dart';
import 'quotation_model.dart';
import 'shared_widgets.dart';

/// Port of `pages/quotation-print-page.tsx` + `quotation-print-template.tsx`.
///
/// The web app paginates at 22 rows and repeats a "continued" footer; on a
/// phone the sheet is one continuous column, so the pagination is dropped and
/// every row is kept. What matters for the contract is the same single
/// `RepaintBoundary` that the preview, the print job and the shared PDF come
/// from.
class QuotationPrintPage extends StatefulWidget {
  const QuotationPrintPage({super.key, required this.quotationId});

  final String quotationId;

  @override
  State<QuotationPrintPage> createState() => _QuotationPrintPageState();
}

class _QuotationPrintPageState extends State<QuotationPrintPage>
    with OpsPrintMixin {
  Quotation? _q;
  bool _loading = true;
  String? _error;

  @override
  String get paperName => 'quotation-${_q?.id ?? widget.quotationId}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final payload = await AppScope.read(context)
          .api
          .get(ServiceNames.quotation, QuotationApi.one(widget.quotationId));
      if (!mounted) return;
      setState(() {
        _q = Quotation.fromJson(Map<String, dynamic>.from(payload as Map));
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
    if (!canView(services, quotationsReadPermission)) {
      return PaperPageScaffold(
        title: 'Print quotation',
        child: opsNotPermitted('quotations'),
      );
    }
    return PaperPageScaffold(
      title: 'Print quotation',
      actions: _q == null ? const [] : paperActions,
      child: _loading
          ? const AppLoader(label: 'Preparing print layout')
          : _error != null
              ? AppErrorState(message: _error, onRetry: _load)
              : Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 32),
                    child: RepaintBoundary(
                      key: paperKey,
                      child: PaperSheet(child: _sheet(_q!)),
                    ),
                  ),
                ),
    );
  }

  Widget _sheet(Quotation q) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CompanyLetterhead(),
          const PaperRule(gap: 12),
          Center(
            child: Text(
              'QUOTATION',
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
                    PaperField(label: 'Client', value: q.clientName),
                    const SizedBox(height: 8),
                    PaperField(
                      label: 'Title',
                      value: q.displayTitle,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    PaperField(label: 'Date', value: Fmt.date(q.createdAt)),
                    const SizedBox(height: 8),
                    PaperField(label: 'Quotation #', value: q.id),
                  ],
                ),
              ),
            ],
          ),
          const PaperRule(gap: 12),
          PaperTable(
            headers: const [
              'NO.',
              'DESCRIPTION OF ITEM',
              'CATEGORY',
              'UNIT PRICE (LKR)'
            ],
            flexes: const [1, 6, 3, 3],
            aligns: const [
              CrossAxisAlignment.start,
              CrossAxisAlignment.start,
              CrossAxisAlignment.start,
              CrossAxisAlignment.end,
            ],
            emptyText: 'No items in this quotation',
            rows: [
              for (var i = 0; i < q.lineItems.length; i++)
                PaperRow(
                  [
                    '${i + 1}.',
                    q.lineItems[i].itemName,
                    q.lineItems[i].category.trim().isEmpty
                        ? 'General'
                        : q.lineItems[i].category.trim(),
                    q.lineItems[i].unitPrice.toStringAsFixed(2),
                  ],
                  subtitle: [
                    for (final spec in q.lineItems[i].specifications)
                      if (spec.specification.trim().isNotEmpty)
                        '• ${spec.specification} — LKR '
                            '${spec.unitPrice.toStringAsFixed(2)}',
                  ].join('\n'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Total Items: ${q.itemCount}',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Paper.ink,
            ),
          ),
          const PaperRule(gap: 14),
          PaperNote('Conditions', Company.quotationConditions.join('\n')),
          const PaperRule(gap: 6),
          const PaperSignatureRow(),
        ],
      );
}
