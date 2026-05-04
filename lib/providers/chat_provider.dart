import 'package:flutter/foundation.dart';
import '../models/contact.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import '../services/local_db.dart';

class ChatProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();
  final WebSocketService _wsService = WebSocketService();
  final LocalDb _localDb = LocalDb();

  List<Contact> _contacts = [];
  List<Message> _messages = [];
  Contact? _selectedContact;
  VoidCallback? onScrollToBottom;  // Screen 设置，消息加载完成后调用
  final Map<int, List<Message>> _msgCache = {};  // contactId → 最近消息窗口
  bool _isLoading = false;
  String? _error;
  Map<String, dynamic>? incomingCall;
  Map<String, dynamic>? _callSignal;
  bool _isConnected = false;
  String? _baseUrl;
  String? _userId;
  
  // 未读消息计数
  Map<int, int> _unreadCounts = {};
  int _totalUnreadCount = 0;
  
  // 最后消息时间（key: "contact_1" 或 "group_2"）
  Map<String, DateTime> _lastMessageTime = {};
  // 最后消息内容预览
  Map<String, String> _lastMessagePreview = {};
  
  Map<int, int> get unreadCounts => _unreadCounts;
  int get totalUnreadCount => _totalUnreadCount;
  Map<String, DateTime> get lastMessageTime => _lastMessageTime;
  Map<String, String> get lastMessagePreview => _lastMessagePreview;

  /// 更新最后消息时间（群聊）
  void updateGroupLastMessage(int groupId, String content) {
    _lastMessageTime['group_$groupId'] = DateTime.now();
    _lastMessagePreview['group_$groupId'] = content;
    notifyListeners();
  }

  /// 从后端加载最新消息时间（用于列表排序）
  Future<void> loadLatestMessages() async {
    try {
      final latest = await _apiService.getLatestMessages();
      for (final item in latest) {
        final time = DateTime.tryParse(item['created_at'] ?? '') ?? DateTime.now();
        final content = item['content'] ?? '';
        if (item['contact_id'] != null) {
          _lastMessageTime['contact_${item['contact_id']}'] = time;
          _lastMessagePreview['contact_${item['contact_id']}'] = content;
        } else if (item['group_id'] != null) {
          _lastMessageTime['group_${item['group_id']}'] = time;
          _lastMessagePreview['group_${item['group_id']}'] = content;
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('loadLatestMessages: $e');
    }
  }

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

      case "call_invite":
        incomingCall = data;
        break;
      case "call_accept":
      case "call_reject":
      case "call_hangup":
      case "call_ice":
        _callSignal = {"type": type, "data": data};
        break;
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
      
      // 写入本地缓存
      _localDb.upsertMessage(newMessage);
      
      // 更新最后消息时间
      if (newMessage.contactId != null) {
        _lastMessageTime['contact_${newMessage.contactId}'] = newMessage.createdAt;
        _lastMessagePreview['contact_${newMessage.contactId}'] = newMessage.content;
        notifyListeners();
      }
      
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

  /// 选择联系人 — SQLite 秒读，增量同步
  void selectContact(Contact contact) {
    final prevId = _selectedContact?.id;
    if (prevId != null) {
      _msgCache[prevId] = List.from(_messages);  // 缓存当前列表
    }
    _selectedContact = contact;
    
    // 从缓存或本地 DB 秒取
    if (_msgCache.containsKey(contact.id)) {
      _messages = _msgCache[contact.id]!;
      notifyListeners();
      onScrollToBottom?.call();  // 内存缓存命中也要滚底
    } else {
      _messages = [];
      notifyListeners();
      _loadLocalThenSync(contact.id);
      return;
    }
    
    // 后台增量同步
    markContactMessagesAsRead(contact.id);
    _syncFromServer(contact.id);
  }

  Future<void> _loadLocalThenSync(int contactId) async {
    try {
      final cached = await _localDb.getContactMessages(contactId);
      if (cached.isNotEmpty && _selectedContact?.id == contactId) {
        _messages = cached;
        _msgCache[contactId] = cached;
        notifyListeners();
        onScrollToBottom?.call();  // 缓存加载完成→滚底
      }
    } catch (_) {}
    if (_selectedContact?.id == contactId) {
      _syncFromServer(contactId);
    }
  }

  /// 从服务器增量同步，不覆盖已有消息
  Future<void> _syncFromServer(int contactId) async {
    try {
      final serverMsgs = await _apiService.getMessages(contactId);
      serverMsgs.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      
      if (_selectedContact?.id != contactId) return;  // 已切走
      
      // 增量合并：只追加本地没有的新消息
      final existingIds = _messages.map((m) => m.id).toSet();
      final newMsgs = serverMsgs.where((m) => !existingIds.contains(m.id)).toList();
      
      if (newMsgs.isNotEmpty) {
        _messages.addAll(newMsgs);
        _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        _localDb.upsertMessages(newMsgs);
        _msgCache[contactId] = List.from(_messages);
        onScrollToBottom?.call();  // 有新消息→滚底
      }
      
      _error = null;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  bool _loadingMore = false;
  bool get loadingMore => _loadingMore;

  /// 上滑加载更早历史消息
  Future<void> loadMoreMessages(int contactId) async {
    if (_loadingMore || _messages.isEmpty) return;
    _loadingMore = true;
    final oldest = _messages.first.createdAt;
    
    try {
      final older = await _localDb.getContactMessages(contactId, limit: 200);
      final newOnes = older.where((m) => m.createdAt.isBefore(oldest)).toList();
      if (newOnes.isNotEmpty && _selectedContact?.id == contactId) {
        _messages.insertAll(0, newOnes);
        _msgCache[contactId] = List.from(_messages);
        notifyListeners();
      }
    } catch (_) {}
    _loadingMore = false;
  }

  /// 通过 ID 选择联系人
  void selectContactById(int contactId) {
    final contact = _contacts.firstWhere(
      (c) => c.id == contactId,
      orElse: () => _contacts.first,
    );
    selectContact(contact);
  }

  /// 删除消息（从本地列表移除）
  void removeMessage(int messageId) {
    _messages.removeWhere((m) => m.id == messageId);
    notifyListeners();
  }

  /// 更新联系人置顶状态
  void updateContactPin(int contactId, bool isPinned) {
    final idx = _contacts.indexWhere((c) => c.id == contactId);
    if (idx != -1) {
      _contacts[idx] = Contact(
        id: _contacts[idx].id,
        displayName: _contacts[idx].displayName,
        portalUrl: _contacts[idx].portalUrl,
        avatar: _contacts[idx].avatar,
        note: _contacts[idx].note,
        isFavorite: _contacts[idx].isFavorite,
        isPinned: isPinned,
        isActive: _contacts[idx].isActive,
        createdAt: _contacts[idx].createdAt,
      );
      notifyListeners();
    }
  }

  /// 清空当前消息列表
  void clearMessages() {
    _messages.clear();
    notifyListeners();
  }

  /// 删除联系人（从本地列表移除）
  void removeContact(int contactId) {
    _contacts.removeWhere((c) => c.id == contactId);
    _unreadCounts.remove(contactId);
    _totalUnreadCount = _unreadCounts.values.fold(0, (sum, count) => sum + count);
    notifyListeners();
  }

  /// 加载消息历史（外部调用时增量合并）
  Future<void> loadMessages(int contactId) async {
    _isLoading = true;
    notifyListeners();
    try {
      final messages = await _apiService.getMessages(contactId);
      messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      if (_selectedContact?.id != contactId) return;
      
      final existingIds = _messages.map((m) => m.id).toSet();
      final newMsgs = messages.where((m) => !existingIds.contains(m.id)).toList();
      if (newMsgs.isNotEmpty) {
        _messages.addAll(newMsgs);
        _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      }
      _error = null;
      _localDb.upsertMessages(messages);
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
      
      // 添加到本地消息列表
      _messages.add(message);
      
      // 同时通过 WebSocket 发送（用于实时通知）
      _wsService.sendTextMessage(_selectedContact!.id, content);
      
      // 更新最后消息时间
      _lastMessageTime['contact_${_selectedContact!.id}'] = DateTime.now();
      _lastMessagePreview['contact_${_selectedContact!.id}'] = content;
      
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
