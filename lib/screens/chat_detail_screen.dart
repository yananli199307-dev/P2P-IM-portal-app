import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/chat_provider.dart';
import '../services/api_service.dart';
import '../models/message.dart';
import 'package:intl/intl.dart';
import '../helpers/file_icon_helper.dart';
import '../widgets/link_text.dart';
import '../widgets/plus_menu.dart';
import '../widgets/emoji_picker.dart';
import 'chat_info_screen.dart';
import 'forward_screen.dart';
import 'call_screen.dart';

class ChatDetailScreen extends StatefulWidget {
  const ChatDetailScreen({super.key});

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _shouldScrollToBottom = true;
  Message? _replyTarget;
  bool _multiSelect = false;
  final Set<int> _selectedIds = {};
  int _panelOpen = 0; // 0=none, 1=emoji, 2=plus

  void _enterMultiSelect(int messageId) {
    setState(() { _multiSelect = true; _selectedIds.add(messageId); });
  }

  void _toggleSelect(int messageId) {
    setState(() {
      if (_selectedIds.contains(messageId)) { _selectedIds.remove(messageId); if (_selectedIds.isEmpty) _multiSelect = false; }
      else { _selectedIds.add(messageId); }
    });
  }

  void _exitMultiSelect() => setState(() { _multiSelect = false; _selectedIds.clear(); });

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

