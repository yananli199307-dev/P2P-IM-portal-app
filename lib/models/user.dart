class User {
  final int id;
  final String portalUrl;  // Portal URL 作为身份标识
  final String? displayName;
  final String? avatar;
  final bool isActive;
  final bool isInitialized;
  final DateTime createdAt;

  User({
    required this.id,
    required this.portalUrl,
    this.displayName,
    this.avatar,
    required this.isActive,
    required this.isInitialized,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      portalUrl: json['portal_url'],
      displayName: json['display_name'],
      avatar: json['avatar'],
      isActive: json['is_active'] ?? true,
      isInitialized: json['is_initialized'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'portal_url': portalUrl,
      'display_name': displayName,
      'avatar': avatar,
      'is_active': isActive,
      'is_initialized': isInitialized,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
