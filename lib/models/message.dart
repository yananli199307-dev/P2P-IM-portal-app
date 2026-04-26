enum MessageType { text, file, image }

class Message {
  final int id;
  final int? contactId;
  final int? groupId;
  final String content;
  final MessageType type;
  
  String get messageType {
    switch (type) {
      case MessageType.file:
        return 'file';
      case MessageType.image:
        return 'image';
      default:
        return 'text';
    }
  }
  final String? fileUrl;
  final String? fileName;
  final int? fileSize;
  final bool isFromMe;
  final bool isRead;
  final DateTime createdAt;

  Message({
    required this.id,
    this.contactId,
    this.groupId,
    required this.content,
    this.type = MessageType.text,
    this.fileUrl,
    this.fileName,
    this.fileSize,
    required this.isFromMe,
    this.isRead = false,
    required this.createdAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'],
      contactId: json['contact_id'],
      groupId: json['group_id'],
      content: json['content'],
      type: _parseMessageType(json['message_type']),
      fileUrl: json['file_url'],
      fileName: json['file_name'],
      fileSize: json['file_size'],
      isFromMe: json['is_from_owner'] ?? false,
      isRead: json['is_read'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  static MessageType _parseMessageType(String? type) {
    switch (type) {
      case 'file':
        return MessageType.file;
      case 'image':
        return MessageType.image;
      case 'text':
      default:
        return MessageType.text;
    }
  }
}
