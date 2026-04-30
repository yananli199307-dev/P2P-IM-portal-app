import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'chat_detail_screen.dart';
import 'group_chat_screen.dart';
import 'agent_chat_screen.dart';
import '../models/group.dart';
import '../models/contact.dart';
import 'package:intl/intl.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _isLoading = false;
  bool _hasSearched = false;

  Future<void> _search() async {
    final keyword = _controller.text.trim();
    if (keyword.isEmpty) return;

    setState(() { _isLoading = true; _hasSearched = true; });
    try {
      final results = await ApiService().searchMessages(keyword);
      if (mounted) setState(() { _results = results; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _results = []; });
    }
  }

  String _formatTime(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return DateFormat('HH:mm').format(dt);
    }
    return DateFormat('MM-dd').format(dt);
  }

  String _highlightText(String text) {
    final keyword = _controller.text.trim();
    if (keyword.isEmpty) return text;
    // 截断过长内容
    if (text.length > 80) text = '${text.substring(0, 80)}...';
    return text;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '搜索消息内容',
            border: InputBorder.none,
          ),
          onChanged: (_) => _search(),
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(icon: const Icon(Icons.clear), onPressed: () { _controller.clear(); setState(() { _results = []; _hasSearched = false; }); }),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _hasSearched && _results.isEmpty
              ? const Center(child: Text('未找到相关消息', style: TextStyle(color: Colors.grey)))
              : _results.isEmpty
                  ? const Center(child: Text('输入关键词搜索', style: TextStyle(color: Colors.grey)))
                  : ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = _results[index];
                        final isGroup = item['type'] == 'group';
                        final title = isGroup ? item['group_name'] ?? '群聊' : item['contact_name'] ?? '联系人';
                        final subtitle = isGroup ? '${item['sender_name'] ?? ''}: ${item['content'] ?? ''}' : item['content'] ?? '';

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isGroup ? Colors.green[100] : const Color(0xFF6C63FF),
                            child: Icon(isGroup ? Icons.group : Icons.person, color: isGroup ? Colors.green : Colors.white, size: 20),
                          ),
                          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
                          subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: Text(_formatTime(item['created_at']), style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                          onTap: () {
                            Navigator.pop(context);
                            if (isGroup) {
                              Navigator.push(context, MaterialPageRoute(
                                builder: (_) => GroupChatScreen(group: Group(
                                  id: item['group_id'] ?? 0,
                                  name: item['group_name'] ?? '群聊',
                                  ownerId: 0,
                                  isOwner: false,
                                  createdAt: DateTime.now(),
                                )),
                              ));
                            } else if (item['contact_id'] == 0) {
                              Navigator.push(context, MaterialPageRoute(
                                builder: (_) => const AgentChatScreen(),
                              ));
                            } else {
                              // 跳转到私聊
                              Navigator.push(context, MaterialPageRoute(
                                builder: (_) => ChatDetailScreen(key: ValueKey('search_${item['id']}')),
                              ));
                            }
                          },
                        );
                      },
                    ),
    );
  }
}
