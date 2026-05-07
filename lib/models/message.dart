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
  final String? msgUuid;  // 客户端消息UUID，用于去重
  final int? replyToMessageId;  // 被回复的消息 ID
  final String? replyToContent;  // 被回复的消息内容摘要
  final String? replyToSenderName;  // 被回复者名称
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
    this.msgUuid,
    this.replyToMessageId,
    this.replyToContent,
    this.replyToSenderName,
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
      msgUuid: json['msg_uuid'],
      isRead: json['is_read'] ?? false,
      replyToMessageId: json['reply_to_message_id'],
      replyToContent: json['reply_to_content'],
      replyToSenderName: json['reply_to_sender_name'],
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
