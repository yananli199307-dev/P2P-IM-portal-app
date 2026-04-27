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
      if (chatProvider.contacts.isEmpty) {
        await chatProvider.loadContacts();
      }
      final groupsData = await ApiService().getGroups();
      if (!mounted) return;
      setState(() {
        _groups = groupsData.map((g) => Group.fromJson(g)).toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final contacts = chatProvider.contacts;

    return Scaffold(
      appBar: AppBar(
        title: const Text('消息'),
        actions: [
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
          : contacts.isEmpty && _groups.isEmpty
              ? const Center(child: Text('暂无消息\n去通讯录添加联系人吧', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)))
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.builder(
                    itemCount: contacts.length + _groups.length,
                    itemBuilder: (context, index) {
                      if (index < contacts.length) {
                        final contact = contacts[index];
                        final unreadCount = chatProvider.unreadCounts[contact.id] ?? 0;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF6C63FF),
                            child: Text(contact.displayName[0].toUpperCase(), style: const TextStyle(color: Colors.white)),
                          ),
                          title: Text(contact.displayName),
                          subtitle: Text(unreadCount > 0 ? '$unreadCount 条未读' : '点击开始聊天'),
                          trailing: unreadCount > 0
                              ? Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
                                  child: Text(unreadCount > 99 ? '99+' : '$unreadCount',
                                      style: const TextStyle(color: Colors.white, fontSize: 12)),
                                )
                              : null,
                          onTap: () {
                            chatProvider.selectContact(contact);
                            Navigator.push(context, MaterialPageRoute(
                              builder: (_) => ChatDetailScreen(key: ValueKey('msg_${contact.id}')),
                            ));
                          },
                        );
                      } else {
                        final group = _groups[index - contacts.length];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.green[100],
                            child: const Icon(Icons.group, color: Colors.green, size: 20),
                          ),
                          title: Row(children: [
                            Flexible(child: Text(group.name, overflow: TextOverflow.ellipsis)),
                            const SizedBox(width: 4),
                            const Icon(Icons.group, size: 12, color: Colors.grey),
                          ]),
                          subtitle: const Text('群聊'),
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(
                              builder: (_) => GroupChatScreen(group: group),
                            ));
                          },
                        );
                      }
                    },
                  ),
                ),
    );
  }
}
