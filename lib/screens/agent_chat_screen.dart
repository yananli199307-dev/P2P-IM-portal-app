import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';
import '../services/local_db.dart';
import '../models/message.dart';
import '../widgets/plus_menu.dart';
import '../widgets/emoji_picker.dart';
import '../widgets/link_text.dart';
import '../services/websocket_service.dart';

class AgentMessage {
  final String id;
  final String content;
  final bool isFromUser;
  final DateTime createdAt;
  final String? fileUrl;
  final String? fileName;

  AgentMessage({
    required this.id,
    required this.content,
    required this.isFromUser,
    required this.createdAt,
    this.fileUrl,
    this.fileName,
  });
}

class AgentChatScreen extends StatefulWidget {
  const AgentChatScreen({Key? key}) : super(key: key);

  @override
  State<AgentChatScreen> createState() => _AgentChatScreenState();
}

class _AgentChatScreenState extends State<AgentChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<AgentMessage> _messages = [];
  final WebSocketService _wsService = WebSocketService();
  bool _isLoading = false;  // 默认 false，首次无缓存时才显示
  bool _isSending = false;
  int _panelOpen = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadHistory();
    _initWebSocket();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final currentScroll = _scrollController.position.pixels;
    if (currentScroll < 50 && !_loadingMore && _messages.isNotEmpty) {
      _loadMore();
    }
  }

  bool _loadingMore = false;
  Future<void> _loadMore() async {
    _loadingMore = true;
    final oldest = _messages.first.createdAt;
    final cached = await LocalDb().getContactMessages(0);
    final older = cached.where((m) => m.createdAt.isBefore(oldest)).toList();
    if (older.isNotEmpty && mounted) {
      setState(() {
        _messages.insertAll(0, older.map((m) => AgentMessage(
          id: m.id.toString(),
          content: m.content,
          isFromUser: m.isFromMe,
          createdAt: m.createdAt,
          fileUrl: m.fileUrl,
          fileName: m.fileName,
        )));
      });
    }
    _loadingMore = false;
  }

  Future<void> _loadHistory() async {
    // 1. 先读本地缓存
    final cached = await LocalDb().getContactMessages(0);
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _messages.clear();
        _messages.addAll(cached.map((m) => AgentMessage(
          id: m.id.toString(),
          content: m.content,
          isFromUser: m.isFromMe,
          createdAt: m.createdAt,
          fileUrl: m.fileUrl,
          fileName: m.fileName,
        )));
        if (cached.length < 50) _isLoading = true;  // 本地消息少时显示加载中
      });
      _scrollToBottom();
    } else {
      setState(() => _isLoading = true);  // 无本地缓存，显示加载圈
    }
    
    // 2. 后台同步服务器
    try {
      final messages = await ApiService().getAgentMessages();
      if (!mounted) return;
      
      final existingIds = _messages.map((m) => m.id).toSet();
      final newMsgs = messages.where((m) => !existingIds.contains(m['id'].toString())).toList();
      
      if (newMsgs.isNotEmpty) {
        setState(() {
          _messages.addAll(newMsgs.reversed.map((m) => AgentMessage(
            id: m['id'].toString(),
            content: m['content'],
            isFromUser: m['is_from_owner'] ?? true,
            createdAt: DateTime.parse(m['created_at']),
            fileUrl: m['file_url'],
            fileName: m['file_name'],
          )));
        });
      } else if (cached.isEmpty) {
        setState(() {
          _messages.addAll(messages.reversed.map((m) => AgentMessage(
            id: m['id'].toString(),
            content: m['content'],
            isFromUser: m['is_from_owner'] ?? true,
            createdAt: DateTime.parse(m['created_at']),
            fileUrl: m['file_url'],
            fileName: m['file_name'],
          )));
        });
      }
      
      setState(() => _isLoading = false);
      _scrollToBottom();
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _initWebSocket() {
    _wsService.onMessage = (message) {
      if (message['type'] == 'agent_reply') {
        final msg = AgentMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          content: message['content'],
          isFromUser: false,
          createdAt: DateTime.now(),
        );
        setState(() => _messages.add(msg));
        // 写入本地缓存
        LocalDb().upsertMessage(Message(
          id: int.tryParse(msg.id) ?? DateTime.now().millisecondsSinceEpoch,
          contactId: 0,
          content: msg.content,
          type: MessageType.text,
          isFromMe: false,
          createdAt: msg.createdAt,
        ));
        _scrollToBottom();
      }
    };
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    _messageController.clear();

    setState(() {
      _messages.add(AgentMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        content: content,
        isFromUser: true,
        createdAt: DateTime.now(),
      ));
      _isSending = true;
    });
    _scrollToBottom();

    try {
      await ApiService().sendAgentMessage(content);
      setState(() {
        _isSending = false;
      });
    } catch (e) {
      setState(() {
        _isSending = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送失败: $e')),
      );
    }
  }

  Future<void> _sendFile() async {
    try {
      final result = await FilePicker.pickFiles(type: FileType.any, allowMultiple: false, withData: true);
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      setState(() => _isSending = true);

      if (file.bytes != null) {
        await ApiService().uploadFileBytes(file.name, file.bytes);
      } else if (file.path != null) {
        await ApiService().uploadFile(file.path!);
      }

      // 发送文件消息
      final msg = file.path != null ? '📎 ${file.name}' : '📎 ${file.name}';
      _messageController.clear();
      _messageController.text = msg;
      _sendMessage();

      setState(() => _isSending = false);
    } catch (e) {
      setState(() => _isSending = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发送文件失败: $e')));
    }
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Text('🤖 '),
            Text('My Agent'),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final isMe = message.isFromUser;
                      
                      return GestureDetector(
                                                onLongPress: () async {
                          final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('删除消息'), content: const Text('确定删除这条消息吗？'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')), TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除', style: TextStyle(color: Colors.red)))],));
                          if (confirm == true) {
                            try {
                              await ApiService().deleteMessage(int.tryParse(message.id) ?? 0);
                              if (mounted) setState(() => _messages.removeWhere((m) => m.id == message.id));
                            } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败: $e'))); }
                          }
                        },
                        child: Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isMe ? Colors.blue[100] : Colors.grey[200],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              LinkText(message.content),
                              const SizedBox(height: 4),
                              Text(
                                _formatTime(message.createdAt),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                    },
                  ),
          ),
          if (_isSending)
            const LinearProgressIndicator(),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              border: Border(top: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Row(
              children: [
                IconButton(icon: const Icon(Icons.add_circle_outline, color: Color(0xFF6C63FF)), onPressed: _isSending ? null : () => setState(() => _panelOpen = _panelOpen == 2 ? 0 : 2)),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: '输入消息...',
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(icon: const Icon(Icons.emoji_emotions, color: Color(0xFF6C63FF)), onPressed: () => setState(() => _panelOpen = _panelOpen == 1 ? 0 : 1)),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _isSending ? null : _sendMessage,
                ),
              ],
            ),
          ),
          if (_panelOpen == 1) EmojiPicker(onEmoji: (e) { _messageController.text += e; _messageController.selection = TextSelection.fromPosition(TextPosition(offset: _messageController.text.length)); }),
          if (_panelOpen == 2) PlusMenu(onFile: _sendFile, onImage: _sendFile),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
