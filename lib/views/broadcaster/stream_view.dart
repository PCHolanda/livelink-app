import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart';
import '../../models/live_model.dart';
import '../../services/supabase_service.dart';
import '../../services/livekit_service.dart';

class StreamView extends StatefulWidget {
  final String liveId;
  const StreamView({super.key, required this.liveId});

  @override
  State<StreamView> createState() => _StreamViewState();
}

class _StreamViewState extends State<StreamView> {
  LiveModel? _live;
  bool _isLiveActive = false;
  bool _isCameraOn = true;
  bool _isMicOn = true;

  // Stream duration tracking
  Timer? _durationTimer;
  Duration _elapsedTime = Duration.zero;

  @override
  void initState() {
    super.initState();
    _loadLiveDetails();
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    // Disconnect when leaving page to release camera resources
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<LiveKitService>(context, listen: false).disconnect();
    });
    super.dispose();
  }

  Future<void> _loadLiveDetails() async {
    final supabaseService = Provider.of<SupabaseService>(context, listen: false);
    try {
      final live = await supabaseService.getLiveById(widget.liveId);
      setState(() {
        _live = live;
        _isLiveActive = live.status == 'live';
      });

      if (_isLiveActive) {
        _startDurationTimer(live.startedAt);
        _connectLiveKit(live);
      }
    } catch (e) {
      _showError('Erro ao buscar detalhes da live: $e');
    }
  }

  void _startDurationTimer(DateTime? startedAt) {
    _durationTimer?.cancel();
    if (startedAt == null) return;
    
    _elapsedTime = DateTime.now().difference(startedAt);
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _elapsedTime = Duration(seconds: _elapsedTime.inSeconds + 1);
        });
      }
    });
  }

  Future<void> _connectLiveKit(LiveModel live) async {
    final supabaseService = Provider.of<SupabaseService>(context, listen: false);
    final liveKitService = Provider.of<LiveKitService>(context, listen: false);

    try {
      // 1. Request token from Edge Function
      final credentials = await supabaseService.generateLiveKitToken(
        roomName: live.slug,
        identity: supabaseService.currentUser?.id ?? 'broadcaster',
        isPublisher: true,
      );

      // 2. Connect via LiveKit
      await liveKitService.connectToRoom(
        url: credentials['url'] as String,
        token: credentials['token'] as String,
        isPublisher: true,
      );
    } catch (e) {
      _showError('Falha ao conectar no servidor de streaming: $e');
      setState(() {
        _isLiveActive = false;
      });
    }
  }

  // ==========================================
  // CONTROLS AND MUTING
  // ==========================================

  Future<void> _startStreaming() async {
    if (_live == null) return;

    final supabaseService = Provider.of<SupabaseService>(context, listen: false);
    
    setState(() => _isLiveActive = true);

    try {
      // 1. Update status in Supabase Database
      await supabaseService.startLive(_live!.id);
      
      // 2. Refresh live locally and start duration timer
      final updatedLive = await supabaseService.getLiveById(_live!.id);
      setState(() {
        _live = updatedLive;
      });
      _startDurationTimer(updatedLive.startedAt);

      // 3. Connect to LiveKit Room
      await _connectLiveKit(updatedLive);
    } catch (e) {
      _showError('Erro ao iniciar transmissão: $e');
      setState(() => _isLiveActive = false);
    }
  }

  Future<void> _endStreaming() async {
    if (_live == null) return;

    final supabaseService = Provider.of<SupabaseService>(context, listen: false);
    final liveKitService = Provider.of<LiveKitService>(context, listen: false);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Encerrar Transmissão'),
        content: const Text('Deseja realmente finalizar esta live? Os espectadores não poderão mais assistir.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Voltar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Encerrar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // 1. Mark live as ended in Supabase
      await supabaseService.endLive(_live!.id);
      
      // 2. Disconnect LiveKit client
      await liveKitService.disconnect();
      
      _durationTimer?.cancel();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transmissão finalizada com sucesso!')),
        );
        context.go('/broadcaster');
      }
    } catch (e) {
      _showError('Erro ao encerrar transmissão: $e');
    }
  }

  void _toggleCamera() {
    final liveKitService = Provider.of<LiveKitService>(context, listen: false);
    setState(() {
      _isCameraOn = !_isCameraOn;
    });
    liveKitService.toggleCamera(_isCameraOn);
  }

  void _toggleMic() {
    final liveKitService = Provider.of<LiveKitService>(context, listen: false);
    setState(() {
      _isMicOn = !_isMicOn;
    });
    liveKitService.toggleMicrophone(_isMicOn);
  }

  void _showError(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
      );
    }
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    final seconds = d.inSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // ==========================================
  // VIEW RENDERERS
  // ==========================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final liveKitService = Provider.of<LiveKitService>(context);
    final supabaseService = Provider.of<SupabaseService>(context);

    if (_live == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Attempt to extract local participant camera track to show preview
    VideoTrack? localVideoTrack;
    if (liveKitService.room != null) {
      final localPart = liveKitService.room!.localParticipant;
      final pub = localPart?.videoTrackPublications
          .where((p) => p.track is VideoTrack)
          .firstOrNull;
      localVideoTrack = pub?.track as VideoTrack?;
    }

    return PopScope(
      canPop: !_isLiveActive,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        _endStreaming();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              // 1. Camera Viewfinder or Idle State Placeholder
              if (_isLiveActive && localVideoTrack != null && _isCameraOn)
                Positioned.fill(
                  child: VideoTrackRenderer(
                    localVideoTrack,
                    fit: VideoViewFit.cover,
                  ),
                )
              else
                Positioned.fill(
                  child: Container(
                    color: Colors.grey[950],
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isCameraOn ? Icons.videocam_off_rounded : Icons.camera_alt_rounded,
                            size: 80,
                            color: Colors.white38,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            !_isLiveActive
                                ? 'Pronto para transmitir!'
                                : 'Câmera desativada',
                            style: const TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // 2. Stream Metadata & Metrics Overlay (Top Bar)
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Title and connection details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _live!.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _isLiveActive ? 'Tempo: ${_formatDuration(_elapsedTime)}' : 'Aguardando início',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Blinking live indicator and spectator counts
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isLiveActive) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.redAccent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.fiber_manual_record, color: Colors.white, size: 12),
                                SizedBox(width: 4),
                                Text(
                                  'AO VIVO',
                                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        // Real-time viewer counter
                        StreamBuilder<LiveModel>(
                          stream: supabaseService.streamLive(_live!.id),
                          builder: (context, snapshot) {
                            final count = snapshot.data?.currentViewers ?? _live!.currentViewers;
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.remove_red_eye_rounded, color: Colors.white70, size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$count',
                                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // 3. Central Action (Start stream button)
              if (!_isLiveActive)
                Center(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                    ),
                    onPressed: _startStreaming,
                    icon: const Icon(Icons.play_arrow_rounded, size: 28),
                    label: const Text(
                      'Iniciar Transmissão Agora',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),

              // 4. Live Controls Overlay (Bottom Bar)
              if (_isLiveActive)
                Positioned(
                  bottom: 24,
                  left: 24,
                  right: 24,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Camera toggle
                      FloatingActionButton(
                        heroTag: 'cam_toggle',
                        backgroundColor: _isCameraOn ? Colors.white24 : Colors.redAccent,
                        foregroundColor: Colors.white,
                        onPressed: _toggleCamera,
                        child: Icon(_isCameraOn ? Icons.videocam_rounded : Icons.videocam_off_rounded),
                      ),
                      // Mic toggle
                      FloatingActionButton(
                        heroTag: 'mic_toggle',
                        backgroundColor: _isMicOn ? Colors.white24 : Colors.redAccent,
                        foregroundColor: Colors.white,
                        onPressed: _toggleMic,
                        child: Icon(_isMicOn ? Icons.mic_rounded : Icons.mic_off_rounded),
                      ),
                      // Stop streaming button
                      FloatingActionButton.large(
                        heroTag: 'stop_stream',
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        onPressed: _endStreaming,
                        child: const Icon(Icons.call_end_rounded, size: 36),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
