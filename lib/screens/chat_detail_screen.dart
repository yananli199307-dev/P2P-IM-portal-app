import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/chat_provider.dart';
import '../models/message.dart';
import 'package:intl/intl.dart';

class ChatDetailScreen extends StatefulWidget {
  const ChatDetailScreen({super.key});

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _shouldScrollToBottom = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    // 用户手动滚动后停止自动滚底
    if (_scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.position.pixels;
      _shouldScrollToBottom = (maxScroll - currentScroll) < 50;
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && _shouldScrollToBottom) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    context.read<ChatProvider>().sendMessage(content);
    _messageController.clear();
    _shouldScrollToBottom = true;
    _scrollToBottom();
  }

  Future<void> _sendFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: false);
      if (result == null || result.files.isEmpty) return;

      final filePath = result.files.first.path;
      if (filePath == null) return;

      await context.read<ChatProvider>().sendFileMessage(filePath);
      _shouldScrollToBottom = true;
      _scrollToBottom();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发送文件失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final contact = chatProvider.selectedContact;
    final messages = chatProvider.messages;

    // 滚动到底部（初次加载）
    if (messages.isNotEmpty) {
      _scrollToBottom();
    }

    if (contact == null) {
      return const Scaffold(body: Center(child: Text('请选择联系人')));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(contact.displayName),
      ),
      body: Column(
        children: [
          Expanded(
            child: chatProvider.isLoading && messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : messages.isEmpty
                    ? const Center(child: Text('暂无消息\n发送第一条消息吧', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        itemCount: _getItemCount(messages),
                        itemBuilder: (context, index) {
                          return _buildItem(messages, index);
                        },
                      ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border(top: BorderSide(color: Colors.grey[300]!)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(icon: const Icon(Icons.attach_file), onPressed: _sendFile),
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: const InputDecoration(hintText: '输入消息...', border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 16)),
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            IconButton(icon: const Icon(Icons.send, color: Color(0xFF6C63FF)), onPressed: _sendMessage),
          ],
        ),
      ),
    );
  }

  // ===== 消息列表（含日期分割线） =====

  int _getItemCount(List<Message> messages) {
    int count = 0;
    String? lastDate;
    for (final msg in messages) {
      final dateKey = DateFormat('yyyy-MM-dd').format(msg.createdAt);
      if (dateKey != lastDate) {
        count++; // 日期分割线
        lastDate = dateKey;
      }
      count++; // 消息
    }
    return count;
  }

  Widget _buildItem(List<Message> messages, int displayIndex) {
    int msgIndex = 0;
    String? lastDate;

    for (int i = 0; i < messages.length; i++) {
      final dateKey = DateFormat('yyyy-MM-dd').format(messages[i].createdAt);
      if (dateKey != lastDate) {
        if (displayIndex == msgIndex) return _buildDateSeparator(messages[i].createdAt);
        msgIndex++;
        lastDate = dateKey;
      }
      if (displayIndex == msgIndex) return _buildMessageBubble(messages[i]);
      msgIndex++;
    }
    return const SizedBox.shrink();
  }

  Widget _buildDateSeparator(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDate = DateTime(date.year, date.month, date.day);
    final diff = today.difference(msgDate).inDays;

    String text;
    if (diff == 0) {
      text = '今天';
    } else if (diff == 1) {
      text = '昨天';
    } else if (diff < 7) {
      text = '$diff 天前';
    } else {
      text = DateFormat('yyyy年M月d日').format(date);
    }

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ),
    );
  }

  Widget _buildMessageBubble(Message message) {
    final isMe = message.isFromMe;
    final time = DateFormat('HH:mm').format(message.createdAt);

    Widget content;
    if (message.messageType == 'image' && message.fileUrl != null) {
      content = GestureDetector(
        onTap: () => _showImagePreview(context, message.fileUrl!),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(message.fileUrl!, width: 200, height: 200, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)),
        ),
      );
    } else if (message.fileUrl != null) {
      content = Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF5A52D5) : Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.attach_file, color: isMe ? Colors.white : Colors.black87),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message.fileName ?? '文件', style: TextStyle(color: isMe ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
                  if (message.fileSize != null)
                    Text(_formatFileSize(message.fileSize), style: TextStyle(fontSize: 12, color: isMe ? Colors.white70 : Colors.grey[600])),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      content = Text(message.content, style: TextStyle(color: isMe ? Colors.white : Colors.black87));
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
        padding: message.fileUrl != null ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: message.fileUrl != null ? null : (isMe ? const Color(0xFF6C63FF) : Colors.grey[300]),
          borderRadius: BorderRadius.circular(16),
        ),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            content,
            const SizedBox(height: 2),
            Text(time, style: TextStyle(fontSize: 10, color: isMe ? Colors.white70 : Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  void _showImagePreview(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: InteractiveViewer(
          panEnabled: true,
          boundaryMargin: const EdgeInsets.all(20),
          minScale: 0.5,
          maxScale: 4,
          child: Image.network(imageUrl, fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image, size: 64))),
        ),
      ),
    );
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
