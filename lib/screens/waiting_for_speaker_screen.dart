import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'session_screen.dart';

class WaitingForSpeakerScreen extends StatefulWidget {
  final String offerId;
  final String speakerAlias;

  const WaitingForSpeakerScreen({
    super.key,
    required this.offerId,
    required this.speakerAlias,
  });

  @override
  State<WaitingForSpeakerScreen> createState() =>
      _WaitingForSpeakerScreenState();
}

class _WaitingForSpeakerScreenState extends State<WaitingForSpeakerScreen> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  Timer? _countdownTimer;

  bool _handledResult = false; // para no procesar dos veces
  DateTime? _pendingSince;
  int _remainingSeconds = 0;

  bool _cancelling = false; // para deshabilitar botón cancelar mientras corre

  static const Duration _maxWait = Duration(minutes: 2);

  @override
  void initState() {
    super.initState();

    // Arrancamos conteo local para no ver 00:00 mientras llega Firestore
    _pendingSince = DateTime.now();
    _startCountdownTimer();

    // Y además nos sincronizamos con Firestore (para reconexiones, etc.)
    _listenOffer();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _listenOffer() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      // Sin usuario, regresamos
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return;
    }

    _sub = FirebaseFirestore.instance
        .collection('offers')
        .doc(widget.offerId)
        .snapshots()
        .listen((doc) async {
          if (!mounted || _handledResult) return;

          if (!doc.exists) {
            // La oferta desapareció
            _handledResult = true;
            _countdownTimer?.cancel();
            await _showInfoAndPop('La oferta ya no está disponible.');
            return;
          }

          final data = doc.data()!;
          final status = data['status'] as String? ?? 'active';
          final pendingCompanionId = data['pendingCompanionId'] as String?;
          final lastSessionId = data['lastSessionId'] as String?;
          final pendingSinceTs = data['pendingSince'] as Timestamp?;

          // Mientras siga pending_speaker para ESTA compañera -> sincronizamos tiempo y esperamos
          if (status == 'pending_speaker' && pendingCompanionId == uid) {
            // Si Firestore trae un pendingSince, lo usamos SIEMPRE para alinear el tiempo real
            if (pendingSinceTs != null) {
              final serverPendingSince = pendingSinceTs.toDate();

              if (_pendingSince == null ||
                  serverPendingSince != _pendingSince) {
                _pendingSince = serverPendingSince;
                _startCountdownTimer();
              }
            }
            // seguiremos esperando hasta que timer o hablante decidan
            return;
          }

          // 🟢 Si el hablante aceptó: la oferta pasó a 'used' y tiene lastSessionId
          if (status == 'used' && lastSessionId != null) {
            _handledResult = true;
            _countdownTimer?.cancel();

            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) =>
                    SessionConversationScreen(sessionId: lastSessionId),
              ),
            );
            return;
          }

          // 🟥 Si ya no está pending_speaker y no hay sesión, es que la rechazó o se canceló desde el lado del hablante/timeout
          if ((status == 'active' || status == 'cancelled') &&
              lastSessionId == null) {
            _handledResult = true;
            _countdownTimer?.cancel();

            await _showInfoAndPop(
              'El hablante no aceptó tu solicitud.\n'
              'Esta oferta volvió a estar disponible.',
            );
            return;
          }
        });
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel();

    // Si por alguna razón sigue null, la fijamos ahora
    _pendingSince ??= DateTime.now();

    final now = DateTime.now();
    final elapsed = now.difference(_pendingSince!);
    final remaining = _maxWait - elapsed;

    if (remaining <= Duration.zero) {
      // Ya se pasó el tiempo, forzamos timeout inmediato
      _handleTimeout();
      return;
    }

    setState(() {
      _remainingSeconds = remaining.inSeconds;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _handledResult) {
        timer.cancel();
        return;
      }

      final now = DateTime.now();
      final elapsed = now.difference(_pendingSince!);
      final remaining = _maxWait - elapsed;

      if (remaining <= Duration.zero) {
        timer.cancel();
        _handleTimeout();
      } else {
        setState(() {
          _remainingSeconds = remaining.inSeconds;
        });
      }
    });
  }

  Future<void> _handleTimeout() async {
    if (_handledResult) return;
    _handledResult = true;

    // Revertir la oferta a activa y limpiar campos de pendiente
    await FirebaseFirestore.instance
        .collection('offers')
        .doc(widget.offerId)
        .update({
          'status': 'active',
          'pendingSpeakerId': FieldValue.delete(),
          'pendingCompanionId': FieldValue.delete(),
          'pendingCompanionAlias': FieldValue.delete(),
          'pendingSince': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

    await _showInfoAndPop(
      'El hablante no respondió a tiempo.\n'
      'La solicitud fue cancelada y la oferta volvió a estar disponible.',
    );
  }

  Future<void> _onCancelPressed() async {
    if (_cancelling || _handledResult) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() {
      _cancelling = true;
    });

    try {
      final result = await FirebaseFirestore.instance.runTransaction<String?>((
        transaction,
      ) async {
        final offerRef = FirebaseFirestore.instance
            .collection('offers')
            .doc(widget.offerId);

        final snap = await transaction.get(offerRef);
        if (!snap.exists) {
          return 'not_exists';
        }

        final data = snap.data() as Map<String, dynamic>;
        final status = data['status'] as String? ?? 'active';
        final pendingCompanionId = data['pendingCompanionId'] as String?;
        final lastSessionId = data['lastSessionId'];

        // Caso ideal: sigue pendiente para esta compañera y aún no hay sesión
        if (status == 'pending_speaker' &&
            pendingCompanionId == uid &&
            lastSessionId == null) {
          transaction.update(offerRef, {
            'status': 'active',
            'pendingSpeakerId': FieldValue.delete(),
            'pendingCompanionId': FieldValue.delete(),
            'pendingCompanionAlias': FieldValue.delete(),
            'pendingSince': FieldValue.delete(),
            'cancelledByCompanionId': uid,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          return 'cancel_ok';
        }

        // Si ya está usada con sesión, el hablante aceptó primero
        if (status == 'used' && lastSessionId != null) {
          return 'already_used';
        }

        // Cualquier otro estado, dejamos que el listener resuelva
        return 'no_action';
      });

      if (!mounted) return;

      if (result == 'cancel_ok') {
        // Cancelación desde compañera exitosa
        _handledResult = true;
        _countdownTimer?.cancel();
        await _showInfoAndPop(
          'Cancelaste tu solicitud.\n'
          'La oferta volvió a estar disponible.',
        );
        return;
      } else if (result == 'already_used') {
        // El hablante alcanzó a aceptar; dejamos que el listener haga el push a la sesión
        // Aquí NO marcamos _handledResult, para que el listener procese el 'used'.
        // Opcionalmente podrías mostrar un SnackBar si quisieras.
      } else {
        // 'no_action' o 'not_exists': el listener se encargará del estado final.
      }
    } catch (e) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Error'),
          content: const Text(
            'No se pudo cancelar la solicitud. Inténtalo de nuevo.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _cancelling = false;
        });
      }
    }
  }

  Future<void> _showInfoAndPop(String message) async {
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Información'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (mounted) {
      Navigator.of(context).pop(); // salir de la pantalla de espera
    }
  }

  String _formatRemaining() {
    // Si todavía no hemos calculado nada, mostramos el máximo
    final total = _remainingSeconds > 0
        ? _remainingSeconds
        : _maxWait.inSeconds;
    final minutes = total ~/ 60;
    final seconds = total % 60;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final remainingText = 'Tiempo restante: ${_formatRemaining()}';

    return WillPopScope(
      onWillPop: () async => false, // bloquear botón back
      child: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
                Text(
                  'Esperando respuesta de ${widget.speakerAlias}…',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 12),
                Text(
                  remainingText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.redAccent,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'No puedes navegar mientras el hablante decide.\n'
                  'Si se cierra la app, volverás a esta pantalla al regresar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _cancelling ? null : _onCancelPressed,
                    child: _cancelling
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Cancelar solicitud'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
