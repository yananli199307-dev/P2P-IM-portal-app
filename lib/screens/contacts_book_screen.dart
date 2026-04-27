import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../providers/chat_provider.dart';
import "../providers/auth_provider.dart";
import '../models/contact.dart';
import '../models/group.dart';
import 'chat_detail_screen.dart';
import 'contact_detail_screen.dart';
import 'group_chat_screen.dart';
import 'agent_chat_screen.dart';

class ContactsBookScreen extends StatefulWidget {
  const ContactsBookScreen({super.key});

  @override
  State<ContactsBookScreen> createState() => _ContactsBookScreenState();
}

class _ContactsBookScreenState extends State<ContactsBookScreen> {
  List<Group> _groups = [];
  List<Map<String, dynamic>> _requests = [];  // 合并的联系人请求+群邀请
  bool _isLoading = true;
  bool _groupsExpanded = false;
  bool _requestsExpanded = true;  // 有请求时默认展开

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
      // 并行加载群组和请求
      final results = await Future.wait([
        ApiService().getGroups(),
        _loadRequests(),
      ]);
      if (!mounted) return;
      setState(() {
        _groups = (results[0] as List).map((g) => Group.fromJson(g, ownerPortal: context.read<AuthProvider>().portalUrl)).toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('加载通讯录失败: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _loadRequests() async {
    final merged = <Map<String, dynamic>>[];
    // 加载联系人请求
    try {
      final contactReqs = await ApiService().getReceivedRequests();
      for (final r in contactReqs) {
        merged.add({...r, 'type': 'contact'});
      }
    } catch (e) {
      debugPrint('加载联系人请求失败: $e');
    }
    // 加载群邀请
    try {
      final groupInvites = await ApiService().getGroupInvites();
      for (final i in groupInvites) {
        merged.add({...i, 'type': 'group'});
      }
    } catch (e) {
      debugPrint('加载群邀请失败: $e');
    }
    setState(() {
      _requests = merged;
      if (merged.isNotEmpty) _requestsExpanded = true;
    });
    return []; // Future.wait 兼容
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

  Future<void> _approveRequest(int requestId) async {
    try {
      await ApiService().approveRequest(requestId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已添加为联系人')),
      );
      _loadData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('操作失败: $e')));
    }
  }

  Future<void> _rejectRequest(int requestId) async {
    try {
      await ApiService().rejectRequest(requestId);
      _loadData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('操作失败: $e')));
    }
  }

  Future<void> _acceptGroupInvite(int inviteId) async {
    try {
      await ApiService().acceptGroupInvite(inviteId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已加入群聊')),
      );
      _loadData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('操作失败: $e')));
    }
  }

  Future<void> _rejectGroupInvite(int inviteId) async {
    try {
      await ApiService().rejectGroupInvite(inviteId);
      _loadData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('操作失败: $e')));
    }
  }

  Widget _buildRequestItem(Map<String, dynamic> req) {
    final isGroup = req['type'] == 'group';
    final id = req['id'];
    final name = isGroup
        ? '群邀请: ${req['group_name'] ?? '未知群'}'
        : (req['requester_name'] ?? '未知');
    final subtitle = isGroup
        ? '来自: ${req['inviter_portal'] ?? ''}'
        : (req['requester_portal'] ?? '');
    final extra = isGroup ? null : req['message'];
    final avatarChar = isGroup ? '群' : (name.isNotEmpty ? name[0].toUpperCase() : '?');
    final avatarColor = isGroup ? Colors.green[100] : Colors.purple[50];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: avatarColor,
          child: Text(avatarChar, style: TextStyle(fontSize: 16, color: isGroup ? Colors.green[700] : Colors.purple[700], fontWeight: FontWeight.bold)),
        ),
        title: Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            if (extra != null && extra.toString().isNotEmpty)
              Text(extra.toString(), style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            isGroup
                ? TextButton(
                    onPressed: () => _rejectGroupInvite(id),
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: Size.zero),
                    child: const Text('拒绝', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  )
                : TextButton(
                    onPressed: () => _rejectRequest(id),
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: Size.zero),
                    child: const Text('拒绝', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
            isGroup
                ? TextButton(
                    onPressed: () => _acceptGroupInvite(id),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      backgroundColor: const Color(0xFF6C63FF),
                    ),
                    child: const Text('接受', style: TextStyle(fontSize: 12, color: Colors.white)),
                  )
                : TextButton(
                    onPressed: () => _approveRequest(id),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      backgroundColor: const Color(0xFF6C63FF),
                    ),
                    child: const Text('批准', style: TextStyle(fontSize: 12, color: Colors.white)),
                  ),
          ],
        ),
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
                  // ===== 新的请求区域（参照 Web 前端） =====
                  if (_requests.isNotEmpty || true) ...[
                    InkWell(
                      onTap: () => setState(() => _requestsExpanded = !_requestsExpanded),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Row(
                          children: [
                            AnimatedRotation(
                              turns: _requestsExpanded ? 0.25 : 0,
                              duration: const Duration(milliseconds: 200),
                              child: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.red),
                            ),
                            const SizedBox(width: 4),
                            const Text('新的请求', style: TextStyle(fontSize: 13, color: Colors.red, fontWeight: FontWeight.w500)),
                            const Spacer(),
                            if (_requests.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
                                child: Text('${_requests.length}', style: const TextStyle(fontSize: 11, color: Colors.white)),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (_requestsExpanded) ...[
                      if (_requests.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: Text('暂无新的请求', style: TextStyle(color: Colors.grey, fontSize: 13))),
                        )
                      else
                        ..._requests.map((req) => _buildRequestItem(req)),
                      const Divider(height: 1),
                    ],
                  ],

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
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => ContactDetailScreen(contact: contact),
                          )).then((_) => _loadData()); // 返回后刷新
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
