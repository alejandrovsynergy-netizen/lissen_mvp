import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'livekit_call_screen.dart';

class OutgoingCallScreen extends StatefulWidget {
  final String sessionId;
  final String callId;
  final String callType; // 'voice' | 'video'
  final String otherAlias;

  const OutgoingCallScreen({
    super.key,
    required this.sessionId,
    required this.callId,
    required this.callType,
    required this.otherAlias,
  });

  @override
  State<OutgoingCallScreen> createState() => _OutgoingCallScreenState();
}

class _OutgoingCallScreenState extends State<OutgoingCallScreen> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _callSub;
  bool _navigated = false;
  bool _ended = false;
  String _statusMessage = 'Llamando…';

  @override
  void initState() {
    super.initState();
    _startRingback();
    _listenCallState();
  }

  @override
  void dispose() {
    _callSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _startRingback() async {
    try {
      await _player.setAsset('assets/sounds/offer_request.wav');
      await _player.setLoopMode(LoopMode.one);
      await _player.play();
    } catch (_) {
      // ignore audio errors
    }
  }

  Future<void> _stopRingback() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  void _listenCallState() {
    _callSub = FirebaseFirestore.instance
        .collection('sessions')
        .doc(widget.sessionId)
        .collection('call')
        .doc('state')
        .snapshots()
        .listen((snap) async {
      final data = snap.data() ?? {};
      final status = (data['status'] ?? '').toString();
      final callId = (data['callId'] ?? '').toString();
      final expiresAtMs = (data['expiresAtMs'] ?? 0) as int;

      if (callId.isNotEmpty && callId != widget.callId) {
        if (mounted) {
          setState(() {
            _ended = true;
            _statusMessage = 'Llamada finalizada.';
          });
        }
        await _stopRingback();
        return;
      }

      if (status == 'ringing' &&
          expiresAtMs > 0 &&
          DateTime.now().millisecondsSinceEpoch > expiresAtMs) {
        await _markEnded();
        return;
      }

      if (status == 'active' && !_navigated) {
        _navigated = true;
        await _stopRingback();
        await _joinCall();
        return;
      }

      if (status == 'ended') {
        await _stopRingback();
        if (mounted) {
          setState(() {
            _ended = true;
            _statusMessage = 'No contestó.';
          });
        }
      }
    });
  }

  Future<void> _markEnded() async {
    try {
      await FirebaseFirestore.instance
          .collection('sessions')
          .doc(widget.sessionId)
          .collection('call')
          .doc('state')
          .set({'status': 'ended'}, SetOptions(merge: true));
    } catch (_) {}

    await _stopRingback();

    if (mounted) {
      setState(() {
        _ended = true;
        _statusMessage = 'No contestó.';
      });
    }
  }

  Future<void> _joinCall() async {
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('livekitGetToken')
          .call({
        'sessionId': widget.sessionId,
        'callType': widget.callType,
      });

      final Map data = res.data as Map;
      final url = data['url']?.toString() ?? '';
      final token = data['token']?.toString() ?? '';

      if (!mounted) return;

      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => LiveKitCallScreen(
            sessionId: widget.sessionId,
            url: url,
            token: token,
            callType: widget.callType,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ended = true;
        _statusMessage = 'No se pudo conectar: $e';
      });
    }
  }

  Future<void> _hangUp() async {
    await _markEnded();
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.callType == 'video';
    final title = isVideo ? 'Videollamada' : 'Llamada';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 44,
              backgroundColor: Colors.white12,
              child: Text(
                widget.otherAlias.isNotEmpty
                    ? widget.otherAlias[0].toUpperCase()
                    : '?',
                style: const TextStyle(fontSize: 32, color: Colors.white),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.otherAlias,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _statusMessage,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 32),
            if (_ended)
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              )
            else
              ElevatedButton(
                onPressed: _hangUp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(18),
                ),
                child: const Icon(Icons.call_end),
              ),
          ],
        ),
      ),
    );
  }
}
