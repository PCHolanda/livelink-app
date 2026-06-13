class LiveModel {
  final String id;
  final String title;
  final String slug;
  final String creatorId;
  final String status; // 'idle' | 'live' | 'ended'
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int maxViewers;
  final int currentViewers;
  final DateTime createdAt;

  LiveModel({
    required this.id,
    required this.title,
    required this.slug,
    required this.creatorId,
    required this.status,
    this.startedAt,
    this.endedAt,
    required this.maxViewers,
    required this.currentViewers,
    required this.createdAt,
  });

  factory LiveModel.fromJson(Map<String, dynamic> json) {
    return LiveModel(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      creatorId: json['creator_id'] as String? ?? '',
      status: json['status'] as String? ?? 'idle',
      startedAt: json['started_at'] != null
          ? DateTime.parse(json['started_at'] as String)
          : null,
      endedAt: json['ended_at'] != null
          ? DateTime.parse(json['ended_at'] as String)
          : null,
      maxViewers: json['max_viewers'] as int? ?? 0,
      currentViewers: json['current_viewers'] as int? ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'slug': slug,
      'creator_id': creatorId,
      'status': status,
      'started_at': startedAt?.toIso8601String(),
      'ended_at': endedAt?.toIso8601String(),
      'max_viewers': maxViewers,
      'current_viewers': currentViewers,
      'created_at': createdAt.toIso8601String(),
    };
  }

  bool get isIdle => status == 'idle';
  bool get isLive => status == 'live';
  bool get isEnded => status == 'ended';
}
