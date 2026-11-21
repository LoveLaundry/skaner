import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../config/api_config.dart';
import '../../state/app_scope.dart';

/// Real-time sync service for instant updates from backend
/// Uses WebSocket connections for real-time data synchronization
class RealtimeSyncService {
  RealtimeSyncService._();

  static final RealtimeSyncService _instance = RealtimeSyncService._();
  factory RealtimeSyncService() => _instance;

  WebSocketChannel? _channel;
  final _statusController = StreamController<SyncStatus>.broadcast();
  final _eventController = StreamController<SyncEvent>.broadcast();
  Timer? _reconnectTimer;
  bool _isConnecting = false;
  bool _shouldReconnect = true;

  /// Stream of sync status changes
  Stream<SyncStatus> get status => _statusController.stream;

  /// Stream of real-time events from backend
  Stream<SyncEvent> get events => _eventController.stream;

  /// Current connection status
  SyncStatus get currentStatus => _channel != null && _isConnecting
      ? SyncStatus.connecting
      : _channel != null
          ? SyncStatus.connected
          : SyncStatus.disconnected;

  /// Connect to WebSocket server
  Future<void> connect(String token) async {
    if (_isConnecting) return;

    _isConnecting = true;
    _shouldReconnect = true;
    _statusController.add(SyncStatus.connecting);

    try {
      final wsUrl = Uri.parse('${ApiConfig.wsUrl}/ws?token=$token');
      _channel = WebSocketChannel.connect(wsUrl);

      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );

      _isConnecting = false;
      _statusController.add(SyncStatus.connected);
    } catch (e) {
      _isConnecting = false;
      _statusController.add(SyncStatus.error(e.toString()));
      _scheduleReconnect();
    }
  }

  /// Disconnect from WebSocket server
  Future<void> disconnect() async {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _channel?.sink.close();
    _channel = null;
    _isConnecting = false;
    _statusController.add(SyncStatus.disconnected);
  }

  /// Send message to server
  void send(Map<String, dynamic> data) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode(data));
    }
  }

  /// Subscribe to specific data types
  void subscribe(List<String> channels) {
    send({
      'type': 'subscribe',
      'channels': channels,
    });
  }

  /// Unsubscribe from channels
  void unsubscribe(List<String> channels) {
    send({
      'type': 'unsubscribe',
      'channels': channels,
    });
  }

  void _onMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      final event = SyncEvent.fromJson(data);
      _eventController.add(event);
    } catch (e) {
      debugPrint('Error parsing WebSocket message: $e');
    }
  }

  void _onError(error) {
    debugPrint('WebSocket error: $error');
    _statusController.add(SyncStatus.error(error.toString()));
    _scheduleReconnect();
  }

  void _onDone() {
    debugPrint('WebSocket connection closed');
    _statusController.add(SyncStatus.disconnected);
    if (_shouldReconnect) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (_shouldReconnect) {
        // Will reconnect when token is available
        // The calling app should handle reconnection with fresh token
      }
    });
  }

  void dispose() {
    disconnect();
    _statusController.close();
    _eventController.close();
  }
}

/// Sync connection status
enum SyncStatus {
  disconnected,
  connecting,
  connected,
  error,
}

/// Real-time sync event from backend
class SyncEvent {
  const SyncEvent({
    required this.type,
    required this.channel,
    required this.data,
    this.timestamp,
  });

  final String type;
  final String channel;
  final Map<String, dynamic> data;
  final String? timestamp;

  factory SyncEvent.fromJson(Map<String, dynamic> json) => SyncEvent(
        type: json['type'] as String,
        channel: json['channel'] as String,
        data: json['data'] as Map<String, dynamic>,
        timestamp: json['timestamp'] as String?,
      );

  bool get isLinenUpdate => channel == 'linen';
  bool get isBillUpdate => channel == 'bill';
  bool get isQuotationUpdate => channel == 'quotation';
  bool get isWorkerUpdate => channel == 'worker';
}
