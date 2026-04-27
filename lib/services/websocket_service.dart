import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// WebSocket 消息回调类型
typedef OnMessageCallback = void Function(Map<String, dynamic> message);
typedef OnConnectCallback = void Function();
typedef OnDisconnectCallback = void Function();

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  WebSocket? _socket;
  String? _token;
  String? _baseUrl;
  bool _isAgent = false;
  
  // 连接状态
  bool get isConnected => _socket != null;
  
  // 回调
  OnMessageCallback? onMessage;
  OnConnectCallback? onConnect;
  OnDisconnectCallback? onDisconnect;
  
  // 重连配置
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int maxReconnectAttempts = 5;
  static const Duration reconnectDelay = Duration(seconds: 3);

  /// 初始化并连接
  Future<void> connect({
    required String baseUrl,
    required String token,
    bool isAgent = false,
    OnMessageCallback? onMessage,
    OnConnectCallback? onConnect,
    OnDisconnectCallback? onDisconnect,
  }) async {
    _baseUrl = baseUrl;
    _token = token;
    _isAgent = isAgent;
    this.onMessage = onMessage;
    this.onConnect = onConnect;
    this.onDisconnect = onDisconnect;
    
    await _connect();
  }

  /// 建立 WebSocket 连接
  Future<void> _connect() async {
    if (_socket != null) {
      await disconnect();
    }

    try {
      // 将 http:// 或 https:// 转换为 ws:// 或 wss://
      String wsUrl = _baseUrl!.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://');
      
      // 移除 /api 后缀
      wsUrl = wsUrl.replaceAll('/api', '');
      
      // 添加 WebSocket 路径
      final path = _isAgent ? '/ws/agent' : '/ws/agent';
      wsUrl = '$wsUrl$path?token=$_token';
      
      if (kDebugMode) {
        print('[WebSocket] Connecting to: $wsUrl');
      }
      
      _socket = await WebSocket.connect(wsUrl);
      _reconnectAttempts = 0;
      
      if (kDebugMode) {
        print('[WebSocket] Connected');
      }
      
      onConnect?.call();
      
      // 监听消息
      _socket!.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );
      
      // 发送心跳
      _startHeartbeat();
      
    } catch (e) {
      if (kDebugMode) {
        print('[WebSocket] Connection error: $e');
      }
      _scheduleReconnect();
    }
  }

  /// 处理收到的消息
  void _onMessage(dynamic data) {
    try {
      final message = jsonDecode(data as String);
      
      if (kDebugMode) {
        print('[WebSocket] Received: $message');
      }
      
      onMessage?.call(message);
    } catch (e) {
      if (kDebugMode) {
        print('[WebSocket] Error parsing message: $e');
      }
    }
  }

  /// 处理错误
  void _onError(error) {
    if (kDebugMode) {
      print('[WebSocket] Error: $error');
    }
  }

  /// 连接关闭
  void _onDone() {
    if (kDebugMode) {
      print('[WebSocket] Connection closed');
    }
    
    _socket = null;
    onDisconnect?.call();
    _scheduleReconnect();
  }

  /// 计划重连
  void _scheduleReconnect() {
    if (_reconnectAttempts >= maxReconnectAttempts) {
      if (kDebugMode) {
        print('[WebSocket] Max reconnect attempts reached');
      }
      return;
    }
    
    _reconnectAttempts++;
    
    if (kDebugMode) {
      print('[WebSocket] Reconnecting in ${reconnectDelay.inSeconds}s (attempt $_reconnectAttempts/$maxReconnectAttempts)');
    }
    
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(reconnectDelay, _connect);
  }

  /// 发送消息
  void sendMessage(String type, Map<String, dynamic> data) {
    if (_socket == null || _socket!.readyState != WebSocket.open) {
      if (kDebugMode) {
        print('[WebSocket] Cannot send, not connected');
      }
      return;
    }
    
    final message = jsonEncode({
      'type': type,
      'data': data,
    });
    
    _socket!.add(message);
    
    if (kDebugMode) {
      print('[WebSocket] Sent: $message');
    }
  }

  /// 发送普通消息
  void sendTextMessage(int contactId, String content) {
    sendMessage('message', {
      'contact_id': contactId,
      'content': content,
      'message_type': 'text',
    });
  }

  /// 发送 Agent 回复（仅 Agent 可用）
  void sendAgentResponse(int targetUserId, int targetContactId, String content) {
    if (!_isAgent) {
      if (kDebugMode) {
        print('[WebSocket] Only agent can send agent_response');
      }
      return;
    }
    
    sendMessage('agent_response', {
      'target_user_id': targetUserId,
      'target_contact_id': targetContactId,
      'content': content,
    });
  }

  /// 发送正在输入状态
  void sendTyping(int contactId, bool isTyping) {
    sendMessage('typing', {
      'contact_id': contactId,
      'is_typing': isTyping,
    });
  }

  /// 心跳定时器
  Timer? _heartbeatTimer;
  
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      sendMessage('ping', {});
    });
  }

  /// 断开连接
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    
    if (_socket != null) {
      await _socket!.close();
      _socket = null;
    }
    
    onDisconnect?.call();
  }
}
