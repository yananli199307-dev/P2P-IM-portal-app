import 'dart:math';
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

  // Portal 地址，默认为当前域名（Web模式）
  // 在 Flutter App 中运行时应该从配置读取
  static String baseUrl = '/api';
  
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
  
  Future<List<Message>> getMessages(int contactId, {int limit = 50}) async {
    final response = await _dio.get('/messages', queryParameters: {
      'contact_id': contactId,
      'limit': limit,
    });
    return (response.data as List)
        .map((json) => Message.fromJson(json))
        .toList();
  }

  Future<Message> sendMessage(int contactId, String content, {MessageType type = MessageType.text}) async {
    final response = await _dio.post('/messages', data: {
      'contact_id': contactId,
      'content': content,
      'message_type': type.name,
    });
    return Message.fromJson(response.data);
  }

  // 获取未读消息
  Future<List<Message>> getUnreadMessages() async {
    final response = await _dio.get('/messages/unread');
    return (response.data as List)
        .map((json) => Message.fromJson(json))
        .toList();
  }

  // 标记消息为已读
  Future<void> markMessageAsRead(int messageId) async {
    await _dio.post('/messages/$messageId/read');
  }

  /// 删除联系人
  Future<void> deleteContact(int contactId) async {
    await _dio.delete('/contacts/$contactId');
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
  Future<List<Map<String, dynamic>>> getGroupMessages(int groupId, {int limit = 50}) async {
    final response = await _dio.get('/messages/group/$groupId', queryParameters: {
      'limit': limit,
    });
    return List<Map<String, dynamic>>.from(response.data);
  }

  // 获取群消息（成员使用 UUID）
  Future<List<Map<String, dynamic>>> getGroupMessagesByUuid(String groupUuid, {int limit = 50}) async {
    final response = await _dio.get('/messages/group/uuid/$groupUuid', queryParameters: {
      'limit': limit,
    });
    return List<Map<String, dynamic>>.from(response.data);
  }

  // 发送群消息
  Future<Map<String, dynamic>> sendGroupMessage(int groupId, String content, {String messageType = 'text', String? fileUrl, String? fileName, int? fileSize, String? groupUuid, bool isOwner = false}) async {
    final Map<String, dynamic> body = {'content': content, 'message_type': messageType};
    if (fileUrl != null) body['file_url'] = fileUrl;
    if (fileName != null) body['file_name'] = fileName;
    if (fileSize != null) body['file_size'] = fileSize;
    
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
  Future<List<Map<String, dynamic>>> getAgentMessages({int limit = 50}) async {
    final userId = await getToken() ?? '1';
    final response = await _dio.get('/internal/messages', queryParameters: {
      'contact_id': 0,
      'limit': limit,
      'token': userId,
    });
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
}
