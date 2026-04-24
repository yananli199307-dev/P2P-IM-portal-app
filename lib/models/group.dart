class Group {
  final int id;
  final String name;
  final String? description;
  final int ownerId;
  final List<int> memberIds;
  final DateTime createdAt;
  final String? groupUuid;  // 用于成员获取消息
  final bool isOwner;  // 当前用户是否是群主

  Group({
    required this.id,
    required this.name,
    this.description,
    required this.ownerId,
    this.memberIds = const [],
    required this.createdAt,
    this.groupUuid,
    this.isOwner = false,
  });

  factory Group.fromJson(Map<String, dynamic> json) {
    return Group(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      ownerId: json['owner_id'],
      memberIds: List<int>.from(json['member_ids'] ?? []),
      createdAt: DateTime.parse(json['created_at']),
      groupUuid: json['group_id'],  // API 返回的是 group_id (UUID)
      isOwner: json['is_owner'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'owner_id': ownerId,
      'member_ids': memberIds,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class GroupMessage {
  final int id;
  final int groupId;
  final String senderName;
  final String? senderPortal;
  final String content;
  final String messageType;
  final DateTime createdAt;

  GroupMessage({
    required this.id,
    required this.groupId,
    required this.senderName,
    this.senderPortal,
    required this.content,
    this.messageType = 'text',
    required this.createdAt,
  });

  factory GroupMessage.fromJson(Map<String, dynamic> json) {
    return GroupMessage(
      id: json['id'],
      groupId: json['group_id'],
      senderName: json['sender_name'] ?? '未知',
      senderPortal: json['sender_portal'],
      content: json['content'],
      messageType: json['message_type'] ?? 'text',
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class GroupInvite {
  final int id;
  final int groupId;
  final String groupName;
  final String inviterPortal;
  final String status;
  final DateTime createdAt;

  GroupInvite({
    required this.id,
    required this.groupId,
    required this.groupName,
    required this.inviterPortal,
    this.status = 'pending',
    required this.createdAt,
  });

  factory GroupInvite.fromJson(Map<String, dynamic> json) {
    return GroupInvite(
      id: json['id'],
      groupId: json['group_id'],
      groupName: json['group_name'],
      inviterPortal: json['inviter_portal'],
      status: json['status'] ?? 'pending',
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}
