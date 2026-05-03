import 'package:url_launcher/url_launcher.dart';
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
  bool _showAllFollows = false;

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
    launchUrl(Uri.parse(url.startsWith('http') ? url : 'https://$url'));
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
    try { await ApiService().removeFollow(id); _loadFollows(); } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('探索')),
      body: ListView(children: [
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
            IconButton(icon: const Icon(Icons.open_in_browser, color: Color(0xFF6C63FF)), onPressed: _openUrl, tooltip: '打开'),
            IconButton(icon: const Icon(Icons.bookmark_add, color: Colors.orange), onPressed: _addFollow, tooltip: '关注'),
          ]),
        ),

        // 我的关注
        if (_follows.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(children: [
              const Icon(Icons.star, color: Colors.amber, size: 20),
              const SizedBox(width: 4),
              Text('我的关注', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[800])),
              const Spacer(),
              TextButton(onPressed: () => setState(() => _showAllFollows = !_showAllFollows),
                child: Text(_showAllFollows ? '收起' : '查看全部 ${_follows.length}', style: const TextStyle(fontSize: 13))),
            ]),
          ),
          if (!_showAllFollows)
            // 紧凑模式：水平滚动头像
            SizedBox(height: 80, child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _follows.length,
              itemBuilder: (_, i) {
                final f = _follows[i];
                final name = f['display_name'] ?? f['portal_url'] ?? '?';
                return GestureDetector(
                  onTap: () => launchUrl(Uri.parse(f['portal_url'] ?? '')),
                  onLongPress: () => _removeFollow(f['id']),
                  child: Container(width: 64, margin: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(children: [
                      CircleAvatar(radius: 24, backgroundColor: Colors.orange[100], child: Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))),
                      const SizedBox(height: 4),
                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                    ])),
                );
              },
            ))
          else
            // 展开模式：列表
            ..._follows.map((f) => ListTile(
              leading: CircleAvatar(backgroundColor: Colors.orange[100], child: Text((f['display_name'] ?? '?')[0].toUpperCase(), style: const TextStyle(color: Colors.orange))),
              title: Text(f['display_name'] ?? f['portal_url'] ?? ''),
              subtitle: Text(f['portal_url'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              trailing: IconButton(icon: const Icon(Icons.close, size: 18, color: Colors.grey), onPressed: () => _removeFollow(f['id'])),
              onTap: () => launchUrl(Uri.parse(f['portal_url'] ?? '')),
            )),
          const SizedBox(height: 8),
        ],

        const Divider(),

        // Agent 精选
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(children: [
            const Icon(Icons.auto_awesome, color: Color(0xFF6C63FF), size: 20),
            const SizedBox(width: 4),
            Text('Agent 精选', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[800])),
          ]),
        ),
        const SizedBox(height: 32),
        const Center(child: Column(children: [
          Icon(Icons.lightbulb_outline, size: 48, color: Colors.grey),
          SizedBox(height: 8),
          Text('Agent 正在学习中...', style: TextStyle(color: Colors.grey)),
          SizedBox(height: 4),
          Text('稍后会为你推荐有趣的内容', style: TextStyle(fontSize: 13, color: Colors.grey)),
        ])),
        const SizedBox(height: 64),
      ]),
    );
  }
}
