import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:printing/printing.dart';

import '../../ui/kit/feedback.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/theme.dart';

/// Neutral paper tokens for every printable document in this feature.
///
/// A print sheet must never inherit the app's dark surfaces or brand accents:
/// what the operator previews is what the printer receives, and the paper is
/// always white with black ink regardless of the device theme.
class Paper {
  Paper._();

  static const Color ink = Color(0xFF111827);
  static const Color muted = Color(0xFF6B7280);
  static const Color rule = Color(0xFFE5E7EB);

  static const TextStyle head = TextStyle(
    fontSize: 9.5,
    letterSpacing: 0.8,
    color: muted,
    fontWeight: FontWeight.w700,
  );

  static const TextStyle body = TextStyle(color: ink, fontSize: 11.5);
  static const TextStyle small = TextStyle(color: muted, fontSize: 10.5);
}

/// The white A4-proportioned page every print screen wraps in a RepaintBoundary.
class PaperSheet extends StatelessWidget {
  const PaperSheet({super.key, required this.child, this.width = 420});

  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        child: DefaultTextStyle(
          style: Paper.body,
          child: child,
        ),
      );
}

class PaperHeading extends StatelessWidget {
  const PaperHeading({
    super.key,
    required this.title,
    required this.subtitle,
    this.documentLabel,
  });

  final String title;
  final String subtitle;
  final String? documentLabel;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Paper.ink,
                  ),
                ),
                Text(subtitle, style: Paper.small),
              ],
            ),
          ),
          if (documentLabel != null) ...[
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  documentLabel!,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: Paper.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: Paper.small),
              ],
            ),
          ],
        ],
      );
}

class PaperRule extends StatelessWidget {
  const PaperRule({super.key, this.gap = 12});

  final double gap;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 1),
          Container(height: 1, color: Paper.rule),
          SizedBox(height: gap),
        ],
      );
}

class PaperField extends StatelessWidget {
  const PaperField(
      {super.key,
      required this.label,
      required this.value,
      this.sub,
      this.alignEnd = false});

  final String label;
  final String value;
  final String? sub;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment:
            alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: Paper.head),
          const SizedBox(height: 3),
          Text(
            value.isEmpty ? '—' : value,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: Paper.ink,
            ),
          ),
          if (sub != null && sub!.trim().isNotEmpty)
            Text(sub!, style: Paper.small),
        ],
      );
}

class PaperTotal extends StatelessWidget {
  const PaperTotal(this.label, this.value, {super.key, this.strong = false});

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
                color: strong ? Paper.ink : Paper.muted,
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
                color: Paper.ink,
              ),
            ),
          ],
        ),
      );
}

/// A four-column line-item grid. The caller supplies already-formatted strings
/// so the same rows serve a quotation, a bill, a gate pass and a delivery slip.
class PaperTable extends StatelessWidget {
  const PaperTable({
    super.key,
    required this.rows,
    this.headers = const ['ITEM', 'QTY', 'RATE', 'TOTAL'],
    this.flexes = const [4, 2, 2, 2],
    this.aligns = const [
      CrossAxisAlignment.start,
      CrossAxisAlignment.end,
      CrossAxisAlignment.end,
      CrossAxisAlignment.end,
    ],
    this.emptyText = 'No items on this document.',
    this.zebra = true,
  });

