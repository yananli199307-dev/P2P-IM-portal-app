import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _urlController = TextEditingController();
  List<Map<String, dynamic>> _follows = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadFollows();
  }

  void _loadFollows() async {
    setState(() => _loading = true);
    try {
      final data = await ApiService().getFollows();
      if (mounted) setState(() { _follows = data; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _addFollow() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    try {
      await ApiService().addFollow(url);
      _urlController.clear();
      _loadFollows();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('关注失败: $e')));
    }
  }

  void _removeFollow(int id) async {
    try {
      await ApiService().removeFollow(id);
      _loadFollows();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('取消关注失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('探索')),
      body: Column(
        children: [
          // 搜索栏
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _urlController,
              decoration: InputDecoration(
                hintText: '输入 Portal URL 或关键词搜索',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(icon: const Icon(Icons.add_circle, color: Color(0xFF6C63FF)), onPressed: _addFollow),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true, fillColor: Colors.grey[100],
              ),
              onSubmitted: (_) => _addFollow(),
            ),
          ),
          // 关注列表
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _follows.isEmpty
                    ? const Center(child: Text('还没有关注任何人\n输入 Portal URL 开始探索', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        itemCount: _follows.length,
                        itemBuilder: (_, i) {
                          final f = _follows[i];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.orange[100],
                              child: Text((f['display_name'] ?? f['portal_url'] ?? '?')[0].toUpperCase(), style: const TextStyle(color: Colors.orange)),
                            ),
                            title: Text(f['display_name'] ?? f['portal_url'] ?? ''),
                            subtitle: Text(f['portal_url'] ?? '', textAlign: TextAlign.left, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                            trailing: IconButton(icon: const Icon(Icons.star, color: Colors.amber), onPressed: () => _removeFollow(f['id'])),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
