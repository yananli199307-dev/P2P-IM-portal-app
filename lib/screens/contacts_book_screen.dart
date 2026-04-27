import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../providers/chat_provider.dart';
import '../models/contact.dart';
import '../models/group.dart';
import 'chat_detail_screen.dart';
import 'group_chat_screen.dart';
import 'agent_chat_screen.dart';

class ContactsBookScreen extends StatefulWidget {
  const ContactsBookScreen({super.key});

  @override
  State<ContactsBookScreen> createState() => _ContactsBookScreenState();
}

class _ContactsBookScreenState extends State<ContactsBookScreen> {
  List<Group> _groups = [];
  bool _isLoading = true;
  bool _groupsExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final chatProvider = context.read<ChatProvider>();
      // 确保联系人已加载
      if (chatProvider.contacts.isEmpty) {
        await chatProvider.loadContacts();
      }
      // 加载群组
      final groupsData = await ApiService().getGroups();
      if (!mounted) return;
      setState(() {
        _groups = groupsData.map((g) => Group.fromJson(g)).toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('加载通讯录失败: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) _loadData();
      });
    }
  }

  void _showCreateGroupDialog() {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('创建群聊'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: '群聊名称', hintText: '输入群聊名称'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) return;
              try {
                await ApiService().createGroup(nameController.text.trim());
                Navigator.pop(ctx);
                _loadData();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('创建失败: $e')));
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  void _showAddContactDialog() {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加联系人'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: '昵称', hintText: '输入对方昵称'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(labelText: 'Portal 地址', hintText: 'https://...'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isEmpty || urlController.text.isEmpty) return;
              try {
                await ApiService().addContact(nameController.text.trim(), urlController.text.trim());
                Navigator.pop(ctx);
                _loadData();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('添加失败: $e')));
              }
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final contacts = chatProvider.contacts;

    return Scaffold(
      appBar: AppBar(
        title: const Text('通讯录'),
        actions: [
          IconButton(icon: const Icon(Icons.group_add), onPressed: _showCreateGroupDialog, tooltip: '创建群聊'),
          IconButton(icon: const Icon(Icons.person_add), onPressed: _showAddContactDialog, tooltip: '添加联系人'),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                children: [
                  // ===== 群聊区域（可折叠） =====
                  if (_groups.isNotEmpty || true) ...[
                    InkWell(
                      onTap: () => setState(() => _groupsExpanded = !_groupsExpanded),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Row(
                          children: [
                            AnimatedRotation(
                              turns: _groupsExpanded ? 0.25 : 0,
                              duration: const Duration(milliseconds: 200),
                              child: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                            ),
                            const SizedBox(width: 4),
                            const Text('群聊', style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
                            const Spacer(),
                            Text('${_groups.length} 个', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ),
                    if (_groupsExpanded && _groups.isNotEmpty) ...[
                      ..._groups.map((group) => ListTile(
                            leading: CircleAvatar(
                              backgroundColor: group.isOwner ? Colors.blue[100] : Colors.grey[200],
                              child: Text(group.isOwner ? '👑' : group.name[0].toUpperCase(), style: const TextStyle(fontSize: 16)),
                            ),
                            title: Row(
                              children: [
                                Flexible(child: Text(group.name, overflow: TextOverflow.ellipsis)),
                                if (group.isOwner)
                                  Container(
                                    margin: const EdgeInsets.only(left: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(3)),
                                    child: const Text('群主', style: TextStyle(fontSize: 10, color: Colors.orange)),
                                  ),
                              ],
                            ),
                            subtitle: Text('${group.memberCount} 个成员'),
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GroupChatScreen(group: group))),
                          )),
                      const Divider(height: 1),
                    ],
                    if (_groupsExpanded && _groups.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: Text('暂无群聊', style: TextStyle(color: Colors.grey, fontSize: 13))),
                      ),
                  ],

                  // ===== 联系人区域 =====
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: const Text('联系人', style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
                  ),
                  // My Agent 固定入口（参照 Web 前端）
                  ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFF6C63FF),
                      child: Text('🤖', style: TextStyle(fontSize: 20)),
                    ),
                    title: const Text('My Agent'),
                    subtitle: const Text('AI 助手', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AgentChatScreen())),
                  ),
                  if (contacts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('暂无联系人\n点击右上角 + 添加', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey))),
                    )
                  else
                    ...contacts.map((contact) {
                      final unreadCount = chatProvider.unreadCounts[contact.id] ?? 0;
                      return Dismissible(
                        key: ValueKey('del_${contact.id}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          color: Colors.red,
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        confirmDismiss: (_) => showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('删除联系人'),
                            content: Text('确定删除 ${contact.displayName} 吗？\n聊天记录将被清除。'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: Colors.red))),
                            ],
                          ),
                        ).then((confirmed) async {
                          if (confirmed == true) {
                            try {
                              await ApiService().deleteContact(contact.id);
                              chatProvider.removeContact(contact.id);
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已删除 ${contact.displayName}')));
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败: $e')));
                            }
                          }
                          return false;
                        }),
                        child: ListTile(
                        leading: CircleAvatar(child: Text((contact.displayName ?? contact.portalUrl ?? '?')[0].toUpperCase())),
                        title: Text(contact.displayName ?? contact.portalUrl ?? '未知'),
                        subtitle: Text(contact.portalUrl ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey), overflow: TextOverflow.ellipsis),
                        trailing: unreadCount > 0
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
                                child: Text(unreadCount > 99 ? '99+' : '$unreadCount', style: const TextStyle(color: Colors.white, fontSize: 12)),
                              )
                            : null,
                        onTap: () {
                          chatProvider.selectContact(contact);
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => ChatDetailScreen(key: ValueKey('book_${contact.id}')),
                          ));
                        },
                      ),
                    );
                    }),
                ],
              ),
            ),
    );
  }
}
