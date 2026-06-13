class UserModel {
  final String id;
  final String name;
  final String email;
  final String role; // 'admin' | 'broadcaster'
  final bool active;
  final DateTime createdAt;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.active,
    required this.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      role: json['role'] as String? ?? 'broadcaster',
      active: json['active'] as bool? ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'role': role,
      'active': active,
      'created_at': createdAt.toIso8601String(),
    };
  }

  bool get isAdmin => role == 'admin';
  bool get isBroadcaster => role == 'broadcaster';
}
