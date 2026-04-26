import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../services/api_service.dart';
import '../models/group.dart';
import 'chat_detail_screen.dart';
import 'group_chat_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  List<Map<String, dynamic>> _conversations = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    try {
      final data = await ApiService().getConversations();
      if (!mounted) return;
      setState(() {
        _conversations = data;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('加载会话失败: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) _loadConversations();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('消息'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Center(
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: chatProvider.isConnected ? Colors.green : Colors.red,
                ),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _conversations.isEmpty
              ? const Center(child: Text('暂无消息\n去通讯录添加联系人吧', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)))
              : RefreshIndicator(
                  onRefresh: _loadConversations,
                  child: ListView.builder(
                    itemCount: _conversations.length,
                    itemBuilder: (context, index) {
                      final conv = _conversations[index];
                      final isGroup = conv['type'] == 'group';
                      final lastMsg = conv['last_message'] ?? '';
                      final lastTime = conv['last_time'] ?? '';
                      
                      // 格式化时间
                      String timeStr = '';
                      if (lastTime.isNotEmpty) {
                        final dt = DateTime.tryParse(lastTime);
                        if (dt != null) {
                          final now = DateTime.now();
                          if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
                            timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                          } else {
                            timeStr = '${dt.month}/${dt.day}';
                          }
                        }
                      }

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isGroup ? Colors.green[100] : const Color(0xFF6C63FF).withOpacity(0.2),
                          child: isGroup
                              ? const Icon(Icons.group, color: Colors.green, size: 20)
                              : Text(
                                  (conv['name'] ?? '?')[0].toUpperCase(),
                                  style: const TextStyle(color: Color(0xFF6C63FF), fontWeight: FontWeight.bold),
                                ),
                        ),
                        title: Row(
                          children: [
                            Flexible(child: Text(isGroup ? conv['name'] : conv['name'], overflow: TextOverflow.ellipsis)),
                            if (isGroup) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.group, size: 12, color: Colors.grey),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          lastMsg.isEmpty ? '暂无消息' : lastMsg,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(timeStr, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            if (conv['unread_count'] != null && conv['unread_count'] > 0)
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
                                child: Text(
                                  conv['unread_count'] > 99 ? '99+' : '${conv['unread_count']}',
                                  style: const TextStyle(color: Colors.white, fontSize: 11),
                                ),
                              ),
                          ],
                        ),
                        onTap: () {
                          if (isGroup) {
                            final group = Group(
                              id: conv['id'],
                              name: conv['name'],
                              ownerId: 0,
                              memberCount: conv['member_count'] ?? 0,
                              isOwner: conv['is_owner'] ?? false,
                              createdAt: DateTime.now(),
                              groupUuid: conv['group_uuid'],
                            );
                            Navigator.push(context, MaterialPageRoute(builder: (_) => GroupChatScreen(group: group)));
                          } else {
                            // 找对应联系人
                            dynamic foundContact;
                            for (final c in chatProvider.contacts) {
                              if (c.id == conv['id'] || c.portalUrl == conv['portal_url']) {
                                foundContact = c;
                                break;
                              }
                            }
                            if (foundContact != null) {
                              chatProvider.selectContact(foundContact);
                              Navigator.push(context, MaterialPageRoute(
                                builder: (_) => ChatDetailScreen(key: ValueKey('chat_${foundContact.id}')),
                              ));
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('联系人不存在，请重新添加')),
                              );
                            }
                          }
                        },
                      );
                    },
                  ),
                ),
    );
  }
}
