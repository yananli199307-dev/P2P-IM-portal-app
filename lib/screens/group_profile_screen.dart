import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/group.dart';
import '../providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'invite_member_screen.dart';
import 'group_members_screen.dart';
import 'group_profile_screen.dart';

class GroupProfileScreen extends StatefulWidget {
  final Group group;
  const GroupProfileScreen({super.key, required this.group});

  @override
  State<GroupProfileScreen> createState() => _GroupProfileScreenState();
}

class _GroupProfileScreenState extends State<GroupProfileScreen> {
  late String _groupName;
  String _announcement = ''; // TODO: 后端支持后启用
  bool _muteNotifications = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _groupName = widget.group.name;
  }

  void _rename() async {
    final ctrl = TextEditingController(text: _groupName);
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('修改群名'), content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: '新群名'), autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
      ],
    ));
    if (ok == true) {
      try {
        await ApiService().updateGroupName(widget.group.id, ctrl.text);
        setState(() => _groupName = ctrl.text);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('修改失败: $e')));
      }
    }
  }

  void _editAnnouncement() async {
    final ctrl = TextEditingController(text: _announcement);
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('群公告'), content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: '公告内容'), maxLines: 3),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
      ],
    ));
    if (ok == true) {
      setState(() => _announcement = ctrl.text);
      // TODO: 等后端支持后调用 API 保存
    }
  }

  void _dissolve() async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('解散群组'), content: const Text('确定要解散这个群组吗？此操作不可恢复。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('解散')),
      ],
    ));
    if (ok == true) {
      try {
        await ApiService().dissolveGroup(widget.group.id);
        if (mounted) { Navigator.pop(context); Navigator.pop(context); }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('解散失败: $e')));
      }
    }
  }

  void _leave() async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('退出群组'), content: const Text('确定要退出这个群组吗？'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('退出')),
      ],
    ));
    if (ok == true) {
      try {
        await ApiService().leaveGroup(widget.group.id);
        if (mounted) { Navigator.pop(context); Navigator.pop(context); }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('退出失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isOwner = widget.group.isOwner;

    return Scaffold(
      appBar: AppBar(title: const Text('群资料')),
      body: ListView(
        children: [
          // 群头像 + 群名
          const SizedBox(height: 24),
          Center(
            child: CircleAvatar(
              radius: 40,
              backgroundColor: Colors.green[100],
              child: const Icon(Icons.group, size: 40, color: Colors.green),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(_groupName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text('${widget.group.memberCount} 名成员', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
          ),

          const SizedBox(height: 24),
          const Divider(),

          // 群公告
          ListTile(
            leading: const Icon(Icons.campaign, color: Colors.orange),
            title: Text(_announcement.isEmpty ? '暂无群公告' : _announcement, 
                       style: TextStyle(color: _announcement.isEmpty ? Colors.grey : null)),
            subtitle: _announcement.isNotEmpty ? const Text('群公告', style: TextStyle(fontSize: 12)) : null,
            trailing: isOwner ? const Icon(Icons.edit, size: 18) : null,
            onTap: isOwner ? _editAnnouncement : null,
          ),
          const Divider(),

          // 群成员
          ListTile(
            leading: const Icon(Icons.people, color: Color(0xFF6C63FF)),
            title: const Text('群成员'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GroupMembersScreen(group: widget.group))),
          ),
          // 邀请成员
          if (isOwner)
            ListTile(
              leading: const Icon(Icons.person_add, color: Colors.blue),
              title: const Text('邀请成员'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => InviteMemberScreen(groupId: widget.group.id))),
            ),
          const Divider(),

          // 消息免打扰
          SwitchListTile(
            secondary: const Icon(Icons.notifications_off, color: Colors.grey),
            title: const Text('消息免打扰'),
            value: _muteNotifications,
            onChanged: (v) => setState(() => _muteNotifications = v),
          ),
          const Divider(),

          // 修改群名（群主）
          if (isOwner)
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.blueGrey),
              title: const Text('修改群名'),
              onTap: _rename,
            ),

          // 解散/退出
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: isOwner ? _dissolve : _leave,
                icon: Icon(isOwner ? Icons.delete : Icons.exit_to_app, color: Colors.red),
                label: Text(isOwner ? '解散群组' : '退出群组', style: const TextStyle(color: Colors.red)),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
