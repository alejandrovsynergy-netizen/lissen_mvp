import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

class LiveKitCallScreen extends StatefulWidget {
  final String sessionId;
  final String callId;
  final String url;
  final String token;
  final String callType; // 'voice' | 'video'

  const LiveKitCallScreen({
    super.key,
    required this.sessionId,
    required this.callId,
    required this.url,
    required this.token,
    required this.callType,
  });

  @override
  State<LiveKitCallScreen> createState() => _LiveKitCallScreenState();
}

class _LiveKitCallScreenState extends State<LiveKitCallScreen> {
  Room? _room;
  EventsListener<RoomEvent>? _listener;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _callSub;

  String? _error;
  bool _needsSettings = false;
  bool _reconnecting = false;
  bool _ending = false;
  bool _micEnabled = true;
  bool _camEnabled = false;
  bool _speakerOn = true;

  @override
  void initState() {
    super.initState();
    _listenCallState();
    _connect();
  }

  void _listenCallState() {
    _callSub = FirebaseFirestore.instance
        .collection('sessions')
        .doc(widget.sessionId)
        .collection('call')
        .doc('state')
        .snapshots()
        .listen((snap) {
      final data = snap.data() ?? {};
      final status = (data['status'] ?? '').toString();
      final callId = (data['callId'] ?? '').toString();

      if (callId.isNotEmpty && callId != widget.callId) {
        if (mounted) Navigator.pop(context);
        return;
      }

      if (status == 'ended' && mounted) {
        _disconnectRoom();
        Navigator.pop(context);
      }
    });
  }

