import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'settings_screen.dart';

class MeScreen extends StatelessWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    return Scaffold(
      appBar: AppBar(title: const Text('我')),
      body: ListView(children: [
        // 头像 + 名称
        const SizedBox(height: 24),
        Center(
          child: CircleAvatar(radius: 48, backgroundColor: const Color(0xFF6C63FF),
            child: Text((user?.displayName ?? '?')[0].toUpperCase(), style: const TextStyle(fontSize: 36, color: Colors.white)),
          ),
        ),
        const SizedBox(height: 12),
        Center(child: Text(user?.displayName ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
        Center(child: Text(user?.portalUrl ?? '', style: TextStyle(fontSize: 13, color: Colors.grey[500]))),
        const SizedBox(height: 32),

        // 功能菜单
        Card(margin: const EdgeInsets.symmetric(horizontal: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            _buildItem(Icons.settings, '设置', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
            const Divider(height: 1, indent: 48),
            _buildItem(Icons.favorite_border, '收藏', () {}),
          ]),
        ),
        const SizedBox(height: 16),
      ]),
    );
  }

  Widget _buildItem(IconData icon, String title, VoidCallback onTap, {bool isRed = false}) {
    return ListTile(leading: Icon(icon, color: isRed ? Colors.red : const Color(0xFF6C63FF)), title: Text(title, style: TextStyle(color: isRed ? Colors.red : null)), trailing: const Icon(Icons.chevron_right, color: Colors.grey), onTap: onTap);
  }
}
