import 'package:cloud_firestore/cloud_firestore.dart';

class OffersService {
  final FirebaseFirestore _db;
  OffersService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  /// COMPAÑERA TOMA OFERTA:
  /// Marca la oferta como pending_speaker y guarda datos de la compañera.
  Future<void> companionTakeOffer({
    required String offerId,
    required String speakerId,
    required String currentUserId,
    required String currentUserAlias,
  }) async {
    if (speakerId.trim().isEmpty) {
      throw Exception('Oferta inválida (sin hablante).');
    }

    await _db.collection('offers').doc(offerId).update({
      'status': 'pending_speaker',
      'pendingSpeakerId': speakerId,
      'pendingCompanionId': currentUserId,
      'pendingCompanionAlias': currentUserAlias,
      'pendingSince': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// SPEAKER ACEPTA OFERTA:
  /// - marca la oferta como used
  /// - crea una sesión active en /sessions
  /// - devuelve el sessionId creado
  ///
  /// Nota: en tu flujo actual parece que usas `acceptPendingCompanion` (que también crea sesión),
  /// así que este método puede quedar como "no usado" por ahora.
  Future<String> speakerAcceptOffer({
    required String offerId,
    required String speakerId,
    required String pendingCompanionId,
    required String pendingCompanionAlias,
    required int durationMinutes,
    required int priceCents,
    required String currency,
    required String speakerAlias,
  }) async {
    final offersRef = _db.collection('offers').doc(offerId);
    final sessionsRef = _db.collection('sessions');

    return _db.runTransaction<String>((tx) async {
      final offerSnap = await tx.get(offersRef);
      if (!offerSnap.exists) {
        throw Exception('La oferta ya no existe.');
      }

      final newSessionRef = sessionsRef.doc();
      tx.set(newSessionRef, {
        'offerId': offerId,
        'speakerId': speakerId,
        'speakerAlias': speakerAlias,
        'companionId': pendingCompanionId,
        'companionAlias': pendingCompanionAlias,
        'participants': [speakerId, pendingCompanionId],
        'status': 'active',
        'durationMinutes': durationMinutes,
        'priceCents': priceCents,
        'currency': currency,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      tx.update(offersRef, {
        'status': 'used',
        'usedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return newSessionRef.id;
    });
  }

  /// SPEAKER ACEPTA COMPAÑERA PENDIENTE (idéntico a OffersPage):
  /// Devuelve un mapa con:
  /// - result: ok | already_used | not_pending | not_exists
  /// - sessionId: si aplica
  Future<Map<String, dynamic>> acceptPendingCompanion({
    required String offerId,
    required String speakerUid,
  }) async {
    final offerRef = _db.collection('offers').doc(offerId);

    return _db.runTransaction<Map<String, dynamic>>((tx) async {
      final offerSnap = await tx.get(offerRef);

      if (!offerSnap.exists) {
        return {'result': 'not_exists'};
      }

      final data = offerSnap.data() as Map<String, dynamic>;
      final status = (data['status'] ?? 'active') as String;
      final speakerId = (data['speakerId'] ?? '') as String;
      final pendingCompanionId = (data['pendingCompanionId'] ?? '') as String?;
      final lastSessionId = (data['lastSessionId'] ?? '') as String?;

      // Si ya hay sesión usada, devolvemos eso
      if (status == 'used' && lastSessionId != null && lastSessionId.isNotEmpty) {
        return {'result': 'already_used', 'sessionId': lastSessionId};
      }

      // Caso ideal: todavía está pendiente para este hablante
      if (status == 'pending_speaker' &&
          speakerId == speakerUid &&
          pendingCompanionId != null &&
          pendingCompanionId.isNotEmpty) {
        final sessionsRef = _db.collection('sessions');
        final newSessionRef = sessionsRef.doc();

        final speakerAlias = (data['speakerAlias'] ?? 'Hablante').toString();
        final companionAlias =
            (data['pendingCompanionAlias'] ?? 'Compañera').toString();
        final durationMinutes =
            (data['durationMinutes'] ?? data['minMinutes'] ?? 30) as int;
        final int rawPriceCents =
            (data['priceCents'] ?? data['totalMinAmountCents'] ?? 0) as int;
        final communicationType =
            (data['communicationType'] ?? 'chat').toString();
        final currency = (data['currency'] ?? 'usd').toString();

        tx.set(newSessionRef, {
          'speakerId': speakerId,
          'companionId': pendingCompanionId,
          'speakerAlias': speakerAlias,
          'companionAlias': companionAlias,
          'offerId': offerId,
          'status': 'active',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'durationMinutes': durationMinutes,
          'communicationType': communicationType,
          'currency': currency,
          'priceCents': rawPriceCents,
          'participants': [speakerId, pendingCompanionId],
        });

        tx.update(offerRef, {
          'status': 'used',
          'lastSessionId': newSessionRef.id,
          'pendingSpeakerId': FieldValue.delete(),
          'pendingCompanionId': FieldValue.delete(),
          'pendingCompanionAlias': FieldValue.delete(),
          'pendingSince': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        return {'result': 'ok', 'sessionId': newSessionRef.id};
      }

      return {'result': 'not_pending'};
    });
  }
    /// SPEAKER RECHAZA COMPAÑERA PENDIENTE
  /// Devuelve:
  /// - ok | already_used | not_pending | not_exists
  Future<String> rejectPendingCompanion({
    required String offerId,
    required String speakerUid,
  }) async {
    final offerRef = _db.collection('offers').doc(offerId);

    return _db.runTransaction<String>((tx) async {
      final offerSnap = await tx.get(offerRef);

      if (!offerSnap.exists) {
        return 'not_exists';
      }

      final data = offerSnap.data() as Map<String, dynamic>;
      final status = (data['status'] ?? 'active') as String;
      final speakerId = (data['speakerId'] ?? '') as String;
      final pendingCompanionId =
          (data['pendingCompanionId'] ?? '') as String?;
      final lastSessionId = (data['lastSessionId'] ?? '') as String?;

      if (status == 'used' &&
          lastSessionId != null &&
          lastSessionId.isNotEmpty) {
        return 'already_used';
      }

      if (status == 'pending_speaker' &&
          speakerId == speakerUid &&
          pendingCompanionId != null &&
          pendingCompanionId.isNotEmpty &&
          (lastSessionId == null || lastSessionId.isEmpty)) {
        tx.update(offerRef, {
          'status': 'active',
          'pendingSpeakerId': FieldValue.delete(),
          'pendingCompanionId': FieldValue.delete(),
          'pendingCompanionAlias': FieldValue.delete(),
          'pendingSince': FieldValue.delete(),
          'rejectedBySpeakerId': speakerUid,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return 'ok';
      }

      return 'not_pending';
    });
  }

}
