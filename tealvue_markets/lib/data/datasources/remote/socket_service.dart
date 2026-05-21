import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../../../core/constants/app_constants.dart';

class SocketService {
  IO.Socket? _socket;
  bool _isConnected = false;

  // Active symbols tracked per-subscriber so we can re-subscribe on reconnect
  // without each subscriber needing to manage the raw socket.
  final Set<String> _activeSymbols = {};

  // ── Broadcast streams ──────────────────────────────────────────
  final _tickController =
  StreamController<Map<String, dynamic>>.broadcast();
  final _connectedController = StreamController<void>.broadcast();
  final _disconnectedController = StreamController<void>.broadcast();

  Stream<Map<String, dynamic>> get tickStream => _tickController.stream;

  Stream<void> get connectedStream => _connectedController.stream;

  Stream<void> get disconnectedStream => _disconnectedController.stream;

  void connect() {
    if (_socket != null) {
      _socket!.disconnect();
      _socket!.dispose();
    }

    _socket = IO.io(
      AppConstants.socketUrl,
      IO.OptionBuilder()
          .setTransports(['polling', 'websocket'])
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(999)
          .setReconnectionDelay(2000)
          .setReconnectionDelayMax(10000)
          .setPath('/socket.io/')
          .build(),
    );

    _socket!.onConnect((_) {
      _isConnected = true;
      // Re-subscribe all active symbols after connect / reconnect.
      if (_activeSymbols.isNotEmpty) {
        _socket!.emit('subscribe', _activeSymbols.toList());
      }
      _connectedController.add(null);
    });

    _socket!.onDisconnect((_) {
      _isConnected = false;
      _disconnectedController.add(null);
    });

    _socket!.onReconnect((_) {
      _isConnected = true;
      if (_activeSymbols.isNotEmpty) {
        _socket!.emit('subscribe', _activeSymbols.toList());
      }
      _connectedController.add(null);
    });

    _socket!.on('ticker', (data) {
      if (data != null && !_tickController.isClosed) {
        _tickController.add(Map<String, dynamic>.from(data));
      }
    });

    _socket!.onConnectError((_) => _isConnected = false);
    _socket!.onError((_) => _isConnected = false);

    _socket!.connect();
  }

  void subscribe(List<String> symbols) {
    _activeSymbols.addAll(symbols);
    if (_isConnected && _socket != null) {
      _socket!.emit('subscribe', symbols);
    }
  }

  void unsubscribe(List<String> symbols) {
    _activeSymbols.removeAll(symbols);
    if (_isConnected && _socket != null) {
      _socket!.emit('unsubscribe', symbols);
    }
  }

  void disconnect() {
    _isConnected = false;
    _activeSymbols.clear();
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }
  void dispose() {
    disconnect();
    _tickController.close();
    _connectedController.close();
    _disconnectedController.close();
  }

  bool get isConnected => _isConnected;
}