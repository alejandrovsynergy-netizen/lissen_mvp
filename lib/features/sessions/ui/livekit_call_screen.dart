import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

class LiveKitCallScreen extends StatefulWidget {
  final String sessionId;
  final String url;
  final String token;
  final String callType; // 'voice' | 'video'

  const LiveKitCallScreen({
    super.key,
    required this.sessionId,  
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

  String? _error;
  bool _needsSettings = false;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    try {
      // 1) Permisos (tipo WhatsApp: pedir popup; NO mandar a Ajustes solo)
      final micStatus = await Permission.microphone.request();

      if (micStatus.isPermanentlyDenied) {
        setState(() {
          _needsSettings = true;
          _error = 'Activa Micrófono en Ajustes para poder llamar.';
        });
        return;
      }
      if (!micStatus.isGranted) {
        setState(() => _error = 'Necesito permiso de Micrófono para la llamada.');
        return;
      }

      if (widget.callType == 'video') {
        final camStatus = await Permission.camera.request();

        if (camStatus.isPermanentlyDenied) {
          setState(() {
            _needsSettings = true;
            _error = 'Activa Cámara en Ajustes para la videollamada.';
          });
          return;
        }
        if (!camStatus.isGranted) {
          setState(() => _error = 'Necesito permiso de Cámara para la videollamada.');
          return;
        }
      }

      // 2) Room + listener (API actual)
      final room = Room();
      final listener = room.createListener(); // ✅ esto evita tus errores

      listener
        ..on<RoomDisconnectedEvent>((_) {
          if (mounted) Navigator.pop(context);
        })
        ..on<ParticipantConnectedEvent>((_) {
          if (mounted) setState(() {});
        })
        ..on<ParticipantDisconnectedEvent>((_) {
          if (mounted) setState(() {});
        });

      await room.connect(
        widget.url,
        widget.token,
        roomOptions: const RoomOptions(),
      );

      // Audio ON siempre
      await room.localParticipant?.setMicrophoneEnabled(true);

      // Video depende del tipo
      final enableCam = widget.callType == 'video';
      await room.localParticipant?.setCameraEnabled(enableCam);

      if (!mounted) return;
      setState(() {
        _room = room;
        _listener = listener;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _hangUp() async {
    try {
      await _room?.disconnect();
    } catch (_) {}
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _listener?.dispose();
    _room?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.callType == 'video' ? 'Videollamada' : 'Llamada';

    final room = _room;
    final remoteCount = room?.remoteParticipants.length ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.call_end),
            onPressed: _hangUp,
          ),
        ],
      ),
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
                : Text(
                    remoteCount == 0
                        ? 'Conectado ✅\nEsperando a la otra persona…'
                        : 'En llamada ✅',
                    textAlign: TextAlign.center,
                  ),
      ),
    );
  }
}
