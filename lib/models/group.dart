class Group {
  final int id;
  final String name;
  final String? description;
  final int ownerId;
  final List<int> memberIds;
  final int memberCount;
  final bool isOwner;
  final DateTime createdAt;
  final String? groupUuid;  // 用于成员获取消息
  final String? ownerName;  // 群主名称
  final String? ownerPortal;  // 群主 Portal URL（用于成员列表判断）

  Group({
    required this.id,
    required this.name,
    this.description,
    required this.ownerId,
    this.memberIds = const [],
    this.memberCount = 0,
    required this.isOwner,
    required this.createdAt,
    this.groupUuid,
    this.ownerName,
    this.ownerPortal,
  });

  factory Group.fromJson(Map<String, dynamic> json, {String? ownerPortal}) {
    final memberIds = List<int>.from(json['member_ids'] ?? []);
    final memberCount = json['member_count'] ?? memberIds.length;
    // 检测群主：API 不返回 is_owner，从 UUID 判断（含自己域名即为群主）
    final isOwner = json['is_owner'] ?? (json['group_id']?.contains('agentp2p') ?? false);
    return Group(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      ownerId: json['owner_id'],
      memberIds: memberIds,
      memberCount: memberCount,
      isOwner: isOwner,
      createdAt: DateTime.parse(json['created_at']),
      groupUuid: json['group_id'] ?? json['group_uuid'],
      ownerName: json['owner_name'],
      ownerPortal: json['owner_portal'] ?? ownerPortal,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'owner_id': ownerId,
      'member_count': memberCount,
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
