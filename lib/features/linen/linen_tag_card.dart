import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../ui/theme.dart';

/// A live linen tag: the QR, CODE128 barcode and bare structured ID that
/// `linen-tag-generator.tsx` prints. Both codes carry exactly [id] — the mobile
/// stack has no `qr_url`, and `/linens/by-code/{code}` expects the bare code.
///
/// The [compact] variant is sized for a list row or a scan-result card; the
/// full variant is the scannable, print-sized tag. Callers decide whether to
/// wrap the tag in an [AppCard] so it can sit inside an existing card without
/// doubling the border.
class LinenTagCard extends StatelessWidget {
  const LinenTagCard({
    super.key,
    required this.id,
    this.compact = false,
    this.compactWidth = 118,
    this.showId = true,
  });

  /// The bare structured ID, e.g. `BSG-A0001XL`.
  final String id;

  /// Use the small row-sized layout instead of the full print-sized tag.
  final bool compact;

  /// Width of the compact layout. Keep it narrow enough for a phone row.
  final double compactWidth;

  /// Hide the text in the compact layout when the surrounding row already
  /// prints the ID as a column, so the same code is not shown twice.
  final bool showId;

  @override
  Widget build(BuildContext context) {
    final data = id.trim();
    if (data.isEmpty) {
      return Text(
        'No tag ID',
        style: context.texts.bodySmall?.copyWith(color: context.c.fgMuted),
      );
    }
    return compact
        ? _CompactTag(data: data, width: compactWidth, showId: showId)
        : _FullTag(data: data);
  }
}

class _FullTag extends StatelessWidget {
  const _FullTag({required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(color: c.line),
            ),
            child: QrImageView(
              data: data,
              size: 168,
              backgroundColor: c.surface,
              eyeStyle: QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: c.fg,
              ),
              dataModuleStyle: QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: c.fg,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: BarcodeWidget(
            barcode: Barcode.code128(),
            data: data,
            drawText: false,
            backgroundColor: c.surface,
            color: c.fg,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          data,
          textAlign: TextAlign.center,
          style: t.titleMedium?.copyWith(
            color: c.fg,
            fontFamily: 'monospace',
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _CompactTag extends StatelessWidget {
  const _CompactTag({
    required this.data,
    required this.width,
    required this.showId,
  });

  final String data;
  final double width;
  final bool showId;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    return SizedBox(
      width: width,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          QrImageView(
            data: data,
            size: 30,
            backgroundColor: c.surface,
            eyeStyle: QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: c.fg,
            ),
            dataModuleStyle: QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: c.fg,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showId)
                  Text(
                    data,
                    style: t.bodySmall?.copyWith(
                      color: c.fg,
                      fontFamily: 'monospace',
                      fontSize: context.fs(11),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (showId) const SizedBox(height: 3),
                SizedBox(
                  width: double.infinity,
                  height: 16,
                  child: BarcodeWidget(
                    barcode: Barcode.code128(),
                    data: data,
                    drawText: false,
                    backgroundColor: c.surface,
                    color: c.fg,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
