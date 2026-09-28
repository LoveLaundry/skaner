import 'package:flutter/material.dart';

import '../../core/api/api_exception.dart';
import '../../core/utils/formatting.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/feedback.dart';
import 'bill_model.dart';
import 'print_paper.dart';
import 'quotation_model.dart';
import 'shared_widgets.dart';

/// Port of `components/gate-pass-print-sheet.tsx`.
///
/// The gate pass is the receipt the hotel signs for the linen it hands over, so
/// the sheet leads with the two counts side by side — what the hotel said and
/// what we actually received — and flags every line where they disagree.
class GatepassSlipPage extends StatefulWidget {
  const GatepassSlipPage({super.key, required this.gatepassId});

  final String gatepassId;

  @override
  State<GatepassSlipPage> createState() => _GatepassSlipPageState();
}

class _GatepassSlipPageState extends State<GatepassSlipPage>
    with OpsPrintMixin {
  GatePass? _pass;
  bool _loading = true;
  String? _error;

  @override
  String get paperName =>
      'gate-pass-${_pass?.gatePassNumber ?? widget.gatepassId}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final payload = await AppScope.read(context)
          .api
          .get(operationsService, GatePassApi.one(widget.gatepassId));
      if (!mounted) return;
      setState(() {
        _pass = GatePass.fromJson(Map<String, dynamic>.from(payload as Map));
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
    if (!canView(services, gatePassesPermission)) {
      return PaperPageScaffold(
        title: 'Print gate pass',
        child: opsNotPermitted('gate passes'),
      );
    }
    return PaperPageScaffold(
      title: 'Print gate pass',
      actions: _pass == null ? const [] : paperActions,
      child: _loading
          ? const AppLoader(label: 'Preparing print layout')
          : _error != null
              ? AppErrorState(message: _error, onRetry: _load)
              : _pass == null
                  ? const AppEmptyState(
                      title: 'Gate pass not found',
                      message: 'It may have been deleted.',
                      icon: Icons.inbox_outlined,
                    )
                  : Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(12, 16, 12, 32),
                        child: RepaintBoundary(
                          key: paperKey,
                          child: PaperSheet(child: _sheet(_pass!)),
                        ),
                      ),
                    ),
    );
  }

  Widget _sheet(GatePass gp) {
    final items = gp.items;
    final mismatched = gp.mismatchCount;
    final rewashed = items.where((i) => i.rewashed).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CompanyLetterhead(),
        const PaperRule(gap: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                'GATE PASS',
                style: Paper.head.copyWith(
                  fontSize: 17,
                  letterSpacing: 2.5,
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'No: ${gp.gatePassNumber}',
                  style: Paper.body.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text('Status: ${humaniseStatus(gp.status)}',
                    style: Paper.small),
              ],
            ),
          ],
        ),
        const PaperRule(gap: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PaperField(label: 'Client / Hotel', value: gp.clientName),
                  const SizedBox(height: 6),
                  PaperField(label: 'Received By', value: gp.receivedBy),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  PaperField(
                    label: 'Date Received',
                    value: Fmt.date(gp.receivingDate),
                    alignEnd: true,
                  ),
                  const SizedBox(height: 6),
                  PaperField(
                    label: 'Item Types',
                    value: '${items.length}',
                    alignEnd: true,
                  ),
                ],
              ),
            ),
          ],
        ),
        const PaperRule(gap: 10),
        PaperTable(
          headers: const [
            'NO.',
            'ITEM',
            'SPECIFICATION',
            'CLIENT QTY',
            'RECEIVED',
            'DIFF',
          ],
          flexes: const [1, 5, 3, 2, 2, 1],
          aligns: const [
            CrossAxisAlignment.start,
            CrossAxisAlignment.start,
            CrossAxisAlignment.start,
            CrossAxisAlignment.end,
            CrossAxisAlignment.end,
            CrossAxisAlignment.end,
          ],
          emptyText: 'No items',
          rows: [
            for (var i = 0; i < items.length; i++)
              PaperRow([
                '${i + 1}',
                items[i].rewashed
                    ? '${items[i].itemName} (REWASHED — not billed)'
                    : items[i].itemName,
                items[i].specification,
                '${items[i].clientQty}',
                '${items[i].receivedQty}',
                // A zero difference is left blank so the eye lands on the real
                // disagreements instead of a column of noughts.
                items[i].difference != 0 ? '${items[i].difference}' : '',
              ]),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              'Total Items: ${items.length} '
              'type${items.length != 1 ? 's' : ''}',
              style: Paper.body,
            ),
            const Spacer(),
            Text('Total Pieces: ${gp.totalReceived}', style: Paper.body),
          ],
        ),
        if (mismatched > 0) ...[
          const SizedBox(height: 8),
          Text(
            'Note: Quantity differences detected on $mismatched '
            'item${mismatched != 1 ? 's' : ''}. Verified before processing.',
            style: Paper.body.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
        if (rewashed > 0) ...[
          const SizedBox(height: 4),
          Text(
            'Note: $rewashed item${rewashed != 1 ? 's' : ''} tagged as free '
            're-wash — not billable.',
            style: Paper.body.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
        if ((gp.notes ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          PaperNote('Remarks', gp.notes!.trim()),
        ],
        const PaperRule(gap: 6),
        const PaperSignatureRow(
          labels: [
            'Recorded By',
            'Received At Laundry',
            'Authorized Signature'
          ],
        ),
      ],
    );
  }
}
