class UserModel {
  final String id;
  final String name;
  final String email;
  final String role; // 'admin' | 'broadcaster'
  final bool active;
  final DateTime createdAt;
  final DateTime? accessStart;
  final DateTime? accessEnd;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.active,
    required this.createdAt,
    this.accessStart,
    this.accessEnd,
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
      accessStart: json['access_start'] != null
          ? DateTime.parse(json['access_start'] as String).toLocal()
          : null,
      accessEnd: json['access_end'] != null
          ? DateTime.parse(json['access_end'] as String).toLocal()
          : null,
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
      'access_start': accessStart?.toUtc().toIso8601String(),
      'access_end': accessEnd?.toUtc().toIso8601String(),
    };
  }

  bool get isAdmin => role == 'admin';
  bool get isBroadcaster => role == 'broadcaster';

  bool get isAccessValid {
    if (!active) return false;
    if (isAdmin) return true;
    final now = DateTime.now();
    if (accessStart != null && accessStart!.isAfter(now)) return false;
    if (accessEnd != null && accessEnd!.isBefore(now)) return false;
    return true;
  }
}