  final List<PaperRow> rows;
  final List<String> headers;
  final List<int> flexes;
  final List<CrossAxisAlignment> aligns;
  final String emptyText;
  final bool zebra;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Container(height: 1, color: Paper.rule),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 0; i < headers.length; i++)
                Expanded(
                  flex: flexes[i],
                  child: Text(
                    headers[i],
                    style: Paper.head,
                    textAlign: aligns[i] == CrossAxisAlignment.end
                        ? TextAlign.right
                        : TextAlign.start,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Container(height: 1, color: Paper.rule),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(emptyText, style: Paper.small),
            )
          else
            for (var r = 0; r < rows.length; r++)
              Container(
                color: zebra && r.isOdd ? const Color(0xFFF7F7F8) : null,
                padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < rows[r].cells.length; i++)
                      Expanded(
                        flex: i < flexes.length ? flexes[i] : 1,
                        child: i == 0
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    rows[r].cells[i],
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Paper.ink,
                                    ),
                                  ),
                                  for (final line in rows[r]
                                      .subtitle
                                      .split('\n')
                                      .where((l) => l.trim().isNotEmpty))
                                    Text(line, style: Paper.small),
                                ],
                              )
                            : Text(
                                rows[r].cells[i],
                                textAlign: aligns[i] == CrossAxisAlignment.end
                                    ? TextAlign.right
                                    : TextAlign.start,
                                style: TextStyle(
                                  color: Paper.ink,
                                  fontWeight: i == rows[r].cells.length - 1
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                      ),
                  ],
                ),
              ),
          Container(height: 1, color: Paper.rule),
        ],
      );
}

class PaperRow {
  const PaperRow(this.cells, {this.subtitle = ''});

  final List<String> cells;
  final String subtitle;
}

/// A plain text block for notes, terms and signatures.
class PaperNote extends StatelessWidget {
  const PaperNote(this.label, this.body, {super.key});

  final String label;
  final String body;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: Paper.head),
          const SizedBox(height: 3),
          Text(body, style: Paper.small),
        ],
      );
}

/// A ruled signature block for a hand-signed receipt.
class PaperSignature extends StatelessWidget {
  const PaperSignature(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 26),
          Container(height: 1, color: Paper.rule),
          const SizedBox(height: 3),
          Text(label, style: Paper.small),
        ],
      );
}

/// The scroll chrome every print screen shares: a neutral page, a share action
/// and a print action, with the sheet itself inside the RepaintBoundary.
class PaperPageScaffold extends StatelessWidget {
  const PaperPageScaffold({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
  });

  final String title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: context.c.canvas,
        appBar: AppBar(title: Text(title), actions: actions),
        body: child,
      );
}

/// The letterhead, mirrored from `config/company.ts` so a printed document
/// carries the same identity the web app's templates do.
class Company {
  Company._();

  static const name = 'Love Laundry';
  static const tagline = 'and dry cleaning experts';
  static const registrationNo = '40-3064';
  static const addressLine1 = 'Medagama, Panirendawa';
  static const addressLine2 = 'Chilaw, Puttalam, Sri Lanka';
  static const phonePrimary = '+94 77 4200 919';
  static const phoneSecondary = '+94 70 243 3566';
  static const email = 'lovelaundry01@gmail.com';

  static const services = [
    'Dry Cleaning',
    'Free Pickup & Delivery',
    'Wash & Pressed',
    'Wash & Fold',
    'Laundered Pressed',
  ];

  /// `QUOTATION_CONDITIONS` in `config/company.ts`.
  static const quotationConditions = [
    'Prices are valid for 30 days from the date of quotation.',
    'Quotation is subject to change without prior notice.',
    'All items are subject to availability at time of order.',
    'Payment terms: 50% advance, balance on delivery.',
    'Any disputes are subject to Colombo jurisdiction.',
  ];
}

class CompanyLetterhead extends StatelessWidget {
  const CompanyLetterhead({super.key});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    Text(
                      Company.name.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2.4,
                        color: Paper.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      Company.tagline,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontStyle: FontStyle.italic,
                        color: Color(0xFF333333),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  border: Border.all(color: Paper.ink),
                  color: const Color(0xFFF9F9F9),
                ),
                child: Text(
                  'Reg. No: ${Company.registrationNo}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Paper.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final service in Company.services)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    border: Border.all(color: Paper.ink),
                    color: const Color(0xFFF5F5F5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                          color: Paper.ink,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        service,
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: Paper.ink,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Container(height: 1, color: Paper.ink),
          const SizedBox(height: 7),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tel: ${Company.phonePrimary} / ${Company.phoneSecondary}',
                      style: Paper.small,
                    ),
                    Text('Email: ${Company.email}', style: Paper.small),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(Company.addressLine1, style: Paper.small),
                  Text(Company.addressLine2, style: Paper.small),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(height: 1, color: Paper.ink),
        ],
      );
}

