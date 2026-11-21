import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

/// Bluetooth scanner service for connecting to Bluetooth barcode scanners.
/// Supports both SPP (Serial Port Profile) and HID devices.
class BluetoothScannerService {
  BluetoothScannerService._();

  static final BluetoothScannerService _instance = BluetoothScannerService._();
  factory BluetoothScannerService() => _instance;

  BluetoothConnection? _connection;
  StreamSubscription<BluetoothDiscoveryResult>? _discoverySubscription;
  final _scanBuffer = StringBuffer();
  final _scanCodeController = StreamController<String>.broadcast();
  final _statusController = StreamController<BluetoothStatus>.broadcast();
  final _receivedCodes = <String>[];

  /// Stream of scanned codes from Bluetooth scanner
  Stream<String> get scannedCodes => _scanCodeController.stream;

  /// Stream of connection status changes
  Stream<BluetoothStatus> get status => _statusController.stream;

  /// List of recently received codes (up to 100)
  List<String> get recentCodes => List.unmodifiable(_receivedCodes);

  /// Whether currently connected to a device
  bool get isConnected => _connection != null && _connection!.isConnected;

  /// Currently connected device
  BluetoothDevice? connectedDevice;

  /// Start discovering available Bluetooth devices
  Future<List<BluetoothDevice>> discoverDevices({Duration timeout = const Duration(seconds: 10)}) async {
    final devices = <BluetoothDevice>[];
    final completer = Completer<List<BluetoothDevice>>();

    try {
      await FlutterBluetoothSerial.instance.requestEnable();

      _discoverySubscription = FlutterBluetoothSerial.instance.startDiscovery().listen(
        (BluetoothDiscoveryResult result) {
          if (!devices.any((d) => d.address == result.device.address)) {
            devices.add(result.device);
          }
        },
        onError: (error) {
          debugPrint('Bluetooth discovery error: $error');
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.complete(devices);
          }
        },
        cancelOnError: false,
      );

      // Timeout if discovery takes too long
      Future.delayed(timeout, () {
        if (!completer.isCompleted) {
          _discoverySubscription?.cancel();
          completer.complete(devices);
        }
      });
    } catch (e) {
      debugPrint('Failed to start Bluetooth discovery: $e');
      if (!completer.isCompleted) {
        completer.complete(devices);
      }
    }

    return completer.future;
  }

  /// Connect to a Bluetooth device
  Future<bool> connect(BluetoothDevice device) async {
    try {
      _statusController.add(BluetoothStatus.connecting);

      // Close existing connection
      await disconnect();

      _connection = await BluetoothConnection.toAddress(device.address);
      connectedDevice = device;

      _statusController.add(BluetoothStatus.connected);

      // Start listening for incoming data
      _connection!.input?.listen(
        _onDataReceived,
        onDone: () {
          _statusController.add(BluetoothStatus.disconnected);
          _connection = null;
          connectedDevice = null;
        },
        onError: (error) {
          debugPrint('Bluetooth connection error: $error');
          _statusController.add(BluetoothStatus.error(error.toString()));
        },
      );

      return true;
    } catch (e) {
      debugPrint('Failed to connect to Bluetooth device: $e');
      _statusController.add(BluetoothStatus.error(e.toString()));
      _connection = null;
      connectedDevice = null;
      return false;
    }
  }

  /// Disconnect from current device
  Future<void> disconnect() async {
    try {
      await _discoverySubscription?.cancel();
      _discoverySubscription = null;
      await _connection?.close();
      _connection = null;
      connectedDevice = null;
      _scanBuffer.clear();
      _statusController.add(BluetoothStatus.disconnected);
    } catch (e) {
      debugPrint('Error disconnecting: $e');
    }
  }

  /// Handle incoming data from Bluetooth scanner
  void _onDataReceived(List<int> data) {
    final text = utf8.decode(data);
    _scanBuffer.write(text);

    // Check for newline or carriage return (common scanner suffixes)
    final bufferText = _scanBuffer.toString();
    if (bufferText.contains('\n') || bufferText.contains('\r')) {
      final code = bufferText
          .replaceAll('\n', '')
          .replaceAll('\r', '')
          .trim();

      if (code.isNotEmpty) {
        _processScannedCode(code);
      }

      _scanBuffer.clear();
    }
  }

  /// Process a scanned code
  void _processScannedCode(String code) {
    // Add to recent codes (max 100)
    _receivedCodes.insert(0, code);
    if (_receivedCodes.length > 100) {
      _receivedCodes.removeLast();
    }

    // Emit to stream
    _scanCodeController.add(code);
  }

  /// Clear recent codes
  void clearRecentCodes() {
    _receivedCodes.clear();
  }

  /// Dispose resources
  void dispose() {
    disconnect();
    _scanCodeController.close();
    _statusController.close();
  }
}

/// Bluetooth connection status
enum BluetoothStatus {
  disconnected,
  connecting,
  connected,
  error,
}

/// Extension for BluetoothStatus
extension BluetoothStatusExtension on BluetoothStatus {
  String get label => switch (this) {
        BluetoothStatus.disconnected => 'Disconnected',
        BluetoothStatus.connecting => 'Connecting...',
        BluetoothStatus.connected => 'Connected',
        BluetoothStatus.error => 'Error',
      };

  bool get isConnected => this == BluetoothStatus.connected;
  bool get isConnecting => this == BluetoothStatus.connecting;
  bool get isError => this == BluetoothStatus.error;
  bool get isDisconnected => this == BluetoothStatus.disconnected;
}
