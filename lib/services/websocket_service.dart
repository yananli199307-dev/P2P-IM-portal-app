import 'dart:convert';
import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  WebSocketChannel? _channel;
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  
  Timer? _pingTimer;
  bool _isConnected = false;

  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  bool get isConnected => _isConnected;

  void connect(String token) {
    try {
      // 使用 user_id 作为 token 简化处理
      // 实际应该使用 JWT token
      final wsUrl = 'wss://agentp2p.cn/ws?token=$token';
      
      _channel = IOWebSocketChannel.connect(wsUrl);
      
      _channel!.stream.listen(
        (data) {
          _handleMessage(data);
        },
        onError: (error) {
          print('WebSocket error: $error');
          _isConnected = false;
          _connectionController.add(false);
        },
        onDone: () {
          print('WebSocket closed');
          _isConnected = false;
          _connectionController.add(false);
          _reconnect(token);
        },
      );

      _isConnected = true;
      _connectionController.add(true);
      
      // 启动心跳
      _startPing();
      
    } catch (e) {
      print('WebSocket connection error: $e');
      _isConnected = false;
      _connectionController.add(false);
    }
  }

  void _handleMessage(dynamic data) {
    try {
      final message = jsonDecode(data);
      _messageController.add(message);
      
      // 处理心跳响应
      if (message['type'] == 'pong') {
        print('Received pong');
      }
    } catch (e) {
      print('Error parsing message: $e');
    }
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isConnected) {
        send({'type': 'ping', 'data': {}});
      }
    });
  }

  void _reconnect(String token) {
    Future.delayed(const Duration(seconds: 5), () {
      if (!_isConnected) {
        print('Reconnecting...');
        connect(token);
      }
    });
  }

  void send(Map<String, dynamic> message) {
    if (_isConnected && _channel != null) {
      _channel!.sink.add(jsonEncode(message));
    }
  }

  void disconnect() {
    _pingTimer?.cancel();
    _channel?.sink.close();
    _isConnected = false;
    _connectionController.add(false);
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _connectionController.close();
  }
}
