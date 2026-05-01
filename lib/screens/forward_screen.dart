import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../services/api_service.dart';
import '../models/group.dart';

class ForwardScreen extends StatefulWidget {
  final String content;

  const ForwardScreen({super.key, required this.content});

  @override
  State<ForwardScreen> createState() => _ForwardScreenState();
}

class _ForwardScreenState extends State<ForwardScreen> {
  final Set<int> _selectedContacts = {};
  final Set<int> _selectedGroups = {};
  List<Group> _groups = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  void _loadGroups() async {
    try {
      final data = await ApiService().getGroups();
      if (mounted) setState(() { _groups = data.map((g) => Group.fromJson(g)).toList(); _loaded = true; });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _doForward() async {
    final total = _selectedContacts.length + _selectedGroups.length;
    if (total == 0) return;
    int ok = 0;
    for (final cid in _selectedContacts) {
      try { await ApiService().sendMessage(cid, widget.content); ok++; } catch (_) {}
    }
    for (final g in _groups) {
      if (!_selectedGroups.contains(g.id)) continue;
      try { await ApiService().sendGroupMessage(g.id, widget.content, isOwner: g.isOwner); ok++; } catch (_) {}
    }
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已转发到 $ok 个会话')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final contacts = context.watch<ChatProvider>().contacts;
    final total = _selectedContacts.length + _selectedGroups.length;

    return Scaffold(
      appBar: AppBar(title: Text(total > 0 ? '已选 $total 个' : '转发给...'), actions: [
        if (total > 0) TextButton(onPressed: _doForward, child: const Text('发送')),
      ]),
      body: _loaded ? ListView(children: [
        if (contacts.isNotEmpty) ...[
          const Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 4), child: Text('联系人', style: TextStyle(color: Colors.grey, fontSize: 13))),
          ...contacts.map((c) => ListTile(
            leading: CircleAvatar(backgroundColor: const Color(0xFF6C63FF), child: Text(c.displayName[0].toUpperCase(), style: const TextStyle(color: Colors.white))),
            title: Text(c.displayName),
            trailing: Icon(_selectedContacts.contains(c.id) ? Icons.check_circle : Icons.radio_button_unchecked, color: const Color(0xFF6C63FF)),
            onTap: () => setState(() { if (_selectedContacts.contains(c.id)) _selectedContacts.remove(c.id); else _selectedContacts.add(c.id); }),
          )),
        ],
        const Divider(),
        const Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 4), child: Text('群聊', style: TextStyle(color: Colors.grey, fontSize: 13))),
        ..._groups.map((g) => ListTile(
          leading: CircleAvatar(backgroundColor: Colors.green[100], child: const Icon(Icons.group, color: Colors.green, size: 20)),
          title: Text(g.name),
          trailing: Icon(_selectedGroups.contains(g.id) ? Icons.check_circle : Icons.radio_button_unchecked, color: const Color(0xFF6C63FF)),
          onTap: () => setState(() { if (_selectedGroups.contains(g.id)) _selectedGroups.remove(g.id); else _selectedGroups.add(g.id); }),
        )),
        if (_groups.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('暂无群聊', style: TextStyle(color: Colors.grey))),
      ]) : const Center(child: CircularProgressIndicator()),
    );
  }
}
