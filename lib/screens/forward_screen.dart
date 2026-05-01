import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../services/api_service.dart';
import '../models/group.dart';

class ForwardScreen extends StatelessWidget {
  final String content;

  const ForwardScreen({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    final contacts = context.watch<ChatProvider>().contacts;

    return Scaffold(
      appBar: AppBar(title: const Text('转发给...')),
      body: ListView(
        children: [
          if (contacts.isNotEmpty) ...[
            const Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 4), child: Text('联系人', style: TextStyle(color: Colors.grey, fontSize: 13))),
            ...contacts.map((c) => _buildContactTile(context, c)),
          ],
          const Divider(),
          const Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 4), child: Text('群聊', style: TextStyle(color: Colors.grey, fontSize: 13))),
          _GroupList(content: content),
        ],
      ),
    );
  }

  Widget _buildContactTile(BuildContext context, c) {
    return ListTile(
      leading: CircleAvatar(backgroundColor: const Color(0xFF6C63FF), child: Text(c.displayName[0].toUpperCase(), style: const TextStyle(color: Colors.white))),
      title: Text(c.displayName),
      onTap: () async {
        try {
          await ApiService().sendMessage(c.id, content);
          if (context.mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已转发'))); }
        } catch (e) {
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('转发失败: $e')));
        }
      },
    );
  }
}

class _GroupList extends StatefulWidget {
  final String content;
  const _GroupList({required this.content});

  @override
  State<_GroupList> createState() => _GroupListState();
}

class _GroupListState extends State<_GroupList> {
  List<Group> _groups = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() async {
    try {
      final data = await ApiService().getGroups();
      if (mounted) setState(() => _groups = data.map((g) => Group.fromJson(g)).toList());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: _groups.map((g) => ListTile(
        leading: CircleAvatar(backgroundColor: Colors.green[100], child: const Icon(Icons.group, color: Colors.green, size: 20)),
        title: Text(g.name),
        subtitle: Text('${g.memberCount} 名成员', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        onTap: () async {
          try {
            await ApiService().sendGroupMessage(g.id, widget.content, isOwner: g.isOwner);
            if (context.mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已转发'))); }
          } catch (e) {
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('转发失败: $e')));
          }
        },
      )).toList(),
    );
  }
}
