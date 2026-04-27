import 'package:flutter/foundation.dart';
import '../models/user.dart';
import '../services/api_service.dart';

class AuthProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();
  
  User? _user;
  String? _token;
  String? _portalUrl;
  bool _isLoading = true;
  bool _isInitialized = false;
  String? _error;

  User? get user => _user;
  String? get token => _token;
  String? get portalUrl => _portalUrl;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _token != null && _user != null;
  bool get isInitialized => _isInitialized;
  String? get error => _error;

  AuthProvider() {
    _apiService.initialize();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    _isLoading = true;
    notifyListeners();

    try {
      // 检查是否已登录（从本地存储恢复）
      _token = await _apiService.getToken();
      _portalUrl = await _apiService.getPortalUrl();
      
      if (_portalUrl != null) {
        _isInitialized = true;
        await _apiService.setPortalUrl(_portalUrl!);
      }
      
      if (_token != null) {
        try {
          _user = await _apiService.getMe();
        } catch (_) {
          // token 过期，清除
          await _apiService.clearToken();
          _token = null;
        }
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 初始化账号（首次使用）
  Future<bool> initAccount(String password, {String? displayName}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _user = await _apiService.initAccount(password, displayName: displayName);
      _isInitialized = true;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = '初始化失败: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// 登录 - 使用 Portal URL + 密码
  Future<bool> login(String portalUrl, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _token = await _apiService.login(portalUrl, password);
      _portalUrl = portalUrl;
      _isInitialized = true;
      // 动态设置 API 地址：手机直连，Web 走代理
      if (!kIsWeb) {
        ApiService().updateBaseUrl('$portalUrl/api');
      }
      // 保存 portalUrl
      await _apiService.setPortalUrl(portalUrl);
      _user = await _apiService.getMe();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = '登录失败: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await _apiService.clearToken();
    _user = null;
    _token = null;
    _portalUrl = null;
    notifyListeners();
  }

  /// 修改密码
  Future<bool> changePassword(String oldPassword, String newPassword) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _apiService.changePassword(oldPassword, newPassword);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = '修改密码失败: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
}
