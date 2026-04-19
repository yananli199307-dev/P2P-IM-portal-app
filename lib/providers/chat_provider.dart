import 'package:flutter/foundation.dart';
import '../models/contact.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';

class ChatProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();
  final WebSocketService _wsService = WebSocketService();

  List<Contact> _contacts = [];
  List<Message> _messages = [];
  Contact? _selectedContact;
  bool _isLoading = false;
  String? _error;
  bool _isConnected = false;
  String? _baseUrl;
  String? _userId;

  List<Contact> get contacts => _contacts;
  List<Message> get messages => _messages;
  Contact? get selectedContact => _selectedContact;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isConnected => _isConnected;

  /// 初始化 WebSocket 连接
  Future<void> initWebSocket({
    required String baseUrl,
    required String userId,
  }) async {
    _baseUrl = baseUrl;
    _userId = userId;
    
    await _wsService.connect(
      baseUrl: baseUrl,
      token: userId,
      onMessage: _handleWebSocketMessage,
      onConnect: () {
        _isConnected = true;
        notifyListeners();
        if (kDebugMode) {
          print('[ChatProvider] WebSocket connected');
        }
      },
      onDisconnect: () {
        _isConnected = false;
        notifyListeners();
        if (kDebugMode) {
          print('[ChatProvider] WebSocket disconnected');
        }
      },
    );
  }

  /// 处理 WebSocket 消息
  void _handleWebSocketMessage(Map<String, dynamic> message) {
    final type = message['type'];
    final data = message['data'];
    
    if (kDebugMode) {
      print('[ChatProvider] WebSocket message: $type');
    }
    
    switch (type) {
      case 'new_message':
        _handleNewMessage(data);
        break;
      case 'ack':
        // 确认收到，无需处理
        break;
      case 'error':
        _error = data['message'];
        notifyListeners();
        break;
      case 'pong':
        // 心跳响应
        break;
    }
  }

  /// 处理新消息
  void _handleNewMessage(Map<String, dynamic> data) {
    try {
      final newMessage = Message.fromJson(data);
      
      // 如果当前正在查看该联系人，添加到消息列表
      if (newMessage.contactId == _selectedContact?.id) {
        _messages.add(newMessage);
        notifyListeners();
      }
      
      // TODO: 显示通知（如果不在当前聊天界面）
    } catch (e) {
      if (kDebugMode) {
        print('[ChatProvider] Error handling new message: $e');
      }
    }
  }

  /// 加载联系人列表
  Future<void> loadContacts() async {
    _isLoading = true;
    notifyListeners();

    try {
      _contacts = await _apiService.getContacts();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 添加联系人
  Future<void> addContact(String name, String portalUrl) async {
    try {
      final contact = await _apiService.addContact(name, portalUrl);
      _contacts.add(contact);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// 选择联系人
  void selectContact(Contact contact) {
    _selectedContact = contact;
    _messages = [];
    notifyListeners();
    loadMessages(contact.id);
  }

  /// 加载消息历史
  Future<void> loadMessages(int contactId) async {
    _isLoading = true;
    notifyListeners();

    try {
      _messages = await _apiService.getMessages(contactId);
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 发送消息
  Future<void> sendMessage(String content) async {
    if (_selectedContact == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      // 先通过 HTTP API 发送
      final message = await _apiService.sendMessage(
        _selectedContact!.id,
        content,
      );
      
      // 添加到本地消息列表（WebSocket 也会推送，但先添加可以立即显示）
      _messages.add(message);
      
      // 同时通过 WebSocket 发送（用于实时通知）
      _wsService.sendTextMessage(_selectedContact!.id, content);
      
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 断开 WebSocket
  Future<void> disconnect() async {
    await _wsService.disconnect();
    _isConnected = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _wsService.disconnect();
    super.dispose();
  }
}
