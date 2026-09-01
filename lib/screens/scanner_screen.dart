import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/linen_service.dart';
import '../services/garment_service.dart';
import '../models/garment_tag.dart';

class ScannerScreen extends StatefulWidget {
  final String? mode; // 'linen', 'garment', or null (auto-detect)

  const ScannerScreen({super.key, this.mode});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  MobileScannerController? _cameraController;
  final _manualCtrl = TextEditingController();
  final _manualKey = GlobalKey<FormState>();
  bool _scanning = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cameraController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _manualCtrl.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (!_scanning) return;
    final code = capture.barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;

    setState(() => _scanning = false);
    _processCode(code);
  }

  Future<void> _processCode(String rawCode) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final auth = context.read<AuthService>();
    final code = _extractCode(rawCode);

    // Determine type based on pattern or forced mode
    if (widget.mode == 'linen' || (widget.mode == null && code.startsWith('LL-'))) {
      await _lookupLinen(auth.token!, code);
    } else if (widget.mode == 'garment' || widget.mode == null) {
      await _lookupGarment(code, rawCode);
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  String _extractCode(String raw) {
    // If it's a URL like https://public.lovelaundry.lk/track?tag=abc123
    if (raw.contains('tag=')) {
      final uri = Uri.parse(raw);
      return uri.queryParameters['tag'] ?? raw;
    }
    return raw.trim();
  }

  Future<void> _lookupLinen(String token, String code) async {
    final service = LinenService(token: token);
    final linen = await service.lookupByCode(code);

    if (!mounted) return;

    if (linen != null) {
      Navigator.pushReplacementNamed(context, '/linen-detail', arguments: linen);
    } else {
      setState(() => _error = 'Linen not found: $code');
      _resumeScanning();
    }
  }

  Future<void> _lookupGarment(String code, String rawCode) async {
    final service = GarmentService();
    GarmentTag? tag;

    // Try direct code lookup first
    tag = await service.lookupByCode(code);

    // If that fails and raw was a URL, try tracking endpoint
    if (tag == null && rawCode.contains('track')) {
      tag = await service.getTracking(code);
    }

    if (!mounted) return;

    if (tag != null) {
      Navigator.pushReplacementNamed(context, '/garment-detail', arguments: tag);
    } else {
      setState(() => _error = 'Tag not found: $code');
      _resumeScanning();
    }
  }

  void _resumeScanning() {
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _error = null;
          _scanning = true;
        });
      }
    });
  }

  Future<void> _manualLookup() async {
    if (!_manualKey.currentState!.validate()) return;
    final code = _manualCtrl.text.trim();
    _manualCtrl.clear();
    await _processCode(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.mode == 'linen'
              ? 'Scan Linen Tag'
              : widget.mode == 'garment'
                  ? 'Scan Garment Tag'
                  : 'Scan QR Code',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on, color: Colors.white),
            onPressed: () => _cameraController?.toggleTorch(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Camera view
          Expanded(
            flex: 3,
            child: Stack(
              alignment: Alignment.center,
              children: [
                MobileScanner(
                  controller: _cameraController,
                  onDetect: _onDetect,
                ),
                // Scanning overlay
                Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white54, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                // Loading overlay
                if (_loading)
                  Container(
                    color: Colors.black54,
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),

          // Manual entry + error
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Error
                  if (_error != null)
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.red, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Manual entry
                  Form(
                    key: _manualKey,
                    child: Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _manualCtrl,
                            textInputAction: TextInputAction.go,
                            onFieldSubmitted: (_) => _manualLookup(),
                            decoration: InputDecoration(
                              hintText: 'Enter code manually (LL-XXXXXX)',
                              hintStyle: TextStyle(
                                  fontSize: 13, color: Colors.grey[400]),
                              prefixIcon: const Icon(Icons.keyboard, size: 20),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              isDense: true,
                            ),
                            validator: (v) => v == null || v.trim().isEmpty
                                ? 'Enter a code'
                                : null,
                          ),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: _loading ? null : _manualLookup,
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.grey[900],
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.arrow_forward,
                                color: Colors.white, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // Tip
                  Text(
                    'Point camera at a QR code or enter code manually',
                    style: TextStyle(fontSize: 12, color: Colors.grey[400]),
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
