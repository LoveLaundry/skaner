import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/models/json.dart' as json;
import '../../core/models/linen.dart';
import '../../core/utils/formatting.dart';
import '../../data/resource_controller.dart';
import '../../state/app_scope.dart';
import '../../ui/kit/feedback.dart';
import '../../ui/kit/inputs.dart';
import '../../ui/kit/primitives.dart';
import '../../ui/theme.dart';
import '_linen_shared.dart';
import 'linen_tracking_detail_page.dart';

/// Port of `features/linen/pages/linen-scanner.tsx`.
///
/// Camera and typed entry are peers, not a primary path and a fallback: the
/// manual field is on screen whatever the camera is doing, so a denied
/// permission, a device with no camera, or a tag that is too damaged to decode
/// never stops the lookup. A decode is never trusted straight to the API — it
/// goes through [parseLinenCode] first, because a tag printed by another
/// system can arrive as a URL.
class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final _codeCtrl = TextEditingController();
  final _scanner = MobileScannerController(
    autoStart: false,
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 400,
    facing: CameraFacing.back,
    formats: const [
      BarcodeFormat.qrCode,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.dataMatrix,
      BarcodeFormat.ean13,
    ],
  );

  ResourceController<LinenItem>? _result;
  String? _code;
  String? _error;
  bool _cameraOn = false;
  bool _starting = false;
  String? _pending;
  final List<String> _history = [];

  @override
  void initState() {
    super.initState();
    _scanner.addListener(_onScanner);
  }

  @override
  void dispose() {
    _scanner.removeListener(_onScanner);
    _result?.removeListener(_onResult);
    _result?.dispose();
    _codeCtrl.dispose();
    unawaited(_scanner.dispose());
    super.dispose();
  }

  void _onScanner() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final item = _result?.data;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan linen'),
        actions: [
          if (_cameraOn)
            AppButton.icon(
              icon: _scanner.value.torchState == TorchState.on
                  ? Icons.flash_on
                  : Icons.flash_off,
              tooltip: 'Toggle torch',
              onPressed: _scanner.value.torchState == TorchState.unavailable
                  ? null
                  : _toggleTorch,
            ),
          AppButton.icon(
            icon: _cameraOn
                ? Icons.no_photography_outlined
                : Icons.photo_camera_outlined,
            tooltip: _cameraOn ? 'Stop camera' : 'Start camera',
            loading: _starting,
            onPressed: _cameraOn ? _stopCamera : _startCamera,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_cameraOn || _starting)
            _Preview(
              controller: _scanner,
              onDetect: _onDetect,
              onRetry: _startCamera,
              starting: _starting,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: AppField(
              label: 'Linen ID',
              hint: 'Type the code on the tag, e.g. LL-7K4P92',
              error: _error,
              child: AppTextInput(
                controller: _codeCtrl,
                hint: 'Enter linen ID',
                icon: Icons.keyboard_alt_outlined,
                mono: true,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _lookupTyped(_codeCtrl.text),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                suffix: IconButton(
                  icon: const Icon(Icons.search, size: 18),
                  tooltip: 'Look up',
                  onPressed:
                      _resolveBusy ? null : () => _lookupTyped(_codeCtrl.text),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Cancel',
                    variant: AppButtonVariant.secondary,
                    expand: true,
                    onPressed: () => Navigator.of(context).pop(_code),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppButton(
                    label: 'Open full record',
                    icon: Icons.open_in_new,
                    variant: AppButtonVariant.primary,
                    expand: true,
                    onPressed: item == null ? null : () => _openDetail(item),
                  ),
                ),
              ],
            ),
          ),
          if (_history.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'RECENT',
                    style: context.texts.labelSmall?.copyWith(
                      color: c.fgFaint,
                      fontSize: 10.5,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final code in _history.take(8))
                        AppFilterChip(
                          label: code,
                          selected: code == _code,
                          onTap: () => _lookupTyped(code),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Expanded(child: _resultBody(item)),
        ],
      ),
    );
  }

  bool get _resolveBusy => _result?.isLoading ?? false;

  Widget _resultBody(LinenItem? item) {
    if (item != null) {
      return _Result(
        item: item,
        pending: _pending,
        onAction: _runAction,
      );
    }
    final controller = _result;
    if (controller == null) {
      return ListView(
        padding: const EdgeInsets.only(top: 20),
        children: [
          SizedBox(
            height: 200,
            child: AppEmptyState(
              title: _cameraOn ? 'Point at a tag' : 'Ready to scan',
              message: _cameraOn
                  ? 'Scanning is automatic. Or type the code below.'
                  : 'Start the camera or type the code on the tag.',
              icon: Icons.qr_code_scanner,
              action: _cameraOn
                  ? null
                  : AppButton(
                      label: 'Start camera',
                      icon: Icons.photo_camera_outlined,
                      variant: AppButtonVariant.primary,
                      onPressed: _startCamera,
                    ),
            ),
          ),
        ],
      );
    }
    if (controller.isLoading) return const AppSkeletonList();
    return ListView(
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.3,
          child: AppErrorState(
            title: 'No linen found',
            message: controller.error ?? 'Nothing matches that code.',
            onRetry: _resolveBusy ? null : () => _lookupTyped(_code ?? ''),
          ),
        ),
      ],
    );
  }

  Future<void> _startCamera() async {
    setState(() {
      _starting = true;
      _error = null;
    });

    final status = await Permission.camera.request();
    if (!mounted) return;
    if (!status.isGranted) {
      setState(() {
        _starting = false;
        _error = status.isPermanentlyDenied
            ? 'Camera access is blocked. Enable it in system settings, or type the code below.'
            : 'Camera access was declined. Type the code below instead.';
      });
      return;
    }

    try {
      await _scanner.start(cameraDirection: CameraFacing.back);
    } on MobileScannerException catch (e) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = _cameraErrorText(e);
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _starting = false;
      _cameraOn = true;
    });
  }

  Future<void> _stopCamera() async {
    try {
      await _scanner.stop();
    } on MobileScannerException {
      // The camera is already gone; the state below is the same either way.
    }
    if (mounted) setState(() => _cameraOn = false);
  }

  Future<void> _toggleTorch() async {
    try {
      await _scanner.toggleTorch();
    } on MobileScannerException {
      if (mounted) setState(() {});
    }
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_result?.isLoading ?? false) return;
    for (final barcode in capture.barcodes) {
      final code = parseLinenCode(barcode.rawValue ?? barcode.displayValue);
      if (code == null) continue;
      if (_cameraOn) await _stopCamera();
      _lookupTyped(code);
      return;
    }
  }

  Future<void> _lookupTyped(String raw) async {
    final code = parseLinenCode(raw);
    if (code == null) {
      setState(() => _error = 'That does not look like a linen code');
      return;
    }
    FocusScope.of(context).unfocus();
    final controller = ResourceController(
      key: 'linen-code-$code',
      cache: AppScope.read(context).cache,
      fetcher: () async {
        final payload = await AppScope.read(context)
            .api
            .get(linenService, LinenApi.byCode(code));
        return LinenItem.fromJson(json.asMap(payload));
      },
    )..load(force: true);
    setState(() {
      _code = code;
      _error = null;
      _history.remove(code);
      _history.insert(0, code);
    });
    _swapResult(controller);
  }

  void _onResult() {
    if (mounted) setState(() {});
  }

  void _swapResult(ResourceController<LinenItem> next) {
    _result?.removeListener(_onResult);
    _result?.dispose();
    setState(() => _result = next..addListener(_onResult));
  }

  Future<void> _runAction(LinenScanAction action) async {
    final item = _result?.data;
    if (item == null) return;
    setState(() => _pending = action.value);
    final ok = await postLinenScan(context, item.id, action);
    if (!mounted) return;
    setState(() => _pending = null);
    if (!ok) return;
    await _result?.load(force: true);
  }

  void _openDetail(LinenItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LinenTrackingDetailPage(docId: item.id),
      ),
    );
  }
}

