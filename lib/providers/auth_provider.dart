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
      // 检查初始化状态
      final initStatus = await _apiService.checkInitStatus();
      _isInitialized = initStatus['initialized'] ?? false;
      
      if (!_isInitialized) {
        // 首次使用，需要初始化
        _isLoading = false;
        notifyListeners();
        return;
      }
      
      // 检查是否已登录
      _token = await _apiService.getToken();
      _portalUrl = await _apiService.getPortalUrl();
      
      if (_token != null) {
        _user = await _apiService.getMe();
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
