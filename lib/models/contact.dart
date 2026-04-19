class Contact {
  final int id;
  final String displayName;
  final String portalUrl;
  final String? avatar;
  final bool isActive;
  final DateTime createdAt;

  Contact({
    required this.id,
    required this.displayName,
    required this.portalUrl,
    this.avatar,
    required this.isActive,
    required this.createdAt,
  });

  factory Contact.fromJson(Map<String, dynamic> json) {
    return Contact(
      id: json['id'],
      displayName: json['display_name'],
      portalUrl: json['portal_url'],
      avatar: json['avatar'],
      isActive: json['is_active'] ?? true,
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'display_name': displayName,
      'portal_url': portalUrl,
      'avatar': avatar,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
