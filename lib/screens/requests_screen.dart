import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key});

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  List<dynamic> _requests = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final apiService = ApiService();
      apiService.initialize();
      
      final authProvider = context.read<AuthProvider>();
      if (authProvider.portalUrl != null) {
        await apiService.setPortalUrl(authProvider.portalUrl!);
      }
      
      final requests = await apiService.getReceivedRequests();
      setState(() {
        _requests = requests;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _approveRequest(int requestId) async {
    try {
      final apiService = ApiService();
      apiService.initialize();
      
      final authProvider = context.read<AuthProvider>();
      if (authProvider.portalUrl != null) {
        await apiService.setPortalUrl(authProvider.portalUrl!);
      }
      
      await apiService.approveRequest(requestId);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已批准，已添加为联系人')),
      );
      
      // 刷新列表
      _loadRequests();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('批准失败: $e')),
      );
    }
  }

  Future<void> _rejectRequest(int requestId) async {
    try {
      final apiService = ApiService();
      apiService.initialize();
      
      final authProvider = context.read<AuthProvider>();
      if (authProvider.portalUrl != null) {
        await apiService.setPortalUrl(authProvider.portalUrl!);
      }
      
      await apiService.rejectRequest(requestId);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已拒绝')),
      );
      
      // 刷新列表
      _loadRequests();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('拒绝失败: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('联系人请求'),
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRequests,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('加载失败: $_error'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadRequests,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_requests.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              '暂无新的联系人请求',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _requests.length,
      itemBuilder: (context, index) {
        final request = _requests[index];
        return _buildRequestItem(request);
      },
    );
  }

  Widget _buildRequestItem(dynamic request) {
    final name = request['requester_name'] ?? '未知用户';
    final portal = request['requester_portal'] ?? '';
    final message = request['message'];
    final requestId = request['id'];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFF6C63FF),
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        portal,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (message != null && message.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  message,
                  style: TextStyle(color: Colors.grey[700]),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _rejectRequest(requestId),
                  child: const Text('拒绝', style: TextStyle(color: Colors.red)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _approveRequest(requestId),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C63FF),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('批准'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
