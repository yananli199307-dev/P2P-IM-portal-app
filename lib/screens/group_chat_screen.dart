import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import "package:provider/provider.dart";
import "../providers/chat_provider.dart";
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../models/group.dart';
import 'invite_member_screen.dart';
import 'group_members_screen.dart';

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
  bool _shouldScrollToBottom = true;
  GroupMessage? _replyTarget;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadMessages();
  }

  void _onScroll() {
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

  Future<void> _loadMessages() async {
    try {
      List<Map<String, dynamic>> messagesData;
      if (widget.group.isOwner) {
        messagesData = await ApiService().getGroupMessages(widget.group.id);
      } else {
        messagesData = await ApiService().getGroupMessagesByUuid(widget.group.groupUuid!);
      }
      if (!mounted) return;
      setState(() {
        // 反转消息顺序：服务端返回最新在前，反转后最早在上最新在下
        _messages = messagesData.reversed.map((m) => GroupMessage.fromJson(m)).toList();
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;
    final reply = _replyTarget;
    _messageController.clear();
    try {
      await ApiService().sendGroupMessage(
        widget.group.id, content,
        groupUuid: widget.group.groupUuid,
        isOwner: widget.group.isOwner,
        replyToMessageId: reply?.id,
        replyToContent: reply != null ? (reply.content.length > 50 ? '${reply.content.substring(0, 50)}...' : reply.content) : null,
        replyToSenderName: reply?.isFromOwner == true ? '群主' : (reply?.senderName ?? '成员'),
      );
      if (mounted) setState(() => _replyTarget = null);
      // 更新消息列表排序
      context.read<ChatProvider>().updateGroupLastMessage(widget.group.id, content);
      _shouldScrollToBottom = true;
      _loadMessages();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发送失败: $e')));
    }
  }

  Future<void> _sendFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: false);
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
      _shouldScrollToBottom = true;
      setState(() => _isSendingFile = false);
      _loadMessages();
    } catch (e) {
      setState(() => _isSendingFile = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发送文件失败: $e')));
    }
  }

  // ===== 消息列表（含日期分割线） =====

  int _getItemCount() {
    int count = 0;
    String? lastDate;
    for (final msg in _messages) {
      final dateKey = DateFormat('yyyy-MM-dd').format(msg.createdAt);
      if (dateKey != lastDate) { count++; lastDate = dateKey; }
      count++;
    }
    return count;
  }

  Widget _buildItem(int displayIndex) {
    int msgIndex = 0;
    String? lastDate;
    for (int i = 0; i < _messages.length; i++) {
      final dateKey = DateFormat('yyyy-MM-dd').format(_messages[i].createdAt);
      if (dateKey != lastDate) {
        if (displayIndex == msgIndex) return _buildDateSeparator(_messages[i].createdAt);
        msgIndex++; lastDate = dateKey;
      }
      if (displayIndex == msgIndex) return _buildMessageBubble(_messages[i]);
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
            const Icon(Icons.attach_file),
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
        child: Text(message.content),
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

    return GestureDetector(
      onLongPress: () {
        showModalBottomSheet(context: context, builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.reply, color: Color(0xFF6C63FF)), title: const Text('回复'), onTap: () { setState(() => _replyTarget = message); Navigator.pop(context); }),
          ListTile(leading: const Icon(Icons.copy, color: Colors.grey), title: const Text('复制'), onTap: () { Navigator.pop(context); }),
        ])));
      },
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

  // ===== 群设置弹窗 =====

  void _showInviteDialog() => Navigator.push(context, MaterialPageRoute(builder: (_) => InviteMemberScreen(groupId: widget.group.id)));
  void _showMembersDialog() => Navigator.push(context, MaterialPageRoute(builder: (_) => GroupMembersScreen(group: widget.group)));

  void _showGroupSettings() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(leading: const Icon(Icons.people), title: const Text('群成员'),
            onTap: () { Navigator.pop(ctx); _showMembersDialog(); }),
          ListTile(leading: const Icon(Icons.person_add), title: const Text('邀请成员'),
            onTap: () { Navigator.pop(ctx); _showInviteDialog(); }),
          if (widget.group.isOwner) ...[
            ListTile(leading: const Icon(Icons.edit), title: const Text('修改群名'),
              onTap: () { Navigator.pop(ctx); _showRenameDialog(); }),
            ListTile(leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('解散群组', style: TextStyle(color: Colors.red)),
              onTap: () { Navigator.pop(ctx); _showDissolveDialog(); }),
          ] else ...[
            ListTile(leading: const Icon(Icons.exit_to_app, color: Colors.red),
              title: const Text('退出群组', style: TextStyle(color: Colors.red)),
              onTap: () { Navigator.pop(ctx); _showLeaveDialog(); }),
          ],
        ],
      ),
    );
  }

  void _showRenameDialog() {
    final ctrl = TextEditingController(text: widget.group.name);
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('修改群名'), content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: '新群名')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        TextButton(onPressed: () async {
          try {
            await ApiService().updateGroupName(widget.group.id, ctrl.text);
            Navigator.pop(ctx);
            setState(() {});
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('群名已修改')));
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('修改失败: $e')));
          }
        }, child: const Text('确定')),
      ],
    ));
  }

  void _showDissolveDialog() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('解散群组'), content: const Text('确定要解散这个群组吗？此操作不可恢复。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        TextButton(onPressed: () async {
          try {
            await ApiService().dissolveGroup(widget.group.id);
            Navigator.pop(ctx); Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('群组已解散')));
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('解散失败: $e')));
          }
        }, style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('解散')),
      ],
    ));
  }

  void _showLeaveDialog() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('退出群组'), content: const Text('确定要退出这个群组吗？'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        TextButton(onPressed: () async {
          try {
            await ApiService().leaveGroup(widget.group.id);
            Navigator.pop(ctx); Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已退出群组')));
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('退出失败: $e')));
          }
        }, style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('退出')),
      ],
    ));
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
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _getItemCount(),
                  itemBuilder: (context, index) => _buildItem(index),
                ),
        ),
        if (_replyTarget != null) _buildReplyBar(),
        if (_isSendingFile) const LinearProgressIndicator(),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.grey[100], border: Border(top: BorderSide(color: Colors.grey[300]!))),
          child: Row(children: [
            IconButton(icon: const Icon(Icons.attach_file), onPressed: _isSendingFile ? null : _sendFile),
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: const InputDecoration(hintText: '输入消息...', border: InputBorder.none),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            IconButton(icon: const Icon(Icons.send), onPressed: _sendMessage),
          ]),
        ),
      ]),
    );
  }
}