String _cameraErrorText(MobileScannerException e) => switch (e.errorCode) {
      MobileScannerErrorCode.permissionDenied =>
        'Camera access is blocked. Enable it in system settings, or type the code below.',
      MobileScannerErrorCode.unsupported =>
        'Scanning is not supported on this device. Type the code below instead.',
      _ => e.errorDetails?.message ?? 'The camera could not be started.',
    };

class _Preview extends StatelessWidget {
  const _Preview({
    required this.controller,
    required this.onDetect,
    required this.onRetry,
    required this.starting,
  });

  final MobileScannerController controller;
  final ValueChanged<BarcodeCapture> onDetect;
  final VoidCallback onRetry;
  final bool starting;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.32;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: Colors.black),
              MobileScanner(
                controller: controller,
                onDetect: onDetect,
                errorBuilder: (context, error, child) =>
                    _CameraError(error: error, onRetry: onRetry),
              ),
              if (starting)
                const ColoredBox(
                  color: Color(0xB3000000),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppSpinner(size: 26, color: Colors.white),
                        SizedBox(height: 10),
                        Text(
                          'Starting camera',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                )
              else
                IgnorePointer(
                  child: Center(
                    child: Container(
                      width: 190,
                      height: 190,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white70, width: 2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              if (!starting)
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ColoredBox(
                    color: Color(0x66000000),
                    child: Padding(
                      padding:
                          EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      child: Text(
                        'Scanning is automatic',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.error, required this.onRetry});

  final MobileScannerException error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                denied
                    ? Icons.no_photography_outlined
                    : Icons.videocam_off_outlined,
                size: 30,
                color: Colors.white70,
              ),
              const SizedBox(height: 10),
              Text(
                _cameraErrorText(error),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              if (denied)
                AppButton(
                  label: 'Open settings',
                  size: AppButtonSize.sm,
                  variant: AppButtonVariant.secondary,
                  onPressed: () => unawaited(openAppSettings()),
                )
              else
                AppButton(
                  label: 'Try again',
                  size: AppButtonSize.sm,
                  variant: AppButtonVariant.secondary,
                  icon: Icons.refresh,
                  onPressed: onRetry,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result(
      {required this.item, required this.pending, required this.onAction});

  final LinenItem item;
  final String? pending;
  final ValueChanged<LinenScanAction> onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = context.texts;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  LinenStatusBadge(status: item.status, compact: false),
                  const Spacer(),
                  if (pending != null)
                    const AppSpinner(size: 15)
                  else
                    Icon(Icons.check_circle_outline,
                        size: 18, color: c.success),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                item.linenId,
                style: t.titleMedium
                    ?.copyWith(color: c.fg, fontFamily: 'monospace'),
              ),
              const SizedBox(height: 3),
              Text(
                '${item.itemType} · ${item.clientName}',
                style: t.bodySmall?.copyWith(color: c.fgMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        AppCard(
          title: 'Item info',
          child: LinenDetailGrid(
            entries: [
              ('Category', item.categoryLabel),
              ('Type', item.itemType),
              ('Client', item.clientName),
              ('Size', item.size ?? '—'),
              ('Color', item.color ?? '—'),
              ('Condition', item.conditionLabel),
              ('Wash count', Fmt.qty(item.washCount)),
              ('Last scanned', Fmt.date(item.lastScannedDate)),
              ('Location', item.location ?? '—'),
            ],
          ),
        ),
        const SizedBox(height: 10),
        AppCard(
          child: LinenQuickActions(
            actions: LinenScanAction.all,
            pendingValue: pending,
            onAction: onAction,
          ),
        ),
      ],
    );
  }
}
