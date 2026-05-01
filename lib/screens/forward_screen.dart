import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../services/api_service.dart';

class ForwardScreen extends StatelessWidget {
  final String content;

  const ForwardScreen({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    final contacts = context.watch<ChatProvider>().contacts;

    return Scaffold(
      appBar: AppBar(title: const Text('转发给...')),
      body: contacts.isEmpty
          ? const Center(child: Text('暂无联系人'))
          : ListView.builder(
              itemCount: contacts.length,
              itemBuilder: (_, i) {
                final c = contacts[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF6C63FF),
                    child: Text(c.displayName[0].toUpperCase(), style: const TextStyle(color: Colors.white)),
                  ),
                  title: Text(c.displayName),
                  onTap: () async {
                    try {
                      await ApiService().sendMessage(c.id, '🔄 $content');
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已转发')));
                      }
                    } catch (e) {
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('转发失败: $e')));
                    }
                  },
                );
              },
            ),
    );
  }
}
