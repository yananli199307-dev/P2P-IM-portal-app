import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/message.dart';

class LocalDb {
  static final LocalDb _instance = LocalDb._();
  factory LocalDb() => _instance;
  LocalDb._();

  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _init();
    return _db!;
  }

  Future<Database> _init() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'p2p_cache.db');
    return openDatabase(path, version: 1, onCreate: (db, v) async {
      await db.execute('''
        CREATE TABLE messages (
          id INTEGER NOT NULL,
          contact_id INTEGER,
          group_id INTEGER,
          content TEXT,
          message_type TEXT DEFAULT 'text',
          file_url TEXT,
          file_name TEXT,
          file_size INTEGER,
          is_from_me INTEGER DEFAULT 0,
          is_read INTEGER DEFAULT 1,
          reply_to_message_id INTEGER,
          reply_to_content TEXT,
          reply_to_sender_name TEXT,
          created_at TEXT NOT NULL,
          is_deleted INTEGER DEFAULT 0,
          PRIMARY KEY (id, contact_id, group_id)
        )
      ''');
      await db.execute('CREATE INDEX idx_local_msg_contact ON messages(contact_id, created_at ASC)');
      await db.execute('CREATE INDEX idx_local_msg_group ON messages(group_id, created_at ASC)');
    });
  }

  /// 插入或更新消息
  Future<void> upsertMessages(List<Message> msgs) async {
    if (msgs.isEmpty) return;
    final d = await db;
    final batch = d.batch();
    for (final m in msgs) {
      batch.insert('messages', _msgToRow(m), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> upsertMessage(Message m) => upsertMessages([m]);

  /// 群聊消息：按原始 JSON 存储
  Future<void> upsertGroupMessages(List<Map<String, dynamic>> rawMsgs) async {
    if (rawMsgs.isEmpty) return;
    final d = await db;
    final batch = d.batch();
    for (final r in rawMsgs) {
      final id = r['id'] as int? ?? 0;
      final gid = r['group_id'] as int? ?? 0;
      batch.insert('messages', {
        'id': id,
        'group_id': gid,
        'content': r['content'] as String? ?? '',
        'message_type': r['message_type'] as String? ?? 'text',
        'file_url': r['file_url'] as String?,
        'file_name': r['file_name'] as String?,
        'file_size': r['file_size'] as int?,
        'is_from_me': (r['is_from_owner'] as bool?) == true ? 1 : 0,
        'created_at': r['created_at'] as String? ?? DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// 读取群聊消息（旧→新）
  Future<List<Map<String, dynamic>>> getCachedGroupMessages(int groupId, {int limit = 200}) async {
    final d = await db;
    final rows = await d.query('messages',
      where: 'group_id = ? AND is_deleted = 0',
      whereArgs: [groupId],
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows.map((r) => {
      'id': r['id'] as int,
      'group_id': r['group_id'] as int?,
      'content': r['content'] as String? ?? '',
      'message_type': r['message_type'] as String? ?? 'text',
      'file_url': r['file_url'] as String?,
      'file_name': r['file_name'] as String?,
      'file_size': r['file_size'] as int?,
      'is_from_owner': (r['is_from_me'] as int?) == 1,
      'created_at': r['created_at'] as String? ?? '',
    }).toList();
  }

  /// 读取联系人消息（旧→新）
  Future<List<Message>> getContactMessages(int contactId, {int limit = 200}) async {
    final d = await db;
    final rows = await d.query('messages',
      where: 'contact_id = ? AND is_deleted = 0',
      whereArgs: [contactId],
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows.map(_rowToMsg).toList();
  }

  /// 读取群消息
  Future<List<Message>> getGroupMessages(int groupId, {int limit = 200}) async {
    final d = await db;
    final rows = await d.query('messages',
      where: 'group_id = ? AND is_deleted = 0',
      whereArgs: [groupId],
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows.map(_rowToMsg).toList();
  }

  /// 软删除
  Future<void> softDelete(int msgId, int? contactId, int? groupId) async {
    final d = await db;
    await d.update('messages', {'is_deleted': 1},
      where: 'id = ? AND contact_id = ?',
      whereArgs: [msgId, contactId ?? 0]);
  }

  /// 清除一个会话的所有缓存
  Future<void> clearContact(int contactId) async {
    final d = await db;
    await d.delete('messages', where: 'contact_id = ?', whereArgs: [contactId]);
  }

  Map<String, dynamic> _msgToRow(Message m) => {
    'id': m.id,
    'contact_id': m.contactId,
    'group_id': m.groupId,
    'content': m.content,
    'message_type': m.messageType,
    'file_url': m.fileUrl,
    'file_name': m.fileName,
    'file_size': m.fileSize,
    'is_from_me': m.isFromMe ? 1 : 0,
    'is_read': m.isRead ? 1 : 0,
    'reply_to_message_id': m.replyToMessageId,
    'reply_to_content': m.replyToContent,
    'reply_to_sender_name': m.replyToSenderName,
    'created_at': m.createdAt.toIso8601String(),
    'is_deleted': 0,
  };

  Message _rowToMsg(Map<String, dynamic> r) => Message(
    id: r['id'] as int,
    contactId: r['contact_id'] as int?,
    groupId: r['group_id'] as int?,
    content: r['content'] as String? ?? '',
    type: _parseType(r['message_type'] as String?),
    fileUrl: r['file_url'] as String?,
    fileName: r['file_name'] as String?,
    fileSize: r['file_size'] as int?,
    isFromMe: (r['is_from_me'] as int?) == 1,
    isRead: (r['is_read'] as int?) != 0,
    replyToMessageId: r['reply_to_message_id'] as int?,
    replyToContent: r['reply_to_content'] as String?,
    replyToSenderName: r['reply_to_sender_name'] as String?,
    createdAt: DateTime.parse(r['created_at'] as String),
  );

  MessageType _parseType(String? t) {
    switch (t) {
      case 'file': return MessageType.file;
      case 'image': return MessageType.image;
      default: return MessageType.text;
    }
  }
}
