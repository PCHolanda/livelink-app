import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:uuid/uuid.dart';
import '../../models/live_model.dart';
import '../../services/supabase_service.dart';
import '../../services/livekit_service.dart';

class SpectatorView extends StatefulWidget {
  final String slug;
  const SpectatorView({super.key, required this.slug});

  @override
  State<SpectatorView> createState() => _SpectatorViewState();
}

class _SpectatorViewState extends State<SpectatorView> {
  LiveModel? _live;
  String? _viewerSessionId;
  bool _isLoading = true;
  bool _isLiveActive = false;
  bool _isMuted = true;

  StreamSubscription<LiveModel>? _liveSubscription;

  @override
  void initState() {
    super.initState();
    _initSpectatorSession();
  }

  @override
  void dispose() {
    _cleanupSession();
    super.dispose();
  }

  Future<void> _cleanupSession() async {
    _liveSubscription?.cancel();
    final supabaseService = Provider.of<SupabaseService>(context, listen: false);
    final liveKitService = Provider.of<LiveKitService>(context, listen: false);

    // 1. Leave viewer counter session in database
    if (_viewerSessionId != null) {
      try {
        await supabaseService.leaveLiveSession(_viewerSessionId!);
      } catch (e) {
        debugPrint('Error leaving viewer session: $e');
      }
    }

    // 2. Disconnect from LiveKit
    await liveKitService.disconnect();
  }

  Future<void> _initSpectatorSession() async {
    final supabaseService = Provider.of<SupabaseService>(context, listen: false);
    try {
      // 1. Resolve live by slug
      final live = await supabaseService.getLiveBySlug(widget.slug);
      if (live == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _live = live;
        _isLiveActive = live.status == 'live';
      });

      // 2. Insert session inside public.viewers table (DB trigger increments viewer counters)
      final sessionId = await supabaseService.joinLiveSession(live.id);
      setState(() {
        _viewerSessionId = sessionId;
        _isLoading = false;
      });

      // 3. Connect to LiveKit if already streaming
      if (_isLiveActive) {
        await _connectLiveKit(live);
      }

      // 4. Set up real-time stream subscription to watch status & audience changes
      _liveSubscription = supabaseService.streamLive(live.id).listen((updatedLive) {
        if (!mounted) return;

        final wasLive = _isLiveActive;
        final isNowLive = updatedLive.status == 'live';

        setState(() {
          _live = updatedLive;
          _isLiveActive = isNowLive;
        });

        // Trigger LiveKit connect/disconnect based on real-time status changes
        if (!wasLive && isNowLive) {
          _connectLiveKit(updatedLive);
        } else if (wasLive && !isNowLive) {
          // Broadcaster stopped live
          Provider.of<LiveKitService>(context, listen: false).disconnect();
        }
      });
    } catch (e) {
      debugPrint('Error initializing spectator session: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _connectLiveKit(LiveModel live) async {
    final supabaseService = Provider.of<SupabaseService>(context, listen: false);
    final liveKitService = Provider.of<LiveKitService>(context, listen: false);

    try {
      // Generate anonymous identifier for spectator token
      final spectatorId = 'viewer_${const Uuid().v4().substring(0, 8)}';

      // Request token from Edge Function
      final credentials = await supabaseService.generateLiveKitToken(
        roomName: live.slug,
        identity: spectatorId,
        isPublisher: false,
      );

      // Connect LiveKit client
      await liveKitService.connectToRoom(
        url: credentials['url'] as String,
        token: credentials['token'] as String,
        isPublisher: false,
      );

      _applyMuteState();

      // Listen for new track subscriptions to enforce mute state
      liveKitService.room?.createListener().on<TrackSubscribedEvent>((event) {
        if (event.track is AudioTrack) {
          event.track.mediaStreamTrack.enabled = !_isMuted;
        }
      });
    } catch (e) {
      debugPrint('Error connecting LiveKit spectator: $e');
    }
  }

  void _applyMuteState() {
    final liveKitService = Provider.of<LiveKitService>(context, listen: false);
    if (liveKitService.room != null) {
      for (var participant in liveKitService.room!.remoteParticipants.values) {
        for (var pub in participant.audioTrackPublications) {
          pub.track?.mediaStreamTrack.enabled = !_isMuted;
        }
      }
    }
  }

  Future<void> _toggleMute() async {
    final liveKitService = Provider.of<LiveKitService>(context, listen: false);
    setState(() {
      _isMuted = !_isMuted;
    });
    
    if (liveKitService.room != null) {
      if (!_isMuted) {
        try {
          await liveKitService.room!.startAudio();
        } catch (e) {
          debugPrint('Error starting audio: $e');
        }
      }
      _applyMuteState();
    }
  }

  // ==========================================
  // VIEW RENDERERS
  // ==========================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final liveKitService = Provider.of<LiveKitService>(context);
    final supabaseService = Provider.of<SupabaseService>(context);

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Preparando sala de transmissão...', style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      );
    }

    if (_live == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.broken_image_rounded, size: 80, color: Colors.white38),
                const SizedBox(height: 24),
                const Text(
                  'Transmissão Não Encontrada',
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'O link que você seguiu pode estar incorreto ou a transmissão foi deletada.',
                  style: TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('Ir para Home'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Try to find the broadcaster's remote video track
    VideoTrack? remoteVideoTrack = liveKitService.remoteVideoTracks.firstOrNull;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // 1. Streaming Screen or Custom Notice Overlays
            if (_live!.isIdle)
              _buildOverlayScreen(
                icon: Icons.schedule_rounded,
                title: 'Transmissão Aguardando Início',
                subtitle: 'O transmissor ainda não iniciou a câmera. Aguarde um momento.',
                color: Colors.amber,
              )
            else if (_live!.isEnded)
              _buildOverlayScreen(
                icon: Icons.cancel_presentation_rounded,
                title: 'Transmissão Encerrada',
                subtitle: 'Esta transmissão foi encerrada pelo apresentador.',
                color: Colors.grey,
              )
            else if (_isLiveActive && remoteVideoTrack != null)
              // Streaming video display
              Positioned.fill(
                child: VideoTrackRenderer(
                  remoteVideoTrack,
                  fit: VideoViewFit.cover,
                ),
              )
            else
              // Connecting/Buffering indicator
              _buildOverlayScreen(
                icon: Icons.sync_rounded,
                title: 'Conectando ao Streaming...',
                subtitle: 'Sintonizando feed de áudio e vídeo em tempo real.',
                color: theme.colorScheme.primary,
                showLoading: true,
              ),

            // 2. Spectator Overlay (Title and Viewer Count)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
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
                            shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Assistindo pelo LiveLink',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
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
                      // Dynamic online viewers count
                      Container(
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
                              '${_live!.currentViewers}',
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ),

            // 3. Audio Control Overlay (Bottom Left)
            if (_isLiveActive && remoteVideoTrack != null)
              Positioned(
                bottom: 24,
                right: 24,
                child: FloatingActionButton(
                  backgroundColor: Colors.black.withOpacity(0.6),
                  foregroundColor: Colors.white,
                  onPressed: _toggleMute,
                  child: Icon(_isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlayScreen({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    bool showLoading = false,
  }) {
    return Positioned.fill(
      child: Container(
        color: Colors.grey[950],
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (showLoading)
              const Padding(
                padding: EdgeInsets.only(bottom: 24),
                child: CircularProgressIndicator(),
              )
            else
              Icon(icon, size: 80, color: color.withOpacity(0.6)),
            const SizedBox(height: 24),
            Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
