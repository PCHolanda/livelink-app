import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

class LiveKitService extends ChangeNotifier {
  Room? _room;
  Room? get room => _room;

  bool _isConnecting = false;
  bool get isConnecting => _isConnecting;

  bool _isPublishing = false;
  bool get isPublishing => _isPublishing;

  final List<VideoTrack> _remoteVideoTracks = [];
  List<VideoTrack> get remoteVideoTracks => _remoteVideoTracks;

  Future<void> connectToRoom({
    required String url,
    required String token,
    required bool isPublisher,
  }) async {
    _isConnecting = true;
    _remoteVideoTracks.clear();
    notifyListeners();

    try {
      // Create room instance
      _room = Room();

      // Configure room listeners
      final listener = _room!.createListener();

      listener.on<TrackSubscribedEvent>((event) {
        if (event.track is VideoTrack) {
          _remoteVideoTracks.add(event.track as VideoTrack);
          notifyListeners();
        }
      });

      listener.on<TrackUnsubscribedEvent>((event) {
        if (event.track is VideoTrack) {
          _remoteVideoTracks.remove(event.track as VideoTrack);
          notifyListeners();
        }
      });

      listener.on<RoomDisconnectedEvent>((event) {
        _room = null;
        _isPublishing = false;
        _remoteVideoTracks.clear();
        notifyListeners();
      });

      // Connect to the LiveKit server
      await _room!.connect(
        url,
        token,
        roomOptions: RoomOptions(
          defaultAudioPublishOptions: AudioPublishOptions(
            name: 'audio',
          ),
          defaultVideoPublishOptions: VideoPublishOptions(
            name: 'video',
            simulcast: true,
          ),
        ),
      );

      if (isPublisher) {
        // Request camera/mic permissions and publish tracks
        await _room?.localParticipant?.setCameraEnabled(true);
        await _room?.localParticipant?.setMicrophoneEnabled(true);
        _isPublishing = true;
      }
    } catch (e) {
      debugPrint('Error connecting to LiveKit room: $e');
      await disconnect();
      rethrow;
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  Future<void> toggleCamera(bool enabled) async {
    if (_room != null && _isPublishing) {
      await _room?.localParticipant?.setCameraEnabled(enabled);
      notifyListeners();
    }
  }

  Future<void> switchCamera() async {
    if (_room != null && _isPublishing) {
      final localPart = _room!.localParticipant;
      final pub = localPart?.videoTrackPublications
          .where((p) => p.track is LocalVideoTrack)
          .firstOrNull;
      final localVideoTrack = pub?.track as LocalVideoTrack?;
      if (localVideoTrack != null) {
        await localVideoTrack.switchCamera();
        notifyListeners();
      }
    }
  }

  Future<void> toggleMicrophone(bool enabled) async {
    if (_room != null && _isPublishing) {
      await _room?.localParticipant?.setMicrophoneEnabled(enabled);
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    try {
      if (_room != null) {
        await _room!.disconnect();
        await _room!.dispose();
      }
    } catch (e) {
      debugPrint('Error during LiveKit disconnect: $e');
    } finally {
      _room = null;
      _isPublishing = false;
      _remoteVideoTracks.clear();
      notifyListeners();
    }
  }
}
