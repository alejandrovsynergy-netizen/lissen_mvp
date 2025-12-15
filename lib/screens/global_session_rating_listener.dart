import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'session_summary_dialog.dart';

/// Widget envoltorio GLOBAL que escucha sesiones completadas para el usuario
/// actual y muestra el modal de resumen/rating aunque esté en otra pantalla.
class GlobalSessionRatingListener extends StatefulWidget {
  final Widget child;

  const GlobalSessionRatingListener({super.key, required this.child});

  @override
  State<GlobalSessionRatingListener> createState() =>
      _GlobalSessionRatingListenerState();
}

class _GlobalSessionRatingListenerState
    extends State<GlobalSessionRatingListener> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _speakerSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _companionSub;

  /// Para no mostrar más de un modal a la vez
  bool _showingDialog = false;

  /// Para no repetir la misma sesión muchas veces
  final Set<String> _handledSessionIds = {};

  @override
  void initState() {
    super.initState();
    _setupListeners();
  }

  void _setupListeners() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // Si todavía no hay usuario logueado, no escuchamos nada.
      return;
    }

    final uid = user.uid;

    // 👉 Sesiones donde soy Hablante y ya están completadas
    _speakerSub = FirebaseFirestore.instance
        .collection('sessions')
        .where('speakerId', isEqualTo: uid)
        .where('status', isEqualTo: 'completed')
        .snapshots()
        .listen((snap) {
          _onSessionsSnapshot(snap, isSpeaker: true);
        });

    // 👉 Sesiones donde soy Compañera y ya están completadas
    _companionSub = FirebaseFirestore.instance
        .collection('sessions')
        .where('companionId', isEqualTo: uid)
        .where('status', isEqualTo: 'completed')
        .snapshots()
        .listen((snap) {
          _onSessionsSnapshot(snap, isSpeaker: false);
        });
  }

  Future<void> _onSessionsSnapshot(
    QuerySnapshot<Map<String, dynamic>> snap, {
    required bool isSpeaker,
  }) async {
    if (!mounted) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    for (final doc in snap.docs) {
      if (_handledSessionIds.contains(doc.id)) continue;

      final data = doc.data();

      // Campo de rating dependiendo del rol
      final ratingField = isSpeaker ? 'ratingBySpeaker' : 'ratingByCompanion';
      final rating = data[ratingField] as int? ?? 0;

      // Si ya tenía rating, lo marcamos como manejado y seguimos
      if (rating > 0) {
        _handledSessionIds.add(doc.id);
        continue;
      }

      await _showDialogForSession(doc, isSpeaker: isSpeaker);
    }
  }

  Future<void> _showDialogForSession(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    required bool isSpeaker,
  }) async {
    if (_showingDialog || !mounted) return;
    _showingDialog = true;

    final data = doc.data();
    if (data == null) {
      _showingDialog = false;
      return;
    }

    final speakerAlias = (data['speakerAlias'] ?? 'Hablante').toString();
    final companionAlias = (data['companionAlias'] ?? 'Compañera').toString();
    final duration = data['durationMinutes'] as int? ?? 0;
    final realDuration = data['realDurationMinutes'] as int? ?? 0;
    final billingMinutes = data['billingMinutes'] as int? ?? 0;
    final endedBy = (data['endedBy'] as String?) ?? '';
    final price = (data['priceCents'] ?? 0) / 100.0;
    final currency = (data['currency'] ?? 'usd').toString().toUpperCase();

    final myRoleLabel = isSpeaker ? 'Hablante' : 'Compañera';

    String endedByLabel;
    switch (endedBy) {
      case 'speaker':
        endedByLabel = 'Hablante';
        break;
      case 'companion':
        endedByLabel = 'Compañera';
        break;
      case 'timeout':
        endedByLabel = 'Por tiempo';
        break;
      default:
        endedByLabel = endedBy.isEmpty ? 'Desconocido' : endedBy;
    }

    // 🔥 AQUÍ se muestra el modal GLOBAL
    final rating = await showSessionSummaryDialog(
      context: context,
      myRoleLabel: myRoleLabel,
      speakerAlias: speakerAlias,
      companionAlias: companionAlias,
      reservedMinutes: duration,
      realMinutes: realDuration,
      billingMinutes: billingMinutes,
      endedByLabel: endedByLabel,
      price: price,
      currency: currency,
    );

    // Si el usuario eligió rating, lo guardamos en la sesión
    if (rating != null && mounted) {
      final ratingField = isSpeaker ? 'ratingBySpeaker' : 'ratingByCompanion';
      try {
        await doc.reference.update({ratingField: rating});
      } catch (_) {
        // si falla, no rompemos la app
      }
    }

    _handledSessionIds.add(doc.id);
    _showingDialog = false;
  }

  @override
  void dispose() {
    _speakerSub?.cancel();
    _companionSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Solo devuelve el child envuelto, el valor está en los listeners
    return widget.child;
  }
}