    final reply = _replyTarget;
    if (reply != null) {
      context.read<ChatProvider>().sendMessage(
        content,
        replyToMessageId: reply.id,
        replyToContent: reply.content.length > 50 ? '${reply.content.substring(0, 50)}...' : reply.content,
        replyToSenderName: reply.isFromMe ? '我' : (reply.replyToSenderName ?? '对方'),
      );
      setState(() => _replyTarget = null);
    } else {
      context.read<ChatProvider>().sendMessage(content);
    }
    _messageController.clear();
    _shouldScrollToBottom = true;
    _scrollToBottom();
  }

  Future<void> _sendFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: false, withData: true);
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      
      if (file.path != null) {
        // 移动端：有本地路径
        await context.read<ChatProvider>().sendFileMessage(file.path!);
      } else if (file.bytes != null) {
        // Web 端：用 bytes 上传
        await context.read<ChatProvider>().sendFileBytes(file.name, file.bytes!);
      }
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
    
    // 接收入通话
    final incomingCall = chatProvider.incomingCall;
    if (incomingCall != null && contact != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final call = chatProvider.incomingCall;
          if (call != null) {
            final callCopy = Map<String, dynamic>.from(call);
            setState(() {});
            Navigator.push(context, MaterialPageRoute(builder: (_) => CallScreen(
              peerName: contact.displayName,
              isIncoming: true,
              isVideo: callCopy['type'] == 'video',
              offerSdp: callCopy['sdp'],
            )));
          }
        }
      });
    }

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
        actions: [
          IconButton(icon: const Icon(Icons.more_vert), onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => ChatInfoScreen(contact: contact)));
          }),
        ],
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
          // 回复引用栏
          if (_replyTarget != null) _buildReplyBar(),
          // 多选操作栏
          if (_multiSelect) _buildMultiSelectBar(),
          _buildInputBar(),
          // 表情/加号面板（输入框下面）
          if (_panelOpen == 1) EmojiPicker(onEmoji: (e) { _messageController.text += e; _messageController.selection = TextSelection.fromPosition(TextPosition(offset: _messageController.text.length)); }),
          if (_panelOpen == 2) PlusMenu(onFile: _sendFile, onImage: _sendFile, onVoiceCall: (){}, onVideoCall: (){}, onLocation: (){}),
        ],
      ),
    );
  }


  Widget _buildReplyBar() {
    if (_replyTarget == null) return const SizedBox.shrink();
    final target = _replyTarget!;
    return Container(
      color: Colors.grey[100],
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(children: [
        Container(width: 3, height: 32, color: const Color(0xFF6C63FF)),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(target.replyToSenderName ?? (target.isFromMe ? '我' : '对方'), style: const TextStyle(fontSize: 12, color: Color(0xFF6C63FF), fontWeight: FontWeight.w600)),
          Text(target.content, style: const TextStyle(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
        IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _replyTarget = null), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
      ]),
    );
  }

  Widget _buildMultiSelectBar() {
    final chatProvider = context.read<ChatProvider>();
    return Container(color: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        TextButton(onPressed: _exitMultiSelect, child: const Text('取消')),
        const Spacer(),
        Text('已选 ${_selectedIds.length} 条', style: TextStyle(color: Colors.grey[600])),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: _selectedIds.isEmpty ? null : () {
            final msgs = chatProvider.messages.where((m) => _selectedIds.contains(m.id)).toList();
            final combined = msgs.map((m) => "${m.isFromMe ? '我' : '对方'}: ${m.content}").join('\n---\n');
            _exitMultiSelect();
            Navigator.push(context, MaterialPageRoute(builder: (_) => ForwardScreen(content: combined)));
          }, icon: const Icon(Icons.forward, size: 18), label: const Text('转发'),
        ),
      ]),
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
            IconButton(icon: const Icon(Icons.add_circle_outline, color: Color(0xFF6C63FF)), onPressed: () => setState(() => _panelOpen = _panelOpen == 2 ? 0 : 2)),
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: const InputDecoration(hintText: '输入消息...', border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 16)),
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),

            IconButton(icon: const Icon(Icons.emoji_emotions, color: Color(0xFF6C63FF)), onPressed: () => setState(() => _panelOpen = _panelOpen == 1 ? 0 : 1)),
            IconButton(icon: const Icon(Icons.send, color: Color(0xFF6C63FF)), onPressed: _sendMessage),
          ],
        ),
      ),
    );
  }

  void _callPlaceholder(String type) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$type 功能开发中...')));
  }

  void _locationPlaceholder() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('位置分享功能开发中...')));
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
            Icon(FileIconHelper.getIcon(message.fileName), color: FileIconHelper.getColor(message.fileName)),
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
      content = LinkText(message.content, style: TextStyle(color: isMe ? Colors.white : Colors.black87));
    }

    // 回复预览
    Widget? replyPreview;
    if (message.replyToMessageId != null) {
      replyPreview = Container(
        padding: const EdgeInsets.only(bottom: 6, left: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 2, height: 14, color: const Color(0xFF6C63FF)),
          const SizedBox(width: 4),
          Text(message.replyToSenderName ?? '"对方"', style: TextStyle(fontSize: 11, color: isMe ? Colors.white70 : Colors.grey[600], fontWeight: FontWeight.w500)),
          const SizedBox(width: 4),
          Flexible(child: Text(message.replyToContent ?? message.content, style: TextStyle(fontSize: 11, color: isMe ? Colors.white54 : Colors.grey[500]), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
      );
    }

    // 长按/右键弹出菜单（微信风格）
    void showMenu() {
        showModalBottomSheet(context: context, builder: (_) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(height: 4, color: Colors.grey[300]),
            ListTile(leading: const Icon(Icons.reply, color: Color(0xFF6C63FF)), title: const Text('引用回复'), onTap: () { setState(() => _replyTarget = message); Navigator.pop(context); }),
            ListTile(leading: const Icon(Icons.content_copy, color: Colors.blueGrey), title: const Text('复制'), onTap: () { Navigator.pop(context); }),
            ListTile(leading: const Icon(Icons.forward, color: Colors.blueGrey), title: const Text('转发'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => ForwardScreen(content: message.content))); }),
            const Divider(),
            ListTile(leading: const Icon(Icons.checklist, color: Colors.blueGrey), title: const Text('多选'), onTap: () { Navigator.pop(context); _enterMultiSelect(message.id); }),
            const Divider(),
            if (isMe)
              ListTile(leading: const Icon(Icons.undo, color: Colors.orange), title: const Text('撤回'), onTap: () async {
                Navigator.pop(context);
                try {
                  await ApiService().recallMessage(message.id);
                  if (mounted) context.read<ChatProvider>().removeMessage(message.id);
                } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('撤回失败: $e'))); }
              }),
            if (isMe)
              ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red), title: const Text('删除', style: TextStyle(color: Colors.red)), onTap: () async {
                Navigator.pop(context);
                final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('删除消息'), content: const Text('确定删除这条消息吗？'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')), TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除', style: TextStyle(color: Colors.red)))],));
                if (confirm == true) {
                  try {
                    await ApiService().deleteMessage(message.id);
                    if (mounted) context.read<ChatProvider>().removeMessage(message.id);
                  } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败: $e'))); }
                }
              }),
          ]),
        ));
    }
    
    return GestureDetector(
      onTap: _multiSelect ? () => _toggleSelect(message.id) : null,
      onLongPress: _multiSelect ? () => _toggleSelect(message.id) : showMenu,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (_multiSelect)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(_selectedIds.contains(message.id) ? Icons.check_circle : Icons.radio_button_unchecked, color: const Color(0xFF6C63FF)),
            ),
          Expanded(child: _buildAlignedBubble(message, isMe, time, content, replyPreview)),
        ],
      ),
    );
  }

  Widget _buildAlignedBubble(Message message, bool isMe, String time, Widget content, Widget? replyPreview) {
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
            if (replyPreview != null) replyPreview,
            content,
            const SizedBox(height: 2),
            Text(time, style: TextStyle(fontSize: 10, color: isMe ? Colors.white70 : Colors.grey[600])),
          ],
        ),
      ),
    );
  }
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
