import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/contact.dart';

class InviteMemberScreen extends StatefulWidget {
  final int groupId;

  const InviteMemberScreen({Key? key, required this.groupId}) : super(key: key);

  @override
  State<InviteMemberScreen> createState() => _InviteMemberScreenState();
}

class _InviteMemberScreenState extends State<InviteMemberScreen> {
  List<Contact> _contacts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    try {
      final contacts = await ApiService().getContacts();
      setState(() {
        _contacts = contacts;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载联系人失败: $e')),
      );
    }
  }

  Future<void> _inviteContact(Contact contact) async {
    try {
      await ApiService().inviteToGroup(widget.groupId, contact.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已邀请 ${contact.displayName}')),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('邀请失败: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('邀请成员'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _contacts.isEmpty
              ? const Center(
                  child: Text(
                    '暂无联系人\n先添加联系人才能邀请',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  itemCount: _contacts.length,
                  itemBuilder: (context, index) {
                    final contact = _contacts[index];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(contact.displayName[0].toUpperCase()),
                      ),
                      title: Text(contact.displayName),
                      subtitle: Text(contact.portalUrl),
                      trailing: ElevatedButton(
                        onPressed: () => _inviteContact(contact),
                        child: const Text('邀请'),
                      ),
                    );
                  },
                ),
    );
  }
}
