import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';

class ExploreSearchScreen extends StatefulWidget {
  const ExploreSearchScreen({super.key});
  @override
  State<ExploreSearchScreen> createState() => _ExploreSearchScreenState();
}

class _ExploreSearchScreenState extends State<ExploreSearchScreen> {
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  List<String> _history = [];
  bool _isLoading = false;
  bool _hasSearched = false;
  String? _portalName;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('explore_history') ?? [];
    if (mounted) setState(() => _history = list);
  }

  Future<void> _saveHistory(String url) async {
    final prefs = await SharedPreferences.getInstance();
    _history.remove(url);
    _history.insert(0, url);
    if (_history.length > 10) _history = _history.sublist(0, 10);
    await prefs.setStringList('explore_history', _history);
    setState(() {});
  }

  String _normalize(String input) {
    var url = input.trim();
    if (url.isEmpty) return url;
    if (!url.startsWith('http')) url = 'https://$url';
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    return url;
  }

  Future<void> _search({String? predefinedUrl}) async {
    final raw = predefinedUrl ?? _controller.text.trim();
    if (raw.isEmpty) return;
    final url = _normalize(raw);
    _controller.text = url;

    setState(() { _isLoading = true; _hasSearched = true; _results = []; _portalName = null; });
    _saveHistory(url);

    try {
      final listingUrl = '$url/api/public/listing';
      final resp = await http.get(Uri.parse(listingUrl), headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final items = jsonDecode(resp.body) as List;
        if (mounted) setState(() { _results = items.cast<Map<String, dynamic>>(); _isLoading = false; _portalName = url; });
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _follow() async {
    if (_portalName == null) return;
    try {
      await ApiService().addFollow(_portalName!);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已关注 $_portalName')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('关注失败')));
    }
  }

  void _openItem(String portal, Map<String, dynamic> item) {
    final itemUrl = item['url'] ?? '';
    final fullUrl = itemUrl.startsWith('http') ? itemUrl : '$portal/$itemUrl';
    launchUrl(Uri.parse(fullUrl.replaceAll(RegExp(r'(?<!:)//+'), '/')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
        title: TextField(
          controller: _controller,
          autofocus: true,
          cursorColor: Colors.white,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: const InputDecoration(
            hintText: '输入域名，如 agentp2p.cn',
            hintStyle: TextStyle(color: Colors.white60),
            border: InputBorder.none,
          ),
          onSubmitted: (_) => _search(),
        ),
        actions: [
          if (_hasSearched)
            IconButton(icon: const Icon(Icons.close), onPressed: () { _controller.clear(); setState(() { _hasSearched = false; _results = []; _portalName = null; }); }),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    if (!_hasSearched) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_history.isNotEmpty) ...[
            const Text('历史搜索', style: TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 8),
            ..._history.map((url) => ListTile(
              leading: const Icon(Icons.history, color: Colors.grey),
              title: Text(url, style: const TextStyle(fontSize: 14)),
              onTap: () => _search(predefinedUrl: url),
            )),
          ],
        ],
      );
    }

    if (_results.isEmpty) {
      return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.search_off, size: 48, color: Colors.grey),
        SizedBox(height: 8),
        Text('未找到公开内容', style: TextStyle(color: Colors.grey)),
        SizedBox(height: 4),
        Text('该 Portal 可能暂无创作', style: TextStyle(fontSize: 13, color: Colors.grey)),
      ]));
    }

    return Column(children: [
      // 关注按钮
      if (_portalName != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: SizedBox(width: double.infinity, child: OutlinedButton.icon(
            icon: const Icon(Icons.bookmark_add, size: 18),
            label: Text('关注 $_portalName'),
            onPressed: _follow,
          )),
        ),
      // 内容列表
      Expanded(child: ListView.builder(
        itemCount: _results.length,
        itemBuilder: (ctx, i) {
          final item = _results[i];
          final icon = {'blog': Icons.article, 'video': Icons.play_circle, 'podcast': Icons.headphones, 'store': Icons.store, 'game': Icons.sports_esports}[item['content_type']] ?? Icons.web;
          return ListTile(
            leading: Icon(icon, color: const Color(0xFF6C63FF)),
            title: Text(item['title'] ?? '', maxLines: 1),
            subtitle: Text(item['description'] ?? '', maxLines: 2, style: const TextStyle(fontSize: 13)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openItem(_portalName!, item),
          );
        },
      )),
    ]);
  }
}
