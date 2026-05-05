import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/update_service.dart';
import '../widgets/update_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;

  void _showChangePasswordDialog() {
    final oldPw = TextEditingController();
    final newPw = TextEditingController();
    final confirmPw = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改密码'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: oldPw,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '当前密码',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v == null || v.isEmpty ? '请输入当前密码' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: newPw,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '新密码',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return '请输入新密码';
                  if (v.length < 6) return '密码至少 6 位';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: confirmPw,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '确认新密码',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v != newPw.text) return '两次输入不一致';
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6C63FF)),
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              try {
                await context.read<AuthProvider>().changePassword(oldPw.text, newPw.text);
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('密码修改成功')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('修改失败: $e')),
                  );
                }
              }
            },
            child: const Text('确认修改'),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认退出'),
        content: const Text('确定要退出登录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<AuthProvider>().logout();
            },
            child: const Text('退出', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(children: [
          // 账户
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('账户', style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
          ),

          // 修改密码
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: const Icon(Icons.lock_outline, color: Color(0xFF6C63FF)),
              title: const Text('修改密码'),
              subtitle: const Text('定期更换密码可以提高安全性', style: TextStyle(fontSize: 12, color: Colors.grey)),
              trailing: TextButton(
                onPressed: _showChangePasswordDialog,
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFFF0EFFF),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                ),
                child: const Text('修改', style: TextStyle(fontSize: 13, color: Color(0xFF6C63FF))),
              ),
            ),
          ),

          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text('通用', style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
          ),

          // 消息通知
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: SwitchListTile(
              secondary: const Icon(Icons.notifications_outlined, color: Color(0xFF6C63FF)),
              title: const Text('消息通知'),
              value: _notificationsEnabled,
              activeColor: const Color(0xFF6C63FF),
              onChanged: (val) => setState(() => _notificationsEnabled = val),
            ),
          ),

          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text('其他', style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
          ),

          // 关于
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: const Icon(Icons.info_outline, color: Color(0xFF6C63FF)),
              title: const Text('关于'),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () {
                showAboutDialog(
                  context: context,
                  applicationName: 'Agent Portal P2P',
                  applicationVersion: '1.0.0',
                  applicationLegalese: '去中心化 P2P 安全通讯应用',
                );
              },
            ),
          ),

          const SizedBox(height: 24),

          // 退出登录
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: const Icon(Icons.system_update, color: Colors.blue),
              title: const Text('检查更新'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _checkUpdate(context),
            ),
          ),

          const SizedBox(height: 12),

          // 退出登录
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('退出登录', style: TextStyle(color: Colors.red)),
              onTap: () => _showLogoutDialog(context),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _checkUpdate(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final info = await UpdateService().checkUpdate();
    if (!context.mounted) return;
    Navigator.pop(context);
    if (info == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('检查失败,请稍后重试')),
      );
      return;
    }
    if (!info.hasUpdate) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已是最新版本 v${info.currentVersion}')),
      );
      return;
    }
    await UpdateDialog.show(context, info);
  }
}
