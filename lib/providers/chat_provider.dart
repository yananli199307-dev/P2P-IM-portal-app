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

  List<Contact> get contacts => _contacts;
  List<Message> get messages => _messages;
  Contact? get selectedContact => _selectedContact;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isConnected => _isConnected;

  void initWebSocket(String userId) {
    _wsService.connect(userId);
    _wsService.connectionStream.listen((connected) {
      _isConnected = connected;
      notifyListeners();
    });
    _wsService.messageStream.listen((message) {
      _handleWebSocketMessage(message);
    });
  }

  void _handleWebSocketMessage(Map<String, dynamic> message) {
    if (message['type'] == 'new_message') {
      final data = message['data'];
      if (data != null) {
        final newMessage = Message.fromJson(data);
        if (newMessage.contactId == _selectedContact?.id) {
          _messages.add(newMessage);
          notifyListeners();
        }
      }
    }
  }

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

  void selectContact(Contact contact) {
    _selectedContact = contact;
    _messages = [];
    notifyListeners();
    loadMessages(contact.id);
  }

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

  Future<void> sendMessage(String content) async {
    if (_selectedContact == null) return;

    try {
      final message = await _apiService.sendMessage(
        _selectedContact!.id,
        content,
      );
      _messages.add(message);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  void dispose() {
    _wsService.dispose();
    super.dispose();
  }
}
