import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class WaitingForCompanionResponseScreen extends StatefulWidget {
  final String offerId;

  const WaitingForCompanionResponseScreen({
    super.key,
    required this.offerId,
  });

  @override
  State<WaitingForCompanionResponseScreen> createState() =>
      _WaitingForCompanionResponseScreenState();
}

class _WaitingForCompanionResponseScreenState
    extends State<WaitingForCompanionResponseScreen> {
  static const Duration _maxWait = Duration(minutes: 1);

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  Timer? _timer;
  int _remainingSeconds = _maxWait.inSeconds;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _startCountdown();
    _listenOffer();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  void _listenOffer() {
    _sub = FirebaseFirestore.instance
        .collection('offers')
        .doc(widget.offerId)
        .snapshots()
        .listen((doc) {
      if (!mounted || _done) return;

      if (!doc.exists) {
        _finishAndPop();
        return;
      }

      final data = doc.data() ?? {};
      final status = (data['status'] ?? 'active').toString();
      final pendingCompanionId =
          (data['pendingCompanionId'] ?? '').toString().trim();

      if (status == 'pending_speaker' && pendingCompanionId.isNotEmpty) {
        _finishAndPop();
      }
    });
  }

  void _startCountdown() {
    _timer?.cancel();
    _remainingSeconds = _maxWait.inSeconds;

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _done) {
        timer.cancel();
        return;
      }

      if (_remainingSeconds <= 1) {
        timer.cancel();
        _handleTimeout();
        return;
      }

      setState(() {
        _remainingSeconds -= 1;
      });
    });
  }

  Future<void> _handleTimeout() async {
    if (_done) return;
    _done = true;

    try {
      await FirebaseFirestore.instance
          .collection('offers')
          .doc(widget.offerId)
          .get()
          .then((snap) async {
        if (!snap.exists) return;
        final data = snap.data() ?? {};
        final status = (data['status'] ?? 'active').toString();
        final pendingCompanionId =
            (data['pendingCompanionId'] ?? '').toString().trim();
        if (status == 'active' && pendingCompanionId.isEmpty) {
          await snap.reference.delete();
        }
      });
    } catch (_) {
      // Si falla el delete, igual cerramos para no bloquear al usuario.
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _finishAndPop() {
    if (_done) return;
    _done = true;
    _sub?.cancel();
    _timer?.cancel();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  String _formatRemaining() {
    final total = _remainingSeconds.clamp(0, _maxWait.inSeconds);
    final minutes = total ~/ 60;
    final seconds = total % 60;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
                const Text(
                  'Esperando respuesta de usuario',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 12),
                Text(
                  'Tiempo restante: ${_formatRemaining()}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.redAccent,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'No puedes navegar mientras esperas.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
