import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/contact.dart';
import '../providers/chat_provider.dart';
import '../services/api_service.dart';
import 'chat_detail_screen.dart';

class ContactDetailScreen extends StatefulWidget {
  final Contact contact;

  const ContactDetailScreen({super.key, required this.contact});

  @override
  State<ContactDetailScreen> createState() => _ContactDetailScreenState();
}

class _ContactDetailScreenState extends State<ContactDetailScreen> {
  late String _displayName;
  bool _isFavorite = false;
  String _note = '';
  bool _isEditing = false;
  final _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _displayName = widget.contact.displayName;
    _note = widget.contact.note ?? '';
    _isFavorite = widget.contact.isFavorite;
    _noteController.text = _note;
  }

  void _toggleFavorite() async {
    try {
      await ApiService().updateContact(widget.contact.id, isFavorite: !_isFavorite);
      setState(() => _isFavorite = !_isFavorite);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('操作失败: $e')));
    }
  }

  void _saveNote() async {
    try {
      await ApiService().updateContact(widget.contact.id, note: _noteController.text);
      setState(() {
        _note = _noteController.text;
        _isEditing = false;
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('备注已保存')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败: $e')));
    }
  }

  void _deleteContact() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除联系人'),
        content: Text('确定要删除 ${_displayName} 吗？此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              try {
                await ApiService().deleteContact(widget.contact.id);
                Navigator.pop(ctx);
                Navigator.pop(context);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('联系人已删除')));
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败: $e')));
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _startChat() {
    context.read<ChatProvider>().selectContact(widget.contact);
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ChatDetailScreen(key: ValueKey('msg_${widget.contact.id}')),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('联系人详情'), actions: [
        IconButton(icon: Icon(_isFavorite ? Icons.star : Icons.star_border, color: _isFavorite ? Colors.amber : null), onPressed: _toggleFavorite),
      ]),
      body: ListView(
        children: [
          const SizedBox(height: 32),
          // 头像
          Center(
            child: CircleAvatar(
              radius: 48,
              backgroundColor: const Color(0xFF6C63FF),
              child: Text(_displayName[0].toUpperCase(), style: const TextStyle(fontSize: 36, color: Colors.white)),
            ),
          ),
          const SizedBox(height: 16),
          // 昵称
          Center(child: Text(_displayName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
          const SizedBox(height: 4),
          // Portal URL
          Center(child: Text(widget.contact.portalUrl, style: TextStyle(fontSize: 13, color: Colors.grey[500]))),
          const SizedBox(height: 32),

          // 操作按钮
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _buildActionButton(Icons.chat_bubble_outline, '发消息', _startChat),
            ]),
          ),
          const SizedBox(height: 24),

          // 备注
          _buildInfoTile('备注', _note.isNotEmpty ? _note : '未设置', Icons.edit, () {
            setState(() {
              _isEditing = true;
              _noteController.text = _note;
            });
          }),
          const Divider(indent: 56),

          // 备注编辑
          if (_isEditing)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 8),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _noteController,
                    autofocus: true,
                    decoration: const InputDecoration(hintText: '输入备注名', border: OutlineInputBorder(), isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(onPressed: _saveNote, child: const Text('保存')),
                TextButton(onPressed: () => setState(() => _isEditing = false), child: const Text('取消')),
              ]),
            ),

          // 删除
          const SizedBox(height: 24),
          _buildInfoTile('删除联系人', '', Icons.delete_outline, _deleteContact, isDanger: true),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(color: const Color(0xFFF0EFFF), borderRadius: BorderRadius.circular(16)),
          child: Icon(icon, color: const Color(0xFF6C63FF)),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF6C63FF))),
      ]),
    );
  }

  Widget _buildInfoTile(String label, String value, IconData icon, VoidCallback onTap, {bool isDanger = false}) {
    return ListTile(
      leading: Icon(icon, color: isDanger ? Colors.red : Colors.grey),
      title: Text(label),
      subtitle: value.isNotEmpty ? Text(value, style: TextStyle(fontSize: 13, color: Colors.grey[600])) : null,
      trailing: isDanger ? null : const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }
}
