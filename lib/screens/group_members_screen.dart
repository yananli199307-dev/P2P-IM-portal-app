import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/group.dart';

class GroupMember {
  final String portalUrl;
  final String displayName;
  final bool isOwner;

  GroupMember({
    required this.portalUrl,
    required this.displayName,
    this.isOwner = false,
  });

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      portalUrl: json['portal'] ?? '',
      displayName: json['display_name'] ?? 'Unknown',
      isOwner: json['is_owner'] ?? false,
    );
  }
}

class GroupMembersScreen extends StatefulWidget {
  final Group group;

  const GroupMembersScreen({Key? key, required this.group}) : super(key: key);

  @override
  State<GroupMembersScreen> createState() => _GroupMembersScreenState();
}

class _GroupMembersScreenState extends State<GroupMembersScreen> {
  List<GroupMember> _members = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    try {
      final membersData = await ApiService().getGroupMembers(widget.group.id);
      setState(() {
        _members = membersData.map((m) => GroupMember.fromJson(m)).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载成员失败: $e')),
      );
    }
  }

  Future<void> _removeMember(String memberPortal) async {
    try {
      await ApiService().removeGroupMember(widget.group.id, memberPortal);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('成员已移除')),
      );
      _loadMembers();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('移除失败: $e')),
      );
    }
  }

  void _showRemoveConfirm(String memberPortal, String displayName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除成员'),
        content: Text('确定要移除 $displayName 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _removeMember(memberPortal);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('移除'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('群成员'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _members.length,
              itemBuilder: (context, index) {
                final member = _members[index];
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(member.displayName[0].toUpperCase()),
                  ),
                  title: Text(member.displayName),
                  subtitle: Text(member.portalUrl),
                  trailing: member.isOwner
                      ? const Chip(
                          label: Text('群主'),
                          backgroundColor: Colors.blue,
                          labelStyle: TextStyle(color: Colors.white),
                        )
                      : widget.group.isOwner
                          ? IconButton(
                              icon: const Icon(Icons.remove_circle, color: Colors.red),
                              onPressed: () => _showRemoveConfirm(
                                member.portalUrl,
                                member.displayName,
                              ),
                            )
                          : null,
                );
              },
            ),
    );
  }
}
