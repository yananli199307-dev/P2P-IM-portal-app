import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../models/contact.dart';
import '../models/message.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  // 配置你的 Portal 地址
  static const String baseUrl = 'https://agentp2p.cn/api';
  
  late Dio _dio;
  String? _token;

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
          // Token 过期，清除登录状态
          clearToken();
        }
        handler.next(error);
      },
    ));
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
  }

  // ========== 认证 ==========
  
  Future<User> register(String username, String password, {String? email}) async {
    final response = await _dio.post('/auth/register', data: {
      'username': username,
      'password': password,
      'email': email,
    });
    return User.fromJson(response.data);
  }

  Future<String> login(String username, String password) async {
    final response = await _dio.post('/auth/login', data: {
      'username': username,
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
