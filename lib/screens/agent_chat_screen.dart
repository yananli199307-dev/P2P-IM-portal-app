import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';
import '../widgets/plus_menu.dart';
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
  bool _isLoading = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _initWebSocket();
  }

  Future<void> _loadHistory() async {
    try {
      final messages = await ApiService().getAgentMessages();
      setState(() {
        _messages.addAll(messages.reversed.map((m) => AgentMessage(
          id: m['id'].toString(),
          content: m['content'],
          isFromUser: m['is_from_owner'] ?? true,
          createdAt: DateTime.parse(m['created_at']),
          fileUrl: m['file_url'],
          fileName: m['file_name'],
        )));
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _initWebSocket() {
    _wsService.onMessage = (message) {
      if (message['type'] == 'agent_reply') {
        setState(() {
          _messages.add(AgentMessage(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            content: message['content'],
            isFromUser: false,
            createdAt: DateTime.now(),
          ));
        });
        _scrollToBottom();
      }
    };
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
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
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;

      final filePath = result.files.first.path;
      if (filePath == null) return;

      setState(() {
        _isSending = true;
      });

      await ApiService().sendAgentFileMessage(filePath);

      setState(() {
        _isSending = false;
      });
    } catch (e) {
      setState(() {
        _isSending = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送文件失败: $e')),
      );
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
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  onPressed: _isSending ? null : _sendFile,
                ),
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
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _isSending ? null : _sendMessage,
                ),
              ],
            ),
          ),
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
