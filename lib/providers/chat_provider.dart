import 'package:flutter/foundation.dart';
import '../models/contact.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import '../services/local_db.dart';
import '../services/webrtc_service.dart';

class ChatProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();
  final WebSocketService _wsService = WebSocketService();
  final LocalDb _localDb = LocalDb();
  final WebRTCService _webrtc = WebRTCService();

  List<Contact> _contacts = [];
  List<Message> _messages = [];
  Contact? _selectedContact;
  VoidCallback? onScrollToBottom;
  void Function(String content)? onAgentReply;  // Screen 设置，消息加载完成后调用
  void Function(Map<String, dynamic> data)? onContactRequestReceived; // 收到新加好友申请的回调
  final Map<int, List<Message>> _msgCache = {};  // contactId → 最近消息窗口
  final Map<int, List<Map<String, dynamic>>> _groupCache = {};

  Map<int, List<Message>> get msgCache => _msgCache;
  Map<int, List<Map<String, dynamic>>> get groupCache => _groupCache;
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
  /// 从内存缓存取最新消息预览（不调后端，即时）
  void loadLatestMessages() {
    // 私聊 + My Agent
    for (final c in _contacts) {
      final msgs = _msgCache[c.id];
      if (msgs != null && msgs.isNotEmpty) {
        _lastMessageTime['contact_${c.id}'] = msgs.last.createdAt;
        _lastMessagePreview['contact_${c.id}'] = msgs.last.content;
      }
    }
    // My Agent
    final agentMsgs = _msgCache[0];
    if (agentMsgs != null && agentMsgs.isNotEmpty) {
      _lastMessageTime['contact_0'] = agentMsgs.last.createdAt;
      _lastMessagePreview['contact_0'] = agentMsgs.last.content;
    }
    // 群聊
    for (final entry in _groupCache.entries) {
      final msgs = entry.value;
      if (msgs.isNotEmpty) {
        final last = msgs.last;
        _lastMessageTime['group_${entry.key}'] = DateTime.tryParse(last['created_at'] ?? '') ?? DateTime.now();
        _lastMessagePreview['group_${entry.key}'] = last['content'] ?? '';
      }
    }
    notifyListeners();
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
      // 后端 /ws 只接受 user_id 数字鉴权,不要传 JWT(access_token)
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

      case "call_invite":
        // 来电:记录信令,UI 监听 incomingCall 弹窗
        incomingCall = {
          ...?data,
          'from_user_id': message['from_user_id'],
          'from_contact_id': message['from_contact_id'],
        };
        // 主叫已写"呼叫中"那条记录;此处记录被叫端收到的来电时间(可选)
        notifyListeners();
        break;
      case "call_accept":
        // 主叫:对方接听,把 answer SDP 喂给 WebRTC
        if (data?['sdp'] != null) {
          _webrtc.onCallAccepted(data['sdp']);
        }
        break;
      case "call_reject":
        recordCallEnd('rejected');
        _webrtc.onPeerHangup();
        incomingCall = null;
        notifyListeners();
        break;
      case "call_hangup":
        recordCallEnd('hangup');
        _webrtc.onPeerHangup();
        incomingCall = null;
        notifyListeners();
        break;
      case "call_ice":
        // ICE candidate 增量(remote desc 未就绪时会自动缓冲)
        if (data != null) {
          _webrtc.onIceCandidate(Map<String, dynamic>.from(data));
        }
        break;
      case 'new_message':
        _handleNewMessage(data);
        break;
      case 'contact_added':
        // 联系人列表变化(本机同意了申请,或对方同意了我的申请回调过来)
        loadContacts();
        break;
      case 'request_received':
        // 收到新的加好友申请,通知 UI 刷新"新的请求"列表
        onContactRequestReceived?.call(data ?? {});
        break;
      case 'agent_reply':
        final content = data?['content'] ?? message['content'] ?? '';
        if (content.isNotEmpty) {
          final msg = Message(
            id: DateTime.now().millisecondsSinceEpoch,
            contactId: 0,
            content: content,
            type: MessageType.text,
            isFromMe: false,
            createdAt: DateTime.now(),
          );
          _localDb.upsertMessage(msg);
          _msgCache.putIfAbsent(0, () => []);
          _msgCache[0]!.add(msg);
          onAgentReply?.call(content);
        }
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
      
      // 更新内存缓存（未选中时也缓存，下次秒开）
      if (newMessage.contactId != null) {
        _msgCache.putIfAbsent(newMessage.contactId!, () => []);
        _msgCache[newMessage.contactId!]!.add(newMessage);
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
      // 预加载所有聊天的最近消息到内存
      _preloadAllMessages();
      _preloadAllGroups();
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

  /// 选择联系人 — 内存已预加载，直接取
  void selectContact(Contact contact) {
    final prevId = _selectedContact?.id;
    if (prevId != null) {
      _msgCache[prevId] = List.from(_messages);
    }
    _selectedContact = contact;
    
    if (_msgCache.containsKey(contact.id)) {
      _messages = _msgCache[contact.id]!;
    } else {
      _messages = [];
    }
    notifyListeners();
    
    markContactMessagesAsRead(contact.id);
    _syncFromServer(contact.id);
  }

  /// 加载当前联系人的消息（由 Screen 在 initState 调用，确保页面已创建）
  Future<void> loadCurrentMessages() async {
    final contactId = _selectedContact?.id;
    if (contactId == null) return;
    markContactMessagesAsRead(contactId);
    await _loadLocalThenSync(contactId);
  }

  /// 预加载所有聊天的最近消息到内存，并后台从服务器同步离线消息
  void _preloadAllMessages() {
    // 1. 本地缓存先放进内存
    _localDb.getContactMessages(0).then((msgs) {
      if (msgs.isNotEmpty) _msgCache[0] = msgs;
      _syncAgentFromServer();
    });
    for (final c in _contacts) {
      _localDb.getContactMessages(c.id).then((msgs) {
        if (msgs.isNotEmpty) _msgCache[c.id] = msgs;
        _syncFromServer(c.id);
      });
    }
  }


  void _preloadAllGroups() async {
    try {
      final groups = await _apiService.getGroups();
      for (final g in groups) {
        final id = g['id'] as int? ?? 0;
        final isOwner = g['is_owner'] == true;
        final uuid = g['group_uuid'] as String? ?? g['group_id'] as String?;
        if (id > 0) {
          final cached = await _localDb.getCachedGroupMessages(id);
          if (cached.isNotEmpty) _groupCache[id] = cached;
          if (isOwner) {
            _syncGroupFromServer(id);
          } else if (uuid != null) {
            _syncNonOwnerGroup(uuid, id);
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _syncNonOwnerGroup(String uuid, int localId) async {
    try {
      final serverMsgs = await _apiService.getGroupMessagesByUuid(uuid);
      // 覆盖为本地 ID 保证缓存一致
      for (final m in serverMsgs) { m['group_id'] = localId; }
      final cached = _groupCache[localId] ?? [];
      final existingIds = cached.map((m) => m['id']).toSet();
      final newMsgs = serverMsgs.where((m) => !existingIds.contains(m['id'])).toList();
      if (newMsgs.isNotEmpty) {
        _groupCache[localId] = [...cached, ...newMsgs];
        _localDb.upsertGroupMessages(newMsgs);
      } else if (cached.isEmpty) {
        _groupCache[localId] = serverMsgs;
        _localDb.upsertGroupMessages(serverMsgs);
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _syncGroupFromServer(int groupId) async {
    try {
      final serverMsgs = await _apiService.getGroupMessages(groupId, since: null);
      final cached = _groupCache[groupId] ?? [];
      final existingIds = cached.map((m) => m['id']).toSet();
      final newMsgs = serverMsgs.where((m) => !existingIds.contains(m['id'])).toList();
      if (newMsgs.isNotEmpty) {
        _groupCache[groupId] = [...cached, ...newMsgs];
        _localDb.upsertGroupMessages(newMsgs);
      } else if (cached.isEmpty) {
        _groupCache[groupId] = serverMsgs;
        _localDb.upsertGroupMessages(serverMsgs);
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _syncAgentFromServer() async {
    try {
      final cached = _msgCache[0];
      final latest = cached != null && cached.isNotEmpty ? cached.last.createdAt : null;
      final serverMsgs = await _apiService.getAgentMessages(since: latest?.toIso8601String());
      if (serverMsgs.isEmpty) return;
      final newMsgs = serverMsgs.where((m) => !(cached ?? []).any((c) => c.id.toString() == m['id'].toString())).toList();
      if (newMsgs.isNotEmpty) {
        final converted = newMsgs.reversed.map((m) => Message(
          id: int.tryParse(m['id'].toString()) ?? 0,
          contactId: 0,
          content: m['content'] ?? '',
          type: MessageType.text,
          isFromMe: m['is_from_owner'] == true,
          createdAt: DateTime.tryParse(m['created_at'] ?? '') ?? DateTime.now(),
        )).toList();
        _msgCache[0] = [...converted, ...(cached ?? [])];
        _localDb.upsertMessages(converted);
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _loadLocalThenSync(int contactId) async {
    try {
      final cached = await _localDb.getContactMessages(contactId);
      if (cached.isNotEmpty && _selectedContact?.id == contactId) {
        _messages = cached;
        _msgCache[contactId] = cached;
        notifyListeners();
        onScrollToBottom?.call();
      }
    } catch (_) {}
    if (_selectedContact?.id == contactId) {
      _syncFromServer(contactId);
    }
  }

  /// 从服务器增量同步，不覆盖已有消息
  Future<void> _syncFromServer(int contactId) async {
    try {
      // 计算本地最新消息时间，传给服务器做增量同步
      final cached = _msgCache[contactId];
      final latest = cached != null && cached.isNotEmpty ? cached.last.createdAt : null;
      final serverMsgs = await _apiService.getMessages(contactId,
        since: latest?.toIso8601String(),
      );
      serverMsgs.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      
      // 没有人看这个聊天→更新缓存和DB后返回
      if (_selectedContact?.id != contactId) {
        if (serverMsgs.isNotEmpty) {
          _msgCache[contactId] = serverMsgs;
          _localDb.upsertMessages(serverMsgs);
          notifyListeners();
        }
        return;
      }
      
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

    // 先本地显示（和群聊/Agent一致）
    final tempMsg = Message(
      id: DateTime.now().millisecondsSinceEpoch,
      contactId: _selectedContact!.id,
      content: content,
      type: MessageType.text,
      isFromMe: true,
      createdAt: DateTime.now(),
      replyToMessageId: replyToMessageId,
      replyToContent: replyToContent,
      replyToSenderName: replyToSenderName,
    );
    _messages.add(tempMsg);
    _lastMessageTime['contact_${_selectedContact!.id}'] = DateTime.now();
    _lastMessagePreview['contact_${_selectedContact!.id}'] = content;
    notifyListeners();

    // 后台通过 HTTP API 发送
    try {
      await _apiService.sendMessage(
        _selectedContact!.id,
        content,
        replyToMessageId: replyToMessageId,
        replyToContent: replyToContent,
        replyToSenderName: replyToSenderName,
      );
      _wsService.sendTextMessage(_selectedContact!.id, content);
      _error = null;
    } catch (e) {
      _error = e.toString();
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

  // ========== WebRTC 通话 ==========

  /// 暴露 WebRTC 单例给 UI(CallScreen)
  WebRTCService get webrtc => _webrtc;

  /// 发起通话 — 由 +号面板/通话按钮调用
  /// targetUserId: 对端 user_id;targetContactId: 对端 contact.id
  Future<void> startCall({
    required int targetUserId,
    required int targetContactId,
    required bool video,
  }) async {
    _webrtc.peerUserId = targetUserId;
    _webrtc.peerContactId = targetContactId;
    _webrtc.onSignal = _sendCallSignal;
    await _webrtc.init();
    await _webrtc.startCall(video);
  }

  /// 接听来电 — 由 IncomingCall UI 调用
  Future<void> acceptIncomingCall() async {
    final ic = incomingCall;
    if (ic == null) return;
    final sdp = ic['sdp'] as String?;
    final videoFlag = ic['type'] == 'video';
    final fromUserId = ic['from_user_id'] as int?;
    final fromContactId = ic['from_contact_id'] as int?;
    if (sdp == null) return;
    _webrtc.peerUserId = fromUserId;
    _webrtc.peerContactId = fromContactId;  // 用对端在我这边的 Contact.id 作为回信令目标
    _webrtc.onSignal = _sendCallSignal;
    await _webrtc.init();
    await _webrtc.acceptCall(sdp, videoFlag);
    incomingCall = null;
    notifyListeners();
  }

  /// 拒绝来电
  void rejectIncomingCall() {
    final fromContactId = incomingCall?['from_contact_id'] as int?;
    _wsService.sendMessage('call_reject', {
      'target_user_id': fromContactId,
      'data': {},
    });
    incomingCall = null;
    notifyListeners();
  }

  /// 主动挂断 — 由 CallScreen 挂断按钮调用
  Future<void> hangupCall() async {
    await recordCallEnd('hangup');
    _webrtc.hangup();
    notifyListeners();
  }

  /// 把通话结果写入聊天记录(只有主叫端写,被叫端通过 new_message 同步收到)
  Future<void> recordCallEnd(String reason) async {
    final peerContactId = _webrtc.peerContactId;
    final isCaller = _webrtc.isCaller;
    final isVideoCall = _webrtc.isVideo;
    final startedAt = _webrtc.startedAt;
    if (peerContactId == null || !isCaller) return;
    final kind = isVideoCall ? '视频通话' : '语音通话';
    String content;
    if (startedAt != null) {
      final sec = DateTime.now().difference(startedAt).inSeconds;
      final m = (sec ~/ 60).toString().padLeft(2, '0');
      final s = (sec % 60).toString().padLeft(2, '0');
      content = '📞 $kind 时长 $m:$s';
    } else if (reason == 'rejected') {
      content = '📞 $kind 对方已拒接';
    } else {
      content = '📞 $kind 未接通';
    }
    try {
      await _apiService.sendMessage(peerContactId, content);
    } catch (e) {
      debugPrint('[Call] recordCallEnd failed: $e');
    }
  }

  /// 清除来电状态(UI 已处理)
  void clearIncomingCall() {
    incomingCall = null;
    notifyListeners();
  }

  /// WebRTCService 回调 → 把信令通过 WebSocket 发出去
  void _sendCallSignal(String type, Map<String, dynamic> data) {
    // 协议:target_user_id 实际是对端 Contact.id(后端按 Contact 表查 portal_url)
    final target = _webrtc.peerContactId;
    if (target == null) {
      debugPrint('[Call] _sendCallSignal: no peerContactId');
      return;
    }
    _wsService.sendMessage(type, {
      'target_user_id': target,
      'data': data,
    });
  }

  @override
  void dispose() {
    _wsService.disconnect();
    super.dispose();
  }
}
