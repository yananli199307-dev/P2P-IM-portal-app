import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import "package:provider/provider.dart";
import "../providers/chat_provider.dart";
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../services/local_db.dart';
import '../models/group.dart';
import '../helpers/file_icon_helper.dart';
import '../widgets/link_text.dart';
import '../widgets/plus_menu.dart';
import '../widgets/emoji_picker.dart';
import '../widgets/link_text.dart';
import 'invite_member_screen.dart';
import 'group_members_screen.dart';
import 'group_profile_screen.dart';
import 'forward_screen.dart';

class GroupMessage {
  final int id;
  final String content;
  final String senderName;
  final bool isFromOwner;
  final DateTime createdAt;
  final String? fileUrl;
  final String? fileName;
  final int? fileSize;
  final String messageType;
  final int? replyToMessageId;
  final String? replyToContent;
  final String? replyToSenderName;

  GroupMessage({
    required this.id,
    required this.content,
    required this.senderName,
    required this.isFromOwner,
    required this.createdAt,
    this.fileUrl,
    this.fileName,
    this.fileSize,
    this.messageType = 'text',
    this.replyToMessageId,
    this.replyToContent,
    this.replyToSenderName,
  });

  factory GroupMessage.fromJson(Map<String, dynamic> json) {
    return GroupMessage(
      id: json['id'],
      content: json['content'] ?? '',
      senderName: json['sender_name'] ?? 'Unknown',
      isFromOwner: json['is_from_owner'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
      fileUrl: json['file_url'],
      fileName: json['file_name'],
      fileSize: json['file_size'],
      messageType: json['message_type'] ?? 'text',
      replyToMessageId: json['reply_to_message_id'],
      replyToContent: json['reply_to_content'],
      replyToSenderName: json['reply_to_sender_name'],
    );
  }
}

class GroupChatScreen extends StatefulWidget {
  final Group group;
  const GroupChatScreen({Key? key, required this.group}) : super(key: key);

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<GroupMessage> _messages = [];
  bool _isLoading = true;
  bool _isSendingFile = false;
  GroupMessage? _replyTarget;
  int _panelOpen = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadMessages();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    
    // 滑到顶部加载更早消息
    if (currentScroll < 50 && !_loadingMore && _messages.isNotEmpty) {
      _loadMore();
    }
  }

  bool _loadingMore = false;
  Future<void> _loadMore() async {
    _loadingMore = true;
    final oldest = _messages.first.createdAt;
    final cached = await LocalDb().getCachedGroupMessages(widget.group.id);
    final older = cached.where((m) => DateTime.parse(m['created_at'] ?? '').isBefore(oldest)).toList();
    if (older.isNotEmpty && mounted) {
      setState(() {
        _messages.insertAll(0, older.map((m) => GroupMessage.fromJson(m)));
      });
    }
    _loadingMore = false;
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }


  Future<void> _loadMessages() async {
    // 1. 先查内存缓存
    final cached0 = context.read<ChatProvider>().groupCache[widget.group.id];
    if (cached0 != null && cached0.isNotEmpty && mounted) {
      setState(() {
        _messages = cached0.map((m) => GroupMessage.fromJson(m)).toList();
        _isLoading = false;
      });
      return;
    }
    // 2. 内存无 → 读 LocalDb
    final cached = await LocalDb().getCachedGroupMessages(widget.group.id);
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _messages = cached.map((m) => GroupMessage.fromJson(m)).toList();
        _isLoading = false;
      });
    } else if (mounted) {
      setState(() => _isLoading = true);
      try {
        List<Map<String, dynamic>> messagesData;
        if (widget.group.isOwner) {
          messagesData = await ApiService().getGroupMessages(widget.group.id);
        } else {
          messagesData = await ApiService().getGroupMessagesByUuid(widget.group.groupUuid!);
          for (final m in messagesData) { m['group_id'] = widget.group.id; }
        }
        if (!mounted) return;
        setState(() {
          _messages = messagesData.reversed.map((m) => GroupMessage.fromJson(m)).toList();
          _isLoading = false;
        });
        LocalDb().upsertGroupMessages(messagesData);
        
      } catch (e) {
        if (!mounted) return;
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;
    final reply = _replyTarget;
    _messageController.clear();
    
    // 先本地显示
    final tempMsg = GroupMessage(
      id: DateTime.now().millisecondsSinceEpoch,
      groupId: widget.group.id,
      content: content,
      senderName: '我',
      isFromOwner: true,
      createdAt: DateTime.now(),
    );
    setState(() {
      _messages.add(tempMsg);
      _replyTarget = null;
    });
    
    try {
      await ApiService().sendGroupMessage(
        widget.group.id, content,
        groupUuid: widget.group.groupUuid,
        isOwner: widget.group.isOwner,
        replyToMessageId: reply?.id,
        replyToContent: reply != null ? (reply.content.length > 50 ? '${reply.content.substring(0, 50)}...' : reply.content) : null,
        replyToSenderName: reply?.isFromOwner == true ? '群主' : (reply?.senderName ?? '成员'),
      );
      context.read<ChatProvider>().updateGroupLastMessage(widget.group.id, content);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发送失败: $e')));
    }
  }

  Future<void> _sendFile() async {
    try {
      final result = await FilePicker.pickFiles(type: FileType.any, allowMultiple: false, withData: true);
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      setState(() => _isSendingFile = true);
      if (file.path != null) {
        await ApiService().sendGroupFileMessage(widget.group.id, file.path!, groupUuid: widget.group.groupUuid, isOwner: widget.group.isOwner);
      } else if (file.bytes != null) {
        final fileData = await ApiService().uploadFileBytes(file.name, file.bytes!);
        await ApiService().sendGroupMessage(widget.group.id, '📎 ' + file.name,
          groupUuid: widget.group.groupUuid, isOwner: widget.group.isOwner,
          messageType: fileData["file_type"] == 'image' ? 'image' : 'file',
          fileUrl: fileData["file_url"], fileName: file.name, fileSize: fileData["file_size"]);
      }
      setState(() => _isSendingFile = false);
      _loadMessages();
    } catch (e) {
      setState(() => _isSendingFile = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发送文件失败: $e')));
    }
  }

  // ===== 消息列表（含日期分割线） =====

  int _getItemCountReversed(List<GroupMessage> msgs) {
    int count = 0;
    String? lastDate;
    for (final msg in msgs) {
      final dateKey = DateFormat('yyyy-MM-dd').format(msg.createdAt);
      if (dateKey != lastDate) { count++; lastDate = dateKey; }
      count++;
    }
    return count;
  }

  Widget _buildItemReversed(List<GroupMessage> msgs, int displayIndex) {
    int msgIndex = 0;
    String? lastDate;
    for (int i = 0; i < msgs.length; i++) {
      final dateKey = DateFormat('yyyy-MM-dd').format(msgs[i].createdAt);
      if (dateKey != lastDate) {
        if (displayIndex == msgIndex) return _buildDateSeparator(msgs[i].createdAt);
        msgIndex++; lastDate = dateKey;
      }
      if (displayIndex == msgIndex) return _buildMessageBubble(msgs[i]);
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
    if (diff == 0) text = '今天';
    else if (diff == 1) text = '昨天';
    else if (diff < 7) text = '$diff 天前';
    else text = DateFormat('yyyy年M月d日').format(date);

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ),
    );
  }

  Widget _buildMessageBubble(GroupMessage message) {
    final isMe = message.isFromOwner;
    final time = DateFormat('HH:mm').format(message.createdAt);

    Widget content;
    if (message.messageType == 'image' && message.fileUrl != null) {
      content = GestureDetector(
        onTap: () => _showImagePreview(message.fileUrl!),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(message.fileUrl!, width: 200, height: 200, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)),
        ),
      );
    } else if (message.fileUrl != null) {
      content = Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: isMe ? Colors.blue[100] : Colors.grey[200], borderRadius: BorderRadius.circular(8)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(FileIconHelper.getIcon(message.fileName), color: FileIconHelper.getColor(message.fileName)),
            const SizedBox(width: 8),
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(message.fileName ?? '文件', style: const TextStyle(fontWeight: FontWeight.bold)),
                if (message.fileSize != null) Text(_formatFileSize(message.fileSize), style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ]),
            ),
          ],
        ),
      );
    } else {
      content = Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: isMe ? Colors.blue[100] : Colors.grey[200], borderRadius: BorderRadius.circular(8)),
        child: LinkText(message.content),
      );
    }

    // 回复预览
    Widget? replyPreview;
    if (message.replyToMessageId != null) {
      replyPreview = Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 2, height: 12, color: const Color(0xFF6C63FF)),
          const SizedBox(width: 4),
          Text(message.replyToSenderName ?? '成员', style: TextStyle(fontSize: 11, color: isMe ? Colors.blue[800] : Colors.grey[600], fontWeight: FontWeight.w500)),
          const SizedBox(width: 4),
          Flexible(child: Text(message.replyToContent ?? '', style: TextStyle(fontSize: 11, color: Colors.grey[500]), maxLines: 1, overflow: TextOverflow.ellipsis)),
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
            ListTile(leading: const Icon(Icons.forward, color: Colors.blueGrey), title: const Text('转发'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => ForwardScreen(content: '${message.senderName}: ${message.content}'))); }),
            const Divider(),
            ListTile(leading: const Icon(Icons.checklist, color: Colors.blueGrey), title: const Text('多选'), onTap: () { Navigator.pop(context); }),
            const Divider(),
            if (isMe)
              ListTile(leading: const Icon(Icons.undo, color: Colors.orange), title: const Text('撤回'), onTap: () async {
                Navigator.pop(context);
                try {
                  await ApiService().recallMessage(message.id);
                  if (mounted) setState(() => _messages.removeWhere((m) => m.id == message.id));
                } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('撤回失败: $e'))); }
              }),
            if (isMe)
              ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red), title: const Text('删除', style: TextStyle(color: Colors.red)), onTap: () async {
                Navigator.pop(context);
                final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('删除消息'), content: const Text('确定删除这条消息吗？'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')), TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除', style: TextStyle(color: Colors.red)))],));
                if (confirm == true) {
                  try {
                    await ApiService().deleteGroupMessage(message.id);
                    if (mounted) setState(() => _messages.removeWhere((m) => m.id == message.id));
                  } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败: $e'))); }
                }
              }),
          ]),
        ));
    }

    return GestureDetector(
      onLongPress: showMenu,
      child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            CircleAvatar(radius: 16, child: Text(message.senderName[0].toUpperCase(), style: const TextStyle(fontSize: 13))),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe) Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(message.senderName, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ),
                if (replyPreview != null) replyPreview,
                content,
                const SizedBox(height: 2),
                Text(time, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }

  void _showImagePreview(String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: InteractiveViewer(
          panEnabled: true, boundaryMargin: const EdgeInsets.all(20), minScale: 0.5, maxScale: 4,
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

  // ===== 群设置 → 群资料页 =====
  void _showGroupSettings() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => GroupProfileScreen(group: widget.group)));
  }

  Widget _buildReplyBar() {
    if (_replyTarget == null) return const SizedBox.shrink();
    final target = _replyTarget!;
    final name = target.isFromOwner ? '群主' : target.senderName;
    return Container(
      color: Colors.grey[100],
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(children: [
        Container(width: 3, height: 32, color: const Color(0xFF6C63FF)),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(fontSize: 12, color: Color(0xFF6C63FF), fontWeight: FontWeight.w600)),
          Text(target.content, style: const TextStyle(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
        IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _replyTarget = null), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.group.name),
          Text(widget.group.isOwner ? '群主' : '成员', style: const TextStyle(fontSize: 12)),
        ]),
        actions: [IconButton(icon: const Icon(Icons.more_vert), onPressed: _showGroupSettings)],
      ),
      body: Column(children: [
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Builder(builder: (ctx) {
                  final reversedMsgs = _messages.reversed.toList();
                  return ListView.builder(
                    reverse: true,
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _getItemCountReversed(reversedMsgs),
                    itemBuilder: (context, index) => _buildItemReversed(reversedMsgs, index),
                  );}),
        ),
        if (_replyTarget != null) _buildReplyBar(),
        if (_isSendingFile) const LinearProgressIndicator(),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.grey[100], border: Border(top: BorderSide(color: Colors.grey[300]!))),
          child: Row(children: [
            IconButton(icon: const Icon(Icons.add_circle_outline, color: Color(0xFF6C63FF)), onPressed: () => setState(() => _panelOpen = _panelOpen == 2 ? 0 : 2)),
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: const InputDecoration(hintText: '输入消息...', border: InputBorder.none),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),

            IconButton(icon: const Icon(Icons.emoji_emotions, color: Color(0xFF6C63FF)), onPressed: () => setState(() => _panelOpen = _panelOpen == 1 ? 0 : 1)),
            IconButton(icon: const Icon(Icons.send), onPressed: _sendMessage),
          ]),
        ),
        if (_panelOpen == 1) EmojiPicker(onEmoji: (e) { _messageController.text += e; _messageController.selection = TextSelection.fromPosition(TextPosition(offset: _messageController.text.length)); }),
        if (_panelOpen == 2) PlusMenu(onFile: _sendFile, onImage: _sendFile),
      ]),
    );
  }
}
