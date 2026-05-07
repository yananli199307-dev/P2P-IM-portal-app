import 'dart:math';
import "package:flutter/foundation.dart" show kIsWeb;
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../models/contact.dart';
import '../models/message.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  // Portal 地址：Web 走本地代理（8080），手机使用安全默认值（登录后更新为实际 Portal URL）
  static String baseUrl = kIsWeb ? 'http://localhost:8080/api' : 'https://placeholder.local/api';
  
  late Dio _dio;
  String? _token;
  String? _portalUrl;

  void initialize() {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (_token != null) {
          options.headers['Authorization'] = 'Bearer $_token';
        }
        handler.next(options);
      },
      onError: (error, handler) {
        if (error.response?.statusCode == 401) {
          clearToken();
        }
        handler.next(error);
      },
    ));
  }

  // 设置 Portal URL
  Future<void> setPortalUrl(String url) async {
    _portalUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('portal_url', url);
    // 同步更新 Dio 的 baseUrl
    updateBaseUrl('$url/api');
  }

  /// 更新 API 基地址（用于手机切换 Portal）
  void updateBaseUrl(String newBaseUrl) {
    baseUrl = newBaseUrl;
    _dio.options.baseUrl = newBaseUrl;
  }

  Future<String?> getPortalUrl() async {
    if (_portalUrl != null) return _portalUrl;
    final prefs = await SharedPreferences.getInstance();
    _portalUrl = prefs.getString('portal_url');
    return _portalUrl;
  }

  Future<void> setToken(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
  }

  Future<String?> getToken() async {
    if (_token != null) return _token;
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
    return _token;
  }

  Future<void> clearToken() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('portal_url');
  }

  // ========== 认证 ==========
  
  /// 检查是否已初始化
  Future<Map<String, dynamic>> checkInitStatus() async {
    final response = await _dio.get('/auth/status');
    return response.data;
  }

  /// 初始化账号（首次使用）
  Future<User> initAccount(String password, {String? displayName}) async {
    final response = await _dio.post('/auth/init', data: {
      'password': password,
      'display_name': displayName ?? '管理员',
    });
    return User.fromJson(response.data);
  }

  /// 登录 - 使用 Portal URL + 密码
  Future<String> login(String portalUrl, String password) async {
    // 先设置 Portal URL
    await setPortalUrl(portalUrl);
    // 更新 Dio baseUrl 为目标 Portal（非 Web 平台必需绝对 URL）
    updateBaseUrl('$portalUrl/api');
    
    final response = await _dio.post('/auth/login', data: {
      'portal_url': portalUrl,
      'password': password,
    });
    final token = response.data['access_token'];
    await setToken(token);
    return token;
  }

  Future<User> getMe() async {
    final response = await _dio.get('/auth/me');
    return User.fromJson(response.data);
  }

  /// 修改密码
  Future<void> changePassword(String oldPassword, String newPassword) async {
    await _dio.post('/auth/change-password', data: {
      'old_password': oldPassword,
      'new_password': newPassword,
    });
  }

  // ========== 联系人 ==========
  
  Future<List<Contact>> getContacts() async {
    final response = await _dio.get('/contacts');
    return (response.data as List)
        .map((json) => Contact.fromJson(json))
        .toList();
  }

  /// 发送添加联系人申请（和 Web 前端一致，等对方同意后才创建）
  Future<void> addContact(String name, String portalUrl) async {
    final sharedKey = 'sk_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${List.generate(8, (_) => (Random().nextDouble() * 36).toInt().toRadixString(36)).join()}';
    await _dio.post('/contact-requests/apply', data: {
      'target_portal': portalUrl,
      'requester_name': name,
      'requester_portal': _portalUrl ?? '',
      'shared_key': sharedKey,
      'message': '',
    });
  }

  // ========== 联系人请求 ==========
  
  /// 生成共享密钥
  String generateSharedKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return 'shared_' + bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  }

  /// 申请添加联系人（匿名，无需登录）
  Future<Map<String, dynamic>> applyContact({
    required String targetPortal,
    required String requesterName,
    required String requesterPortal,
    String? message,
  }) async {
    // 生成 shared_key
    final sharedKey = generateSharedKey();
    
    // 保存到本地（用于后续验证回调）
    final prefs = await SharedPreferences.getInstance();
    final pendingRequests = jsonDecode(prefs.getString('pending_requests') ?? '[]') as List;
    pendingRequests.add({
      'target_portal': targetPortal,
      'requester_portal': requesterPortal,
      'shared_key': sharedKey,
      'created_at': DateTime.now().toIso8601String(),
    });
    await prefs.setString('pending_requests', jsonEncode(pendingRequests));
    
    final response = await _dio.post('/contact-requests/apply', data: {
      'target_portal': targetPortal,
      'requester_name': requesterName,
      'requester_portal': requesterPortal,
      'shared_key': sharedKey,
      'message': message,
    });
    return response.data;
  }

  /// 获取收到的请求
  Future<List<dynamic>> getReceivedRequests() async {
    final response = await _dio.get('/contact-requests/received');
    return response.data;
  }

  /// 批准请求
  Future<Map<String, dynamic>> approveRequest(int requestId) async {
    final response = await _dio.post('/contact-requests/$requestId/approve');
    return response.data;
  }

  /// 拒绝请求
  Future<Map<String, dynamic>> rejectRequest(int requestId) async {
    final response = await _dio.post('/contact-requests/$requestId/reject');
    return response.data;
  }

  // ========== 消息 ==========
  
  Future<List<Message>> getMessages(int contactId, {int limit = 50, String? since}) async {
    final params = <String, dynamic>{
      'contact_id': contactId,
      'limit': limit,
    };
    if (since != null) params['since'] = since;
    final response = await _dio.get('/messages', queryParameters: params);
    return (response.data as List)
        .map((json) => Message.fromJson(json))
        .toList();
  }

  Future<Message> sendMessage(int contactId, String content, {MessageType type = MessageType.text, int? replyToMessageId, String? replyToContent, String? replyToSenderName, String? msgUuid}) async {
    final body = <String, dynamic>{
      'contact_id': contactId,
      'content': content,
      'message_type': type.name,
    };
    if (msgUuid != null) body['msg_uuid'] = msgUuid;
    if (replyToMessageId != null) body['reply_to_message_id'] = replyToMessageId;
    if (replyToContent != null) body['reply_to_content'] = replyToContent;
    if (replyToSenderName != null) body['reply_to_sender_name'] = replyToSenderName;
    final response = await _dio.post('/messages', data: body);
    return Message.fromJson(response.data);
  }

  // 获取未读消息
  Future<List<Message>> getUnreadMessages() async {
    final response = await _dio.get('/messages/unread');
    return (response.data as List)
        .map((json) => Message.fromJson(json))
        .toList();
  }

  /// 获取所有聊天的最新消息（用于消息列表排序）
  Future<List<Map<String, dynamic>>> getLatestMessages() async {
    final response = await _dio.get('/messages/latest');
    return List<Map<String, dynamic>>.from(response.data);
  }

  // 标记消息为已读
  Future<void> markMessageAsRead(int messageId) async {
    await _dio.post('/messages/$messageId/read');
  }

  /// 删除联系人
  Future<void> deleteContact(int contactId) async {
    await _dio.delete('/contacts/$contactId');
  }

  /// 更新联系人（备注名等）
  Future<void> updateContact(int contactId, {String? note, bool? isFavorite, bool? isPinned}) async {
    await _dio.put('/contacts/$contactId', data: {
      if (note != null) 'note': note,
      if (isFavorite != null) 'is_favorite': isFavorite,
      if (isPinned != null) 'is_pinned': isPinned,
    });
  }

  // ========== 群组 ==========

  // 获取群组列表
  Future<List<Map<String, dynamic>>> getGroups() async {
    final response = await _dio.get('/groups');
    return List<Map<String, dynamic>>.from(response.data);
  }

  // 创建群组
  Future<Map<String, dynamic>> createGroup(String name, {String? description, List<int>? memberIds}) async {
    final response = await _dio.post('/groups', data: {
      'name': name,
      'description': description,
      'member_ids': memberIds ?? [],
    });
    return response.data;
  }

  // 邀请成员加入群组
  Future<Map<String, dynamic>> inviteToGroup(int groupId, int contactId) async {
    final response = await _dio.post('/groups/invite', data: {
      'group_id': groupId,
      'contact_id': contactId,
    });
    return response.data;
  }

  // 获取群邀请列表
  Future<List<Map<String, dynamic>>> getGroupInvites() async {
    final response = await _dio.get('/groups/invites');
    return List<Map<String, dynamic>>.from(response.data);
  }

  // 接受群邀请
  Future<Map<String, dynamic>> acceptGroupInvite(int inviteId) async {
    final response = await _dio.post('/groups/invites/$inviteId/accept');
    return response.data;
  }

  // 拒绝群邀请
  Future<Map<String, dynamic>> rejectGroupInvite(int inviteId) async {
    final response = await _dio.post('/groups/invites/$inviteId/reject');
    return response.data;
  }

  // 获取群消息（群主使用数字 ID）
  Future<List<Map<String, dynamic>>> getGroupMessages(int groupId, {int limit = 50, String? since}) async {
    final params = <String, dynamic>{'limit': limit};
    if (since != null) params['since'] = since;
    final response = await _dio.get('/messages/group/$groupId', queryParameters: params);
    return List<Map<String, dynamic>>.from(response.data);
  }

  // 获取群消息（成员使用 UUID）
  Future<List<Map<String, dynamic>>> getGroupMessagesByUuid(String groupUuid, {int limit = 50, String? since}) async {
    final params = <String, dynamic>{'limit': limit};
    if (since != null) params['since'] = since;
    final response = await _dio.get('/messages/group/uuid/$groupUuid', queryParameters: params);
    return List<Map<String, dynamic>>.from(response.data);
  }

  // 发送群消息
  Future<Map<String, dynamic>> sendGroupMessage(int groupId, String content, {String messageType = 'text', String? fileUrl, String? fileName, int? fileSize, String? groupUuid, bool isOwner = false, int? replyToMessageId, String? replyToContent, String? replyToSenderName}) async {
    final Map<String, dynamic> body = {'content': content, 'message_type': messageType};
    if (fileUrl != null) body['file_url'] = fileUrl;
    if (fileName != null) body['file_name'] = fileName;
    if (fileSize != null) body['file_size'] = fileSize;
    if (replyToMessageId != null) body['reply_to_message_id'] = replyToMessageId;
    if (replyToContent != null) body['reply_to_content'] = replyToContent;
    if (replyToSenderName != null) body['reply_to_sender_name'] = replyToSenderName;
    
    // 和 Web 前端一致：群主用 dbId/messages/p2p，成员用 UUID
    if (isOwner) {
      final response = await _dio.post('/groups/$groupId/messages/p2p', data: body);
      return response.data;
    } else {
      final uuid = groupUuid ?? groupId.toString();
      final response = await _dio.post('/groups/by-uuid/$uuid/messages/send', data: body);
      return response.data;
    }
  }

  // ========== 文件上传 ==========

  /// 上传文件
  Future<Map<String, dynamic>> uploadFile(String filePath) async {
    final fileName = filePath.split('/').last;
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
    });
    final response = await _dio.post('/files/upload', data: formData);
    return response.data;
  }

  /// 上传文件（Web 版，使用 bytes）
  Future<Map<String, dynamic>> uploadFileBytes(String fileName, dynamic bytes) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: fileName),
    });
    final response = await _dio.post('/files/upload', data: formData);
    return response.data;
  }

  // ========== 群成员管理 ==========

  /// 获取群成员列表
  Future<List<Map<String, dynamic>>> getGroupMembers(int groupId) async {
    final response = await _dio.get('/groups/$groupId/members');
    final data = response.data;
    if (data is Map && data.containsKey('members')) {
      return List<Map<String, dynamic>>.from(data['members']);
    }
    return List<Map<String, dynamic>>.from(data);
  }

  /// 移除群成员
  Future<void> removeGroupMember(int groupId, String memberPortal) async {
    await _dio.post('/groups/$groupId/members/remove', data: {
      'member_portal': memberPortal,
    });
  }

  /// 解散群组
  Future<void> dissolveGroup(int groupId) async {
    await _dio.post('/groups/$groupId/dissolve');
  }

  // ========== My Agent ==========

  /// 获取 My Agent 历史消息
  Future<List<Map<String, dynamic>>> getAgentMessages({int limit = 50, String? since}) async {
    final userId = await getToken() ?? '1';
    final params = <String, dynamic>{
      'contact_id': 0,
      'limit': limit,
      'token': userId,
    };
    if (since != null) params['since'] = since;
    final response = await _dio.get('/internal/messages', queryParameters: params);
    return List<Map<String, dynamic>>.from(response.data);
  }

  /// 发送消息给 My Agent
  Future<void> sendAgentMessage(String content) async {
    await _dio.post('/messages', data: {
      'contact_id': 0,
      'content': content,
      'message_type': 'text',
    });
  }

  /// 发送文件消息给联系人
  Future<Message> sendFileMessage(int contactId, String filePath) async {
    final fileData = await uploadFile(filePath);
    final response = await _dio.post('/messages', data: {
      'contact_id': contactId,
      'content': '📎 ${fileData['file_name']}',
      'message_type': fileData['file_type'] == 'image' ? 'image' : 'file',
      'file_url': fileData['file_url'],
      'file_name': fileData['file_name'],
      'file_size': fileData['file_size'],
    });
    return Message.fromJson(response.data);
  }

  /// 发送群文件消息
  Future<Map<String, dynamic>> sendGroupFileMessage(int groupId, String filePath, {String? groupUuid, bool isOwner = false}) async {
    final fileData = await uploadFile(filePath);
    final body = {
      'content': '📎 ${fileData['file_name']}',
      'message_type': fileData['file_type'] == 'image' ? 'image' : 'file',
      'file_url': fileData['file_url'],
      'file_name': fileData['file_name'],
      'file_size': fileData['file_size'],
    };
    if (isOwner) {
      final response = await _dio.post('/groups/$groupId/messages/p2p', data: body);
      return response.data;
    } else {
      final uuid = groupUuid ?? groupId.toString();
      final response = await _dio.post('/groups/by-uuid/$uuid/messages/send', data: body);
      return response.data;
    }
  }

  /// 修改群名称
  Future<void> updateGroupName(int groupId, String newName) async {
    await _dio.put('/groups/$groupId', data: {'name': newName});
  }

  /// 退出群聊
  Future<void> leaveGroup(int groupId) async {
    await _dio.post('/groups/$groupId/leave');
  }

  /// 发送文件给 My Agent
  Future<void> sendAgentFileMessage(String filePath) async {
    final fileData = await uploadFile(filePath);
    await _dio.post('/messages', data: {
      'contact_id': 0,
      'content': '📎 ${fileData['file_name']}',
      'message_type': fileData['file_type'] == 'image' ? 'image' : 'file',
      'file_url': fileData['file_url'],
      'file_name': fileData['file_name'],
      'file_size': fileData['file_size'],
    });
  }

  // ========== 消息删除 ==========
  
  /// 删除单条私聊消息
  Future<void> deleteMessage(int messageId) async {
    await _dio.delete('/messages/$messageId');
  }

  /// 清空与联系人的聊天记录
  Future<void> clearContactMessages(int contactId) async {
    await _dio.delete('/messages/contact/$contactId');
  }

  /// 删除单条群聊消息
  Future<void> deleteGroupMessage(int messageId) async {
    await _dio.delete('/messages/group/item/$messageId');
  }

  /// 清空群聊消息
  Future<void> clearGroupMessages(int groupId) async {
    await _dio.delete('/messages/group/clear/$groupId');
  }

  /// 撤回消息（硬删除）
  Future<void> recallMessage(int messageId) async {
    await _dio.post('/messages/$messageId/recall');
  }

  Future<void> updateGroupAnnouncement(int groupId, String announcement) async {
    await _dio.put('/groups/$groupId/announcement', data: {'announcement': announcement});
  }

  // ========== 关注 ==========
  
  Future<List<Map<String, dynamic>>> getFollows() async {
    final response = await _dio.get('/follows');
    return List<Map<String, dynamic>>.from(response.data);
  }

  Future<void> addFollow(String portalUrl) async {
    await _dio.post('/follows', data: {'portal_url': portalUrl});
  }

  Future<void> removeFollow(int followId) async {
    await _dio.delete('/follows/$followId');
  }

  // ========== 搜索 ==========
  
  Future<List<Map<String, dynamic>>> searchMessages(String keyword, {int limit = 20}) async {
    final response = await _dio.get('/messages/search', queryParameters: {'keyword': keyword, 'limit': limit});
    return List<Map<String, dynamic>>.from(response.data);
  }
}
