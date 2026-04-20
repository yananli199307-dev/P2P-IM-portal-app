import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../models/contact.dart';
import 'add_contact_screen.dart';
import 'chat_detail_screen.dart';

// 导出供其他文件使用
export 'chat_detail_screen.dart';

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

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
        onRefresh: () => chatProvider.loadContacts(),
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
