import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../services/api_service.dart';
import "../providers/auth_provider.dart";
import '../models/group.dart';
import '../models/contact.dart';
import 'chat_detail_screen.dart';
import 'group_chat_screen.dart';
import 'agent_chat_screen.dart';
import 'search_screen.dart';

/// 消息列表混合项
class _ChatItem {
  final Contact? contact;
  final Group? group;
  final DateTime time;
  final String preview;

  _ChatItem({this.contact, this.group, required this.time, required this.preview});

  String get title => contact?.displayName ?? group?.name ?? '';
  bool get isGroup => group != null;
  int get id => contact?.id ?? group?.id ?? 0;
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  List<Group> _groups = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final chatProvider = context.read<ChatProvider>();
      // 先并行加载联系人和最新消息时间
      await Future.wait([
        chatProvider.loadContacts(),
        chatProvider.loadLatestMessages(),
      ]);
      // 再加载群组
      final groupsData = await ApiService().getGroups();
      if (!mounted) return;
      setState(() {
        _groups = groupsData.map((g) => Group.fromJson(g, ownerPortal: context.read<AuthProvider>().portalUrl)).toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  /// 合并联系人 + 群聊 + My Agent，按最后消息时间排序（微信风格）
  List<_ChatItem> _buildChatList(ChatProvider provider) {
    final items = <_ChatItem>[];
    final lastMsg = provider.lastMessageTime;
    final lastPreview = provider.lastMessagePreview;

    // My Agent 固定在列表顶部（如果有消息）
    final agentKey = 'contact_0';
    final agentTime = lastMsg[agentKey];
    if (agentTime != null) {
      items.add(_ChatItem(
        group: Group(
          id: 0,
          name: 'My Agent',
          ownerId: 0,
          isOwner: true,
          createdAt: agentTime,
        ),
        time: agentTime,
        preview: lastPreview[agentKey] ?? '',
      ));
    }

    for (final contact in provider.contacts) {
      final key = 'contact_${contact.id}';
      items.add(_ChatItem(
        contact: contact,
        time: lastMsg[key] ?? DateTime.fromMillisecondsSinceEpoch(0),
        preview: lastPreview[key] ?? '点击开始聊天',
      ));
    }

    for (final group in _groups) {
      final key = 'group_${group.id}';
      items.add(_ChatItem(
        group: group,
        time: lastMsg[key] ?? group.createdAt,
        preview: lastPreview[key] ?? '群聊',
      ));
    }

    // 时间倒序：最新消息在最上面
    items.sort((a, b) => b.time.compareTo(a.time));
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('消息'),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: () { Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())); }),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                width: 8, height: 8,
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
          : chatProvider.contacts.isEmpty && _groups.isEmpty
              ? const Center(child: Text('暂无消息\n去通讯录添加联系人吧', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)))
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: Consumer<ChatProvider>(
                    builder: (_, provider, __) {
                      final items = _buildChatList(provider);
                      return ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final unreadCount = item.isGroup ? 0 : (provider.unreadCounts[item.id] ?? 0);
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: item.isGroup ? Colors.green[100] : const Color(0xFF6C63FF),
                              child: item.isGroup
                                  ? const Icon(Icons.group, color: Colors.green, size: 20)
                                  : Text(item.title[0].toUpperCase(), style: const TextStyle(color: Colors.white)),
                            ),
                            title: Row(children: [
                              Flexible(child: Text(item.title, overflow: TextOverflow.ellipsis)),
                              if (item.isGroup) const SizedBox(width: 4),
                              if (item.isGroup) const Icon(Icons.group, size: 12, color: Colors.grey),
                            ]),
                            subtitle: Text(
                              item.preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Colors.grey[600], fontSize: 13),
                            ),
                            trailing: unreadCount > 0
                                ? Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
                                    child: Text(unreadCount > 99 ? '99+' : '$unreadCount',
                                        style: const TextStyle(color: Colors.white, fontSize: 12)),
                                  )
                                : null,
                            onTap: () {
                              // My Agent 特殊处理
                              if (item.group?.id == 0 && item.group?.name == 'My Agent') {
                                Navigator.push(context, MaterialPageRoute(
                                  builder: (_) => const AgentChatScreen(),
                                ));
                              } else if (item.isGroup) {
                                Navigator.push(context, MaterialPageRoute(
                                  builder: (_) => GroupChatScreen(group: item.group!),
                                ));
                              } else {
                                provider.selectContact(item.contact!);
                                Navigator.push(context, MaterialPageRoute(
                                  builder: (_) => ChatDetailScreen(key: ValueKey('msg_${item.id}')),
                                ));
                              }
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
    );
  }
}