/// The two-sided signature block the web templates end every document with.
class PaperSignatureRow extends StatelessWidget {
  /// The slips (`gate-pass-print-sheet.tsx`, `delivery-print-sheet.tsx`) sign in
  /// three equal columns and carry no company block, so passing three labels
  /// switches to that layout; two labels keep the letterhead centre block that
  /// bills and quotations use.
  const PaperSignatureRow(
      {super.key,
      this.left = 'Prepared By',
      this.right = 'Authorized Signature',
      this.labels});

  final String left;
  final String right;
  final List<String>? labels;

  @override
  Widget build(BuildContext context) {
    final given = labels;
    if (given != null && given.length > 2) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < given.length; i++) ...[
            if (i > 0) const SizedBox(width: 16),
            Expanded(child: PaperSignature(given[i])),
          ],
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: PaperSignature(given?[0] ?? left),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                Company.name,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Paper.ink,
                ),
              ),
              Text(Company.addressLine1,
                  style: const TextStyle(fontSize: 9, color: Paper.muted)),
              Text(Company.addressLine2,
                  style: const TextStyle(fontSize: 9, color: Paper.muted)),
              const SizedBox(height: 5),
              Text(
                'Tel: ${Company.phonePrimary}',
                style: const TextStyle(fontSize: 9, color: Paper.muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(child: PaperSignature(given?[1] ?? right)),
      ],
    );
  }
}

/// Rasterises the one [paperKey] boundary into a PDF.
///
/// The screen owns exactly one `RepaintBoundary`, so the preview, the print
/// job and the shared file are byte-for-byte the same document.
mixin OpsPrintMixin<T extends StatefulWidget> on State<T> {
  final GlobalKey paperKey = GlobalKey();
  bool printing = false;

  RenderRepaintBoundary? get _boundary =>
      paperKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;

  Future<Uint8List> _rasterise() async {
    final boundary = _boundary;
    if (boundary == null) return Uint8List(0);
    final image = await boundary.toImage(pixelRatio: 3.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  Future<void> printPaper(String filename) async {
    if (_boundary == null) return;
    setState(() => printing = true);
    try {
      final printed = await Printing.layoutPdf(
        onLayout: (_) async => _rasterise(),
        name: filename,
      );
      if (!printed) {
        await Printing.sharePdf(
            bytes: await _rasterise(), filename: '$filename.pdf');
      }
      if (mounted) AppToast.success(context, 'Sent to printer');
    } catch (e) {
      if (mounted) AppToast.error(context, 'Could not print: $e');
    } finally {
      if (mounted) setState(() => printing = false);
    }
  }

  Future<void> sharePaper(String filename) async {
    if (_boundary == null) return;
    setState(() => printing = true);
    try {
      await Printing.sharePdf(
        bytes: await _rasterise(),
        filename: '$filename.pdf',
      );
    } catch (e) {
      if (mounted) AppToast.error(context, 'Could not share: $e');
    } finally {
      if (mounted) setState(() => printing = false);
    }
  }

  /// The share and print buttons every print screen puts in its app bar.
  List<Widget> get paperActions => [
        AppButton.icon(
          icon: Icons.ios_share,
          tooltip: 'Share PDF',
          loading: printing,
          onPressed: () => sharePaper(paperName),
        ),
        AppButton.icon(
          icon: Icons.print_outlined,
          tooltip: 'Print',
          variant: AppButtonVariant.primary,
          loading: printing,
          onPressed: () => printPaper(paperName),
        ),
      ];

  String get paperName;
}
