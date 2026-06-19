import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import '../models/user_model.dart';
import '../models/live_model.dart';

class SupabaseService extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;

  UserModel? _currentUser;
  UserModel? get currentUser => _currentUser;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  SupabaseService() {
    // Listen to auth state changes
    _client.auth.onAuthStateChange.listen((data) async {
      final session = data.session;
      if (session != null) {
        await _fetchCurrentUserInfo(session.user.id);
      } else {
        _currentUser = null;
        notifyListeners();
      }
    });
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  // ==========================================
  // AUTHENTICATION
  // ==========================================

  Future<void> signIn(String email, String password) async {
    _setLoading(true);
    try {
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (response.user != null) {
        await _fetchCurrentUserInfo(response.user!.id);
        if (_currentUser != null) {
          if (!_currentUser!.active) {
            await signOut();
            throw Exception('Esta conta está desativada pelo administrador.');
          }
          if (!_currentUser!.isAccessValid) {
            await signOut();
            throw Exception('Seu período de acesso à plataforma expirou ou ainda não iniciou.');
          }
        }
      }
    } finally {
      _setLoading(false);
    }
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
    _currentUser = null;
    notifyListeners();
  }

  Future<void> recoverPassword(String email) async {
    await _client.auth.resetPasswordForEmail(
      email,
      redirectTo: kIsWeb ? null : 'livelink://reset-password',
    );
  }

  Future<void> _fetchCurrentUserInfo(String userId) async {
    try {
      final data = await _client
          .from('users')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (data != null) {
        final parsedUser = UserModel.fromJson(data);
        if (!parsedUser.isAccessValid) {
          _currentUser = null;
          await signOut();
        } else {
          _currentUser = parsedUser;
        }
      } else {
        _currentUser = null;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching user info: $e');
    }
  }

  // ==========================================
  // LIVES MANAGEMENT (BROADCASTER & VIEWER)
  // ==========================================

  Future<LiveModel> createLive(String title) async {
    if (_currentUser == null) throw Exception('Não autenticado.');

    // Generate unique slug
    final cleanTitle = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-');
    final uniqueSuffix = DateTime.now().millisecondsSinceEpoch.toString().substring(8);
    final slug = '$cleanTitle-$uniqueSuffix';

    final response = await _client.from('lives').insert({
      'title': title,
      'slug': slug,
      'creator_id': _currentUser!.id,
      'status': 'idle',
      'current_viewers': 0,
      'max_viewers': 0,
    }).select().single();

    return LiveModel.fromJson(response);
  }

  Future<LiveModel?> getLiveBySlug(String slug) async {
    final response = await _client
        .from('lives')
        .select()
        .eq('slug', slug)
        .maybeSingle();
    if (response == null) return null;
    return LiveModel.fromJson(response);
  }

  Future<LiveModel> getLiveById(String id) async {
    final response = await _client
        .from('lives')
        .select()
        .eq('id', id)
        .single();
    return LiveModel.fromJson(response);
  }

  Future<void> startLive(String liveId) async {
    await _client.from('lives').update({
      'status': 'live',
      'started_at': DateTime.now().toIso8601String(),
    }).eq('id', liveId);
  }

  Future<void> endLive(String liveId) async {
    await _client.from('lives').update({
      'status': 'ended',
      'ended_at': DateTime.now().toIso8601String(),
    }).eq('id', liveId);
  }

  Stream<List<LiveModel>> streamLivesHistory() {
    if (_currentUser == null) return Stream.value([]);
    return _client
        .from('lives')
        .stream(primaryKey: ['id'])
        .eq('creator_id', _currentUser!.id)
        .order('created_at', ascending: false)
        .map((list) => list.map((json) => LiveModel.fromJson(json)).toList());
  }

  Stream<LiveModel> streamLive(String liveId) {
    return _client
        .from('lives')
        .stream(primaryKey: ['id'])
        .eq('id', liveId)
        .map((list) => LiveModel.fromJson(list.first));
  }

  // ==========================================
  // VIEWERS MANAGEMENT
  // ==========================================

  Future<String> fetchUserIpAddress() async {
    try {
      final response = await http.get(Uri.parse('https://api.ipify.org')).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        return response.body;
      }
    } catch (_) {}
    return 'unknown';
  }

  Future<String> joinLiveSession(String liveId) async {
    final ip = await fetchUserIpAddress();
    final data = await _client.from('viewers').insert({
      'live_id': liveId,
      'ip_address': ip,
      'joined_at': DateTime.now().toIso8601String(),
    }).select('id').single();

    return data['id'] as String;
  }

  Future<void> leaveLiveSession(String sessionId) async {
    await _client.from('viewers').update({
      'left_at': DateTime.now().toIso8601String(),
    }).eq('id', sessionId);
  }

  // ==========================================
  // LIVEKIT TOKEN GENERATION
  // ==========================================

  Future<Map<String, dynamic>> generateLiveKitToken({
    required String roomName,
    required String identity,
    required bool isPublisher,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'livekit-token',
        body: {
          'roomName': roomName,
          'identity': identity,
          'isPublisher': isPublisher,
        },
      );

      if (response.status != 200) {
        throw Exception(response.data['error'] ?? 'Falha ao buscar token LiveKit.');
      }

      final Map<String, dynamic> data = response.data;
      return {
        'token': data['token'] as String,
        'url': data['url'] as String,
      };
    } catch (e) {
      throw Exception('Erro ao gerar token: $e');
    }
  }

  // ==========================================
  // ADMIN PANEL - USER CRUD & METRICS (via Edge Functions)
  // ==========================================

  Future<List<UserModel>> getAllUsers() async {
    if (_currentUser == null || !_currentUser!.isAdmin) {
      throw Exception('Acesso negado: Administradores apenas.');
    }
    final response = await _client
        .from('users')
        .select()
        .order('created_at', ascending: false);

    return (response as List).map((json) => UserModel.fromJson(json)).toList();
  }

  Future<List<LiveModel>> getAllLives() async {
    if (_currentUser == null || !_currentUser!.isAdmin) {
      throw Exception('Acesso negado.');
    }
    final response = await _client
        .from('lives')
        .select()
        .order('created_at', ascending: false);

    return (response as List).map((json) => LiveModel.fromJson(json)).toList();
  }

  Future<List<LiveModel>> fetchLivesByUser(String userId) async {
    if (_currentUser == null || !_currentUser!.isAdmin) {
      throw Exception('Acesso negado.');
    }
    final response = await _client
        .from('lives')
        .select()
        .eq('creator_id', userId)
        .order('created_at', ascending: false);

    return (response as List).map((json) => LiveModel.fromJson(json)).toList();
  }

  Future<List<Map<String, dynamic>>> getAuditLogs() async {
    if (_currentUser == null || !_currentUser!.isAdmin) {
      throw Exception('Acesso negado.');
    }
    final response = await _client
        .from('audit_logs')
        .select('*, users(name)')
        .order('created_at', ascending: false)
        .limit(100);

    return (response as List).map((e) => e as Map<String, dynamic>).toList();
  }

  Future<void> adminCreateUser({
    required String email,
    required String password,
    required String name,
    required String role,
    DateTime? accessStart,
    DateTime? accessEnd,
  }) async {
    final response = await _client.functions.invoke(
      'manage-users',
      body: {
        'action': 'create',
        'payload': {
          'email': email,
          'password': password,
          'name': name,
          'role': role,
          'access_start': accessStart?.toUtc().toIso8601String(),
          'access_end': accessEnd?.toUtc().toIso8601String(),
        }
      },
    );

    if (response.status != 200) {
      throw Exception(response.data['error'] ?? 'Erro ao criar usuário');
    }
    notifyListeners();
  }

  Future<void> adminUpdateUser({
    required String id,
    required String email,
    required String name,
    required String role,
    required bool active,
    DateTime? accessStart,
    DateTime? accessEnd,
  }) async {
    final response = await _client.functions.invoke(
      'manage-users',
      body: {
        'action': 'update',
        'payload': {
          'id': id,
          'email': email,
          'name': name,
          'role': role,
          'active': active,
          'access_start': accessStart?.toUtc().toIso8601String(),
          'access_end': accessEnd?.toUtc().toIso8601String(),
        }
      },
    );

    if (response.status != 200) {
      throw Exception(response.data['error'] ?? 'Erro ao atualizar usuário');
    }
    notifyListeners();
  }

  Future<void> adminDeleteUser(String userId) async {
    final response = await _client.functions.invoke(
      'manage-users',
      body: {
        'action': 'delete',
        'payload': {
          'id': userId,
        }
      },
    );

    if (response.status != 200) {
      throw Exception(response.data['error'] ?? 'Erro ao deletar usuário');
    }
    notifyListeners();
  }

  Future<void> adminResetPassword({
    required String id,
    required String newPassword,
  }) async {
    final response = await _client.functions.invoke(
      'manage-users',
      body: {
        'action': 'reset-password',
        'payload': {
          'id': id,
          'newPassword': newPassword,
        }
      },
    );

    if (response.status != 200) {
      throw Exception(response.data['error'] ?? 'Erro ao resetar senha');
    }
  }

  // Aggregate stats logic for the dashboard
  Future<Map<String, dynamic>> fetchDashboardStats() async {
    if (_currentUser == null || !_currentUser!.isAdmin) {
      throw Exception('Acesso negado.');
    }

    // 1. Total users and active users
    final usersCountResponse = await _client
        .from('users')
        .select('role, active');
    
    final usersList = usersCountResponse as List;
    final totalUsers = usersList.length;
    final activeUsers = usersList.where((u) => u['active'] == true).length;

    // 2. Lives stats
    final livesResponse = await _client
        .from('lives')
        .select('status, started_at, ended_at, max_viewers, creator_id, users(name)');
    
    final livesList = livesResponse as List;
    final totalLives = livesList.length;
    final livesInProgress = livesList.where((l) => l['status'] == 'live').length;

    // 3. Viewers stats
    int totalViewers = 0;
    double totalHours = 0.0;
    
    for (var live in livesList) {
      totalViewers += (live['max_viewers'] as num? ?? 0).toInt();
      if (live['started_at'] != null && live['ended_at'] != null) {
        final start = DateTime.parse(live['started_at'] as String);
        final end = DateTime.parse(live['ended_at'] as String);
        totalHours += end.difference(start).inMinutes / 60.0;
      } else if (live['started_at'] != null && live['status'] == 'live') {
        final start = DateTime.parse(live['started_at'] as String);
        totalHours += DateTime.now().difference(start).inMinutes / 60.0;
      }
    }

    // 4. Bandwidth calculation: 
    // Average live bit rate is 1.5 Mbps.
    // Bandwidth (GB) = (Bitrate in Mbps * Time in seconds * Viewers) / 8000
    // Simplified estimate: 0.675 GB per viewer-hour (1.5 Mbps * 3600s / 8000)
    double bandwidthGB = totalViewers * totalHours * 0.675;

    // 5. Ranking of transmitters (broadcasters with highest sum of max_viewers)
    final Map<String, int> creatorAudience = {};
    final Map<String, String> creatorNameMap = {};
    
    for (var live in livesList) {
      final creatorId = live['creator_id'] as String;
      final maxV = (live['max_viewers'] as num? ?? 0).toInt();
      final creatorData = live['users'];
      final name = creatorData != null ? (creatorData as Map)['name'] as String : 'Desconhecido';
      
      creatorNameMap[creatorId] = name;
      creatorAudience[creatorId] = (creatorAudience[creatorId] ?? 0) + maxV;
    }

    final sortedCreators = creatorAudience.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final ranking = sortedCreators.take(5).map((entry) {
      return {
        'id': entry.key,
        'name': creatorNameMap[entry.key] ?? 'Desconhecido',
        'audience': entry.value,
      };
    }).toList();

    return {
      'totalUsers': totalUsers,
      'activeUsers': activeUsers,
      'totalLives': totalLives,
      'livesInProgress': livesInProgress,
      'totalViewers': totalViewers,
      'totalHours': double.parse(totalHours.toStringAsFixed(1)),
      'bandwidthGB': double.parse(bandwidthGB.toStringAsFixed(2)),
      'ranking': ranking,
    };
  }
}
