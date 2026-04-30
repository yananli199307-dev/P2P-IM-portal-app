import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/contact.dart';
import '../services/api_service.dart';
import '../providers/chat_provider.dart';

class ChatInfoScreen extends StatefulWidget {
  final Contact contact;
  const ChatInfoScreen({super.key, required this.contact});

  @override
  State<ChatInfoScreen> createState() => _ChatInfoScreenState();
}

class _ChatInfoScreenState extends State<ChatInfoScreen> {
  late bool _muteNotifications;
  late bool _pinChat;

  @override
  void initState() {
    super.initState();
    _pinChat = widget.contact.isPinned;
    _muteNotifications = false;
    // 从 contact 列表读取最新状态
    final contact = context.read<ChatProvider>().contacts.firstWhere((c) => c.id == widget.contact.id, orElse: () => widget.contact);
    _pinChat = contact.isPinned;
  }

  void _togglePin(bool v) async {
    try {
      await ApiService().updateContact(widget.contact.id, isPinned: v);
      setState(() => _pinChat = v);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('操作失败: $e')));
    }
  }

  void _clearHistory() async {
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('清空聊天记录'),
      content: const Text('确定清空与该联系人的所有聊天记录吗？此操作不可恢复。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('清空')),
      ],
    ));
    if (confirm == true) {
      try {
        await ApiService().clearContactMessages(widget.contact.id);
        if (mounted) {
          context.read<ChatProvider>().clearMessages();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('聊天记录已清空')));
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('清空失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('聊天信息')),
      body: ListView(
        children: [
          const SizedBox(height: 24),
          // 头像 + 昵称
          Center(
            child: CircleAvatar(
              radius: 40,
              backgroundColor: const Color(0xFF6C63FF),
              child: Text(widget.contact.displayName[0].toUpperCase(), style: const TextStyle(fontSize: 32, color: Colors.white)),
            ),
          ),
          const SizedBox(height: 12),
          Center(child: Text(widget.contact.displayName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
          Center(child: Text(widget.contact.portalUrl, style: TextStyle(fontSize: 13, color: Colors.grey[500]))),
          const SizedBox(height: 24),
          const Divider(),

          // 置顶聊天
          SwitchListTile(
            secondary: const Icon(Icons.push_pin, color: Colors.blueGrey),
            title: const Text('置顶聊天'),
            value: _pinChat,
            onChanged: _togglePin,
          ),
          const Divider(),

          // 消息免打扰
          SwitchListTile(
            secondary: const Icon(Icons.notifications_off, color: Colors.grey),
            title: const Text('消息免打扰'),
            value: _muteNotifications,
            onChanged: (v) => setState(() => _muteNotifications = v),
          ),
          const Divider(),

          // 查找聊天记录
          ListTile(
            leading: const Icon(Icons.search, color: Colors.blueGrey),
            title: const Text('查找聊天记录'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // TODO: 会话内搜索
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('会话内搜索功能即将上线')));
            },
          ),
          const Divider(),

          // 清空聊天记录
          ListTile(
            leading: const Icon(Icons.delete_sweep, color: Colors.red),
            title: const Text('清空聊天记录', style: TextStyle(color: Colors.red)),
            onTap: _clearHistory,
          ),
          const Divider(),

          // 共享文件
          ListTile(
            leading: const Icon(Icons.folder, color: Colors.blueGrey),
            title: const Text('共享文件'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('共享文件功能即将上线')));
            },
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
