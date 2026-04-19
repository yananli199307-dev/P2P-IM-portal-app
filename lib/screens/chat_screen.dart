import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import 'chat_detail_screen.dart';

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('消息'),
        actions: [
          // 连接状态指示器
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
      body: chatProvider.contacts.isEmpty
          ? const Center(
              child: Text(
                '暂无消息\n先去添加联系人吧',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            )
          : ListView.builder(
              itemCount: chatProvider.contacts.length,
              itemBuilder: (context, index) {
                final contact = chatProvider.contacts[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF6C63FF),
                    child: Text(
                      contact.displayName[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  title: Text(contact.displayName),
                  subtitle: const Text('点击开始聊天'),
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
    );
  }
}