  Future<void> _connect() async {
    try {
      final micStatus = await Permission.microphone.request();

      if (micStatus.isPermanentlyDenied) {
        setState(() {
          _needsSettings = true;
          _error = 'Activa Microfono en Ajustes para poder llamar.';
        });
        return;
      }
      if (!micStatus.isGranted) {
        setState(() => _error = 'Necesito permiso de Microfono para la llamada.');
        return;
      }

      if (widget.callType == 'video') {
        final camStatus = await Permission.camera.request();

        if (camStatus.isPermanentlyDenied) {
          setState(() {
            _needsSettings = true;
            _error = 'Activa Camara en Ajustes para la videollamada.';
          });
          return;
        }
        if (!camStatus.isGranted) {
          setState(() => _error = 'Necesito permiso de Camara para la videollamada.');
          return;
        }
      }

      final room = Room(
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultAudioOutputOptions: AudioOutputOptions(speakerOn: true),
        ),
      );
      final listener = room.createListener();

      listener
        ..on<RoomDisconnectedEvent>((_) {
          _reconnecting = false;
          _requestEndCall();
          if (mounted) Navigator.pop(context);
        })
        ..on<RoomReconnectingEvent>((_) {
          if (mounted) setState(() => _reconnecting = true);
        })
        ..on<RoomReconnectedEvent>((_) {
          if (mounted) setState(() => _reconnecting = false);
        })
        ..on<ParticipantConnectedEvent>((_) {
          if (mounted) setState(() {});
        })
        ..on<ParticipantDisconnectedEvent>((_) {
          if (mounted) setState(() {});
        })
        ..on<TrackSubscribedEvent>((_) {
          if (mounted) setState(() {});
        })
        ..on<TrackUnsubscribedEvent>((_) {
          if (mounted) setState(() {});
        })
        ..on<LocalTrackPublishedEvent>((_) {
          if (mounted) setState(() {});
        })
        ..on<LocalTrackUnpublishedEvent>((_) {
          if (mounted) setState(() {});
        });

      await room.connect(
        widget.url,
        widget.token,
      );

      await room.localParticipant?.setMicrophoneEnabled(true);

      final enableCam = widget.callType == 'video';
      await room.localParticipant?.setCameraEnabled(enableCam);
      await room.setSpeakerOn(true);

      if (!mounted) return;
      setState(() {
        _room = room;
        _listener = listener;
        _error = null;
        _micEnabled = room.localParticipant?.isMicrophoneEnabled() ?? true;
        _camEnabled = room.localParticipant?.isCameraEnabled() ?? false;
        _speakerOn = room.speakerOn ?? true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _requestEndCall() async {
    if (_ending) return;
    _ending = true;
    try {
      await FirebaseFirestore.instance
          .collection('sessions')
          .doc(widget.sessionId)
          .collection('call')
          .doc('state')
          .set({'status': 'ended'}, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<bool> _confirmHangUp() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Finalizar llamada'),
          content: const Text('Quieres colgar la llamada?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Colgar'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _hangUp() async {
    final confirmed = await _confirmHangUp();
    if (!confirmed) return;

    await _requestEndCall();
    _disconnectRoom();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _toggleMic() async {
    final room = _room;
    if (room == null) return;
    final next = !_micEnabled;
    await room.localParticipant?.setMicrophoneEnabled(next);
    if (mounted) setState(() => _micEnabled = next);
  }

  Future<void> _toggleCamera() async {
    final room = _room;
    if (room == null) return;
    final next = !_camEnabled;
    await room.localParticipant?.setCameraEnabled(next);
    if (mounted) setState(() => _camEnabled = next);
  }

  Future<void> _toggleSpeaker() async {
    final room = _room;
    if (room == null) return;
    final next = !_speakerOn;
    await room.setSpeakerOn(next);
    if (mounted) setState(() => _speakerOn = next);
  }

  void _disconnectRoom() {
    try {
      _room?.disconnect();
    } catch (_) {}
  }

  VideoTrack? _firstRemoteVideoTrack(Room room) {
    for (final participant in room.remoteParticipants.values) {
      for (final pub in participant.videoTrackPublications) {
        final track = pub.track;
        if (track != null && !pub.muted) {
          return track;
        }
      }
    }
    return null;
  }

  VideoTrack? _firstLocalVideoTrack(Room room) {
    final local = room.localParticipant;
    if (local == null) return null;
    for (final pub in local.videoTrackPublications) {
      final track = pub.track;
      if (track != null && !pub.muted) {
        return track;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _callSub?.cancel();
    _listener?.dispose();
    _room?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.callType == 'video' ? 'Videollamada' : 'Llamada';

    final room = _room;
    final remoteCount = room?.remoteParticipants.length ?? 0;
    final isVideo = widget.callType == 'video';

    return WillPopScope(
      onWillPop: () async {
        final confirmed = await _confirmHangUp();
        if (confirmed) {
          await _requestEndCall();
          _disconnectRoom();
        }
        return confirmed;
      },
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(
          child: _error != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('ERROR: $_error', textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    if (_needsSettings)
                      ElevatedButton(
                        onPressed: () => openAppSettings(),
                        child: const Text('Abrir ajustes'),
                      )
                    else
                      ElevatedButton(
                        onPressed: _connect,
                        child: const Text('Reintentar'),
                      ),
                  ],
                )
              : (room == null)
                  ? const CircularProgressIndicator()
                  : Stack(
                      children: [
                        Positioned.fill(
                          child: isVideo
                              ? _buildVideoStage(room)
                              : _buildAudioStage(remoteCount),
                        ),
                        if (_reconnecting)
                          Positioned(
                            top: 8,
                            left: 12,
                            right: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Reconectando...',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                        Positioned(
                          bottom: 24,
                          left: 24,
                          right: 24,
                          child: _buildControls(isVideo),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _buildAudioStage(int remoteCount) {
    final status = remoteCount == 0
        ? 'Conectado. Esperando a la otra persona.'
        : 'En llamada.';
    return Center(
      child: Text(
        status,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 16),
      ),
    );
  }

  Widget _buildVideoStage(Room room) {
    final remoteTrack = _firstRemoteVideoTrack(room);
    final localTrack = _firstLocalVideoTrack(room);

    return Stack(
      children: [
        Positioned.fill(
          child: remoteTrack == null
              ? Container(
                  color: Colors.black,
                  alignment: Alignment.center,
                  child: const Text(
                    'Esperando video...',
                    style: TextStyle(color: Colors.white70),
                  ),
                )
              : VideoTrackRenderer(
                  remoteTrack,
                  fit: VideoViewFit.cover,
                ),
        ),
        Positioned(
          right: 12,
          top: 12,
          width: 120,
          height: 180,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white24),
            ),
            clipBehavior: Clip.antiAlias,
            child: localTrack == null
                ? const Center(
                    child: Icon(Icons.videocam_off, color: Colors.white54),
                  )
                : VideoTrackRenderer(
                    localTrack,
                    fit: VideoViewFit.cover,
                    mirrorMode: VideoViewMirrorMode.auto,
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildControls(bool isVideo) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _circleButton(
          icon: _micEnabled ? Icons.mic : Icons.mic_off,
          onTap: _toggleMic,
          background: _micEnabled ? Colors.white10 : Colors.redAccent,
        ),
        if (isVideo)
          _circleButton(
            icon: _camEnabled ? Icons.videocam : Icons.videocam_off,
            onTap: _toggleCamera,
            background: _camEnabled ? Colors.white10 : Colors.redAccent,
          ),
        _circleButton(
          icon: _speakerOn ? Icons.volume_up : Icons.volume_off,
          onTap: _toggleSpeaker,
          background: _speakerOn ? Colors.white10 : Colors.redAccent,
        ),
        _circleButton(
          icon: Icons.call_end,
          onTap: _hangUp,
          background: Colors.redAccent,
        ),
      ],
    );
  }

  Widget _circleButton({
    required IconData icon,
    required VoidCallback onTap,
    required Color background,
  }) {
    return InkResponse(
      onTap: onTap,
      radius: 28,
      child: CircleAvatar(
        radius: 24,
        backgroundColor: background,
        foregroundColor: Colors.white,
        child: Icon(icon),
      ),
    );
  }
}
