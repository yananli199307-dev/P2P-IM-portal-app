import 'package:flutter/material.dart';
import '../services/api_service.dart';

class InChatSearchScreen extends StatefulWidget {
  final int contactId;
  const InChatSearchScreen({super.key, required this.contactId});

  @override
  State<InChatSearchScreen> createState() => _InChatSearchScreenState();
}

class _InChatSearchScreenState extends State<InChatSearchScreen> {
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;

  void _search() {
    final kw = _controller.text.trim();
    if (kw.isEmpty) return;
    setState(() => _loading = true);
    ApiService().searchMessages(kw, limit: 50).then((all) {
      if (mounted) setState(() {
        _results = all.where((m) => m['type'] == 'private' && m['contact_id'] == widget.contactId).toList();
        _loading = false;
      });
    }).catchError((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: TextField(controller: _controller, autofocus: true,
        decoration: const InputDecoration(hintText: '查找聊天记录', border: InputBorder.none),
        onChanged: (_) => _search(),
      )),
      body: _loading ? const Center(child: CircularProgressIndicator())
          : _results.isEmpty && _controller.text.isNotEmpty ? const Center(child: Text('未找到相关消息', style: TextStyle(color: Colors.grey)))
          : ListView.builder(itemCount: _results.length, itemBuilder: (_, i) {
              final m = _results[i];
              return ListTile(title: Text(m['content'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(m['created_at']?.toString().substring(0, 16) ?? '', style: TextStyle(fontSize: 12, color: Colors.grey[500])));
            }),
    );
  }
}
