import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/models/json.dart' as json;
import '../../core/models/linen.dart';
import '../../core/utils/formatting.dart';
import '../../data/resource_controller.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/kit/shell_parts.dart';
import '../../ui/theme.dart';
import '_linen_shared.dart';
import 'linen_tracking_detail_page.dart';

/// The tag itself: what `linen-tag-generator.tsx` prints, rendered on the
/// handset so a piece can be identified, re-tagged or checked against the
/// record without a printer.
///
/// The QR encodes the bare `linen_id`, which is exactly what
/// `/linens/by-code/{code}` expects, so a photo of this screen scans.
class GarmentDetailPage extends StatefulWidget {
  const GarmentDetailPage({super.key, required this.code});

  final String code;

  @override
  State<GarmentDetailPage> createState() => _GarmentDetailPageState();
}

class _GarmentDetailPageState extends State<GarmentDetailPage> {
  late final ResourceController<LinenItem> _controller;

  @override
  void initState() {
    super.initState();
    _controller = ResourceController(
      key: 'linen-code-$_normalised',
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
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  String get _normalised {
    try {
      return Uri.decodeComponent(widget.code).trim().toUpperCase();
    } on FormatException {
      return widget.code.trim().toUpperCase();
    }
  }

  Future<LinenItem> _fetch() async {
    final payload = await AppScope.read(context)
        .api
        .get(linenService, LinenApi.byCode(_normalised));
    return LinenItem.fromJson(json.asMap(payload));
  }

  Future<void> _reload() => _controller.load(force: true);

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final c = context.c;
    final item = _controller.data;

    return Scaffold(
      appBar: AppBar(
        title: Text(item?.linenId ?? _normalised),
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
            label: 'Tag',
          ),
          AppOfflineSyncBar(engine: services.sync),
          Expanded(
            child: RefreshIndicator(
              color: c.brand,
              onRefresh: _reload,
              child: _controller.phase == LoadPhase.failed && item == null
                  ? ListView(
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.4,
                          child: AppErrorState(
                            message: _controller.error,
                            onRetry: _reload,
                          ),
                        ),
                      ],
                    )
                  : item == null
                      ? const AppSkeletonList()
                      : _Body(item: item, onOpen: () => _openDetail(item)),
            ),
          ),
        ],
      ),
    );
  }

  void _openDetail(LinenItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LinenTrackingDetailPage(docId: item.id),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.item, required this.onOpen});

  final LinenItem item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
      children: [
        AppCard(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(Radii.md),
                  border: Border.all(color: c.line),
                ),
                child: QrImageView(
                  data: item.linenId,
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
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: BarcodeWidget(
                  barcode: Barcode.code128(),
                  data: item.linenId,
                  drawText: false,
                  height: 44,
                  backgroundColor: c.surface,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                item.linenId,
                style: t.titleMedium
                    ?.copyWith(color: c.fg, fontFamily: 'monospace'),
              ),
              const SizedBox(height: 10),
              LinenStatusBadge(status: item.status, compact: false),
            ],
          ),
        ),
        const SizedBox(height: 10),
        AppCard(
          title: 'Item details',
          child: LinenDetailGrid(
            entries: [
              ('Category', item.categoryLabel),
              ('Item type', item.itemType),
              ('Client', item.clientName),
              ('Department', item.department ?? '—'),
              ('Size', item.size ?? '—'),
              ('Color', item.color ?? '—'),
              ('Condition', item.conditionLabel),
              ('Wash count', Fmt.qty(item.washCount)),
              ('Location', item.location ?? '—'),
              ('Last washed', Fmt.date(item.lastWashedDate)),
              ('Last scanned', Fmt.date(item.lastScannedDate)),
              ('Retirement', Fmt.date(item.retirementDate)),
            ],
          ),
        ),
        if (item.notes != null && item.notes!.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          AppNotice(message: item.notes!, tone: AppTone.neutral),
        ],
        const SizedBox(height: 12),
        AppButton(
          label: 'Open full record',
          icon: Icons.open_in_new,
          variant: AppButtonVariant.primary,
          expand: true,
          onPressed: onOpen,
        ),
      ],
    );
  }
}
