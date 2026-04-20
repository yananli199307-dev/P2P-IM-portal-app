import 'dart:math';
import 'dart:convert';
import 'package:dio/dio.dart';
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
    // 更新 baseUrl
    baseUrl = '$url/api';
    _dio.options.baseUrl = baseUrl;
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

  Future<Contact> addContact(String name, String portalUrl) async {
    final response = await _dio.post('/contacts', data: {
      'display_name': name,
      'portal_url': portalUrl,
    });
    return Contact.fromJson(response.data);
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
}
