import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});
  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _urlController = TextEditingController();
  List<Map<String, dynamic>> _follows = [];
  List<_ContentCard> _feed = [];
  bool _loadingFollows = false;
  bool _loadingFeed = false;
  bool _showAllFollows = false;

  @override
  void initState() {
    super.initState();
    _loadFollows();
    _loadFeed();
  }

  Future<void> _loadFollows() async {
    setState(() => _loadingFollows = true);
    try {
      final data = await ApiService().getFollows();
      if (mounted) setState(() { _follows = data; _loadingFollows = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingFollows = false);
    }
  }

  Future<void> _loadFeed() async {
    setState(() => _loadingFeed = true);
    try {
      final follows = await ApiService().getFollows();
      final cards = <_ContentCard>[];
      for (final f in follows) {
        final portal = f['portal_url'] as String? ?? '';
        if (portal.isEmpty) continue;
        final name = f['display_name'] as String? ?? portal;
        try {
          final uri = Uri.parse('$portal/api/public/listing'.replaceAll(RegExp(r'(?<!:)//+'), '/'));
          final resp = await http.get(uri, headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 8));
          if (resp.statusCode == 200) {
            final items = jsonDecode(resp.body) as List;
            for (final item in items) {
              cards.add(_ContentCard(
                portalName: name,
                portalUrl: portal,
                title: item['title'] ?? '',
                description: item['description'] ?? '',
                contentType: item['content_type'] ?? 'page',
                url: '${portal}/${item['url']}'.replaceAll(RegExp(r'(?<!:)//+'), '/'),
                thumbnailUrl: item['thumbnail_url'] != null ? '${portal}/${item['thumbnail_url']}' : null,
                updatedAt: DateTime.tryParse(item['updated_at'] ?? '') ?? DateTime.now(),
              ));
            }
          }
        } catch (_) {}
      }
      cards.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      if (mounted) setState(() { _feed = cards; _loadingFeed = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingFeed = false);
    }
  }

  void _openUrl() {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    launchUrl(Uri.parse(url.startsWith('http') ? url : 'https://$url'));
  }

  Future<void> _showSearchDialog() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('发现 Portal'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入 Portal URL'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('关注')),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      _urlController.text = result.trim();
      _addFollow();
    }
  }

  Future<void> _addFollow() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    final fullUrl = url.startsWith('http') ? url : 'https://$url';
    try {
      await ApiService().addFollow(fullUrl);
      _urlController.clear();
      await _loadFollows();
      await _loadFeed();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已添加关注')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('关注失败: $e')));
    }
  }

  Future<void> _removeFollow(int id) async {
    try { await ApiService().removeFollow(id); _loadFollows(); _loadFeed(); } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('探索'), actions: [
        IconButton(icon: const Icon(Icons.search), onPressed: _showSearchDialog, tooltip: '搜索'),
        IconButton(icon: const Icon(Icons.refresh), onPressed: _loadFeed, tooltip: '刷新'),
      ]),
      body: RefreshIndicator(
        onRefresh: () async { await _loadFeed(); await _loadFollows(); },
        child: ListView(children: [
          // 我的关注
          if (_follows.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Row(children: [
                const Icon(Icons.star, color: Colors.amber, size: 20),
                const SizedBox(width: 4),
                Text('我的关注', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[800])),
                const Spacer(),
                TextButton(onPressed: () => setState(() => _showAllFollows = !_showAllFollows),
                  child: Text(_showAllFollows ? '收起' : '${_follows.length} 个创作者', style: const TextStyle(fontSize: 13))),
              ]),
            ),
            if (!_showAllFollows)
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
              ..._follows.map((f) => ListTile(
                leading: CircleAvatar(backgroundColor: Colors.orange[100], child: Text((f['display_name'] ?? '?')[0].toUpperCase(), style: const TextStyle(color: Colors.orange))),
                title: Text(f['display_name'] ?? f['portal_url'] ?? ''),
                subtitle: Text(f['portal_url'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                trailing: IconButton(icon: const Icon(Icons.close, size: 18, color: Colors.grey), onPressed: () => _removeFollow(f['id'])),
                onTap: () => launchUrl(Uri.parse(f['portal_url'] ?? '')),
              )),
            const SizedBox(height: 8),
          ],

          // 内容流
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(children: [
              const Icon(Icons.auto_awesome, color: Color(0xFF6C63FF), size: 20),
              const SizedBox(width: 4),
              Text('创作动态', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[800])),
            ]),
          ),

          if (_loadingFeed)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))

          else if (_feed.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(child: Column(children: [
                Icon(Icons.explore_outlined, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 8),
                Text('关注创作者后\n他们的内容会出现在这里', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[500])),
              ])),
            )
          else
            ..._feed.map((card) => _buildCard(card)),

          const SizedBox(height: 64),
        ]),
      ),
    );
  }

  Widget _buildCard(_ContentCard card) {
    final typeIcons = {
      'blog': Icons.article, 'video': Icons.play_circle, 'game': Icons.sports_esports,
      'store': Icons.store, '3d': Icons.view_in_ar, 'page': Icons.web,
    };
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        onTap: () => launchUrl(Uri.parse(card.url)),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 56, height: 56,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: Colors.grey[200]),
              child: card.thumbnailUrl != null
                ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(card.thumbnailUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(typeIcons[card.contentType] ?? Icons.web, color: const Color(0xFF6C63FF), size: 28)))
                : Icon(typeIcons[card.contentType] ?? Icons.web, color: const Color(0xFF6C63FF), size: 28)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(card.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15), maxLines: 1),
              if (card.description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(card.description, style: TextStyle(color: Colors.grey[600], fontSize: 13), maxLines: 2),
              ],
              const SizedBox(height: 4),
              Row(children: [
                CircleAvatar(radius: 8, backgroundColor: Colors.orange[100], child: Text(card.portalName[0].toUpperCase(), style: const TextStyle(fontSize: 8, color: Colors.orange))),
                const SizedBox(width: 4),
                Text(card.portalName, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                const Spacer(),
                Text(_timeAgo(card.updatedAt), style: TextStyle(fontSize: 11, color: Colors.grey[400])),
              ]),
            ])),
          ]),
        ),
      ),
    );
  }

  String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    return '${diff.inDays}天前';
  }
}

class _ContentCard {
  final String portalName, portalUrl, title, description, contentType, url;
  final String? thumbnailUrl;
  final DateTime updatedAt;
  _ContentCard({required this.portalName, required this.portalUrl, required this.title, required this.description, required this.contentType, required this.url, this.thumbnailUrl, required this.updatedAt});
}
