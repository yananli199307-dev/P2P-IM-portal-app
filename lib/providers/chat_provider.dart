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
  
  // 未读消息计数
  Map<int, int> _unreadCounts = {};
  int _totalUnreadCount = 0;
  
  Map<int, int> get unreadCounts => _unreadCounts;
  int get totalUnreadCount => _totalUnreadCount;

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
    required String apiKey,
  }) async {
    _baseUrl = baseUrl;
    _userId = userId;
    
    await _wsService.connect(
      baseUrl: baseUrl,
      token: apiKey,
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
      
      // 如果当前正在查看该联系人，添加到消息列表并标记已读
      if (newMessage.contactId == _selectedContact?.id) {
        _messages.add(newMessage);
        // 如果是收到的消息，自动标记为已读
        if (!newMessage.isFromMe && newMessage.contactId != null) {
          markContactMessagesAsRead(newMessage.contactId!);
        }
        notifyListeners();
      } else if (!newMessage.isFromMe && newMessage.contactId != null) {
        // 不在当前聊天界面，增加未读计数
        incrementUnreadCount(newMessage.contactId!);
      }
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
      // 加载未读消息
      await loadUnreadMessages();
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
      await _apiService.addContact(name, portalUrl);
      // 申请已发送，等对方同意后刷新联系人
      await loadContacts();
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
    // 标记该联系人的消息为已读
    markContactMessagesAsRead(contact.id);
  }

  /// 通过 ID 选择联系人
  void selectContactById(int contactId) {
    final contact = _contacts.firstWhere(
      (c) => c.id == contactId,
      orElse: () => _contacts.first,
    );
    selectContact(contact);
  }

  /// 删除联系人（从本地列表移除）
  void removeContact(int contactId) {
    _contacts.removeWhere((c) => c.id == contactId);
    _unreadCounts.remove(contactId);
    _totalUnreadCount = _unreadCounts.values.fold(0, (sum, count) => sum + count);
    notifyListeners();
  }

  /// 加载消息历史
  Future<void> loadMessages(int contactId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final messages = await _apiService.getMessages(contactId);
      // 按时间排序（旧的在上面，新的在下面）
      messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      _messages = messages;
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 发送消息
  Future<void> sendMessage(String content, {int? replyToMessageId, String? replyToContent, String? replyToSenderName}) async {
    if (_selectedContact == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      // 先通过 HTTP API 发送
      final message = await _apiService.sendMessage(
        _selectedContact!.id,
        content,
        replyToMessageId: replyToMessageId,
        replyToContent: replyToContent,
        replyToSenderName: replyToSenderName,
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

  /// 加载未读消息
  Future<void> loadUnreadMessages() async {
    try {
      final unreadMessages = await _apiService.getUnreadMessages();
      
      // 按联系人统计未读数量
      _unreadCounts = {};
      for (final message in unreadMessages) {
        if (message.contactId != null) {
          _unreadCounts[message.contactId!] = (_unreadCounts[message.contactId!] ?? 0) + 1;
        }
      }
      
      // 计算总未读数
      _totalUnreadCount = _unreadCounts.values.fold(0, (sum, count) => sum + count);
      
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('[ChatProvider] Error loading unread messages: $e');
      }
    }
  }

  /// 标记联系人的所有消息为已读
  Future<void> markContactMessagesAsRead(int contactId) async {
    try {
      // 获取该联系人的未读消息
      final unreadMessages = await _apiService.getUnreadMessages();
      final contactUnreadMessages = unreadMessages.where((m) => m.contactId == contactId).toList();
      
      // 逐个标记为已读
      for (final message in contactUnreadMessages) {
        await _apiService.markMessageAsRead(message.id);
      }
      
      // 更新本地未读计数
      _unreadCounts.remove(contactId);
      _totalUnreadCount = _unreadCounts.values.fold(0, (sum, count) => sum + count);
      
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('[ChatProvider] Error marking messages as read: $e');
      }
    }
  }

  /// 更新未读计数（用于 WebSocket 收到新消息时）
  void incrementUnreadCount(int contactId) {
    _unreadCounts[contactId] = (_unreadCounts[contactId] ?? 0) + 1;
    _totalUnreadCount++;
    notifyListeners();
  }

  /// 发送文件消息
  Future<void> sendFileMessage(String filePath) async {
    if (_selectedContact == null) return;

    try {
      final message = await _apiService.sendFileMessage(_selectedContact!.id, filePath);
      _messages.add(message);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// 发送文件（Web 版，使用 bytes）
  Future<void> sendFileBytes(String fileName, List<int> bytes) async {
    if (_selectedContact == null) return;
    try {
      final fileData = await _apiService.uploadFileBytes(fileName, bytes);
      // 构建文件消息
      final message = Message(
        id: DateTime.now().millisecondsSinceEpoch,
        contactId: _selectedContact!.id,
        content: '📎 $fileName',
        type: fileData['file_type'] == 'image' ? MessageType.image : MessageType.file,
        fileUrl: fileData['file_url'],
        fileName: fileName,
        fileSize: fileData['file_size'],
        isFromMe: true,
        createdAt: DateTime.now(),
      );
      _messages.add(message);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _wsService.disconnect();
    super.dispose();
  }
}
