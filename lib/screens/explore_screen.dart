import 'dart:html' as html;

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

  void _openUrl() {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    // 如果没有 http 前缀，加上 https://
    final fullUrl = url.startsWith('http') ? url : 'https://$url';
    _launchUrl(fullUrl);
  }

  void _launchUrl(String url) {
    html.window.open(url, '_blank');
  }

  void _addFollow() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    final fullUrl = url.startsWith('http') ? url : 'https://$url';
    try {
      await ApiService().addFollow(fullUrl);
      _urlController.clear();
      _loadFollows();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已添加关注')));
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
            child: Row(children: [
              Expanded(child: TextField(
                controller: _urlController,
                decoration: InputDecoration(
                  hintText: '输入 Portal URL 去浏览',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true, fillColor: Colors.grey[100],
                ),
                onSubmitted: (_) => _openUrl(),
              )),
              const SizedBox(width: 8),
              IconButton(icon: const Icon(Icons.open_in_browser, color: Color(0xFF6C63FF)), onPressed: _openUrl, tooltip: '打开浏览'),
              IconButton(icon: const Icon(Icons.bookmark_add, color: Colors.orange), onPressed: _addFollow, tooltip: '关注'),
            ]),
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
