import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../services/api_service.dart';
import '../models/contact.dart';
import '../models/group.dart';
import 'add_contact_screen.dart';
import 'chat_detail_screen.dart';


// 导出供其他文件使用
export 'chat_detail_screen.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<GroupInvite> _groupInvites = [];


  @override
  void initState() {
    super.initState();
    _loadGroupInvites();
  }

  Future<void> _loadGroupInvites() async {
    setState(() {
      _isLoadingInvites = true;
    });
    try {
      final invites = await ApiService().getGroupInvites();
      setState(() {
        _groupInvites = invites.map((i) => GroupInvite.fromJson(i)).toList();
        _isLoadingInvites = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingInvites = false;
      });
    }
  }

  Future<void> _acceptInvite(GroupInvite invite) async {
    try {
      await ApiService().acceptGroupInvite(invite.id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已接受群邀请')),
      );
      _loadGroupInvites();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('接受失败: $e')),
      );
    }
  }

  Future<void> _rejectInvite(GroupInvite invite) async {
    try {
      await ApiService().rejectGroupInvite(invite.id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已拒绝群邀请')),
      );
      _loadGroupInvites();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('拒绝失败: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('联系人'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AddContactScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await chatProvider.loadContacts();
          await _loadGroupInvites();
        },
        child: Column(
          children: [
            // 群邀请列表
            if (_groupInvites.isNotEmpty)
              Container(
                color: Colors.blue[50],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        '群邀请 (${_groupInvites.length})',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ),
                    ..._groupInvites.map((invite) => ListTile(
                      leading: const CircleAvatar(
                        child: Text('群'),
                      ),
                      title: Text(invite.groupName),
                      subtitle: Text('来自: ${invite.inviterPortal}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () => _acceptInvite(invite),
                            child: const Text('接受'),
                          ),
                          TextButton(
                            onPressed: () => _rejectInvite(invite),
                            child: const Text('拒绝'),
                          ),
                        ],
                      ),
                    )),
                    const Divider(),
                  ],
                ),
              ),
            // 联系人列表
            Expanded(
              child: chatProvider.isLoading && chatProvider.contacts.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : chatProvider.contacts.isEmpty
                      ? const Center(
                          child: Text(
                            '暂无联系人\n点击右上角添加',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          itemCount: chatProvider.contacts.length,
                          itemBuilder: (context, index) {
                            final contact = chatProvider.contacts[index];
                            return ContactTile(
                              contact: contact,
                              onTap: () {
                                chatProvider.selectContact(contact);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const ChatDetailScreen(),
                                  ),
                                );
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class ContactTile extends StatelessWidget {
  final Contact contact;
  final VoidCallback onTap;

  const ContactTile({
    super.key,
    required this.contact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final unreadCount = chatProvider.unreadCounts[contact.id] ?? 0;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: const Color(0xFF6C63FF),
        child: Text(
          contact.displayName[0].toUpperCase(),
          style: const TextStyle(color: Colors.white),
        ),
      ),
      title: Text(contact.displayName),
      subtitle: Text(
        contact.portalUrl,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
      trailing: unreadCount > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                unreadCount > 99 ? '99+' : '$unreadCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
      onTap: onTap,
    );
  }
}
