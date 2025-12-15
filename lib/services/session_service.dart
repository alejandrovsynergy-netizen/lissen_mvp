import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/session_model.dart';

class SessionService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Leer una sesión por ID
  Future<SessionModel?> getSessionById(String sessionId) async {
    final doc = await _db.collection('sessions').doc(sessionId).get();
    if (!doc.exists || doc.data() == null) return null;
    return SessionModel.fromDoc(doc);
  }

  /// Stream de sesiones de un usuario (igual que HomeTab)
  Stream<List<SessionModel>> streamSessionsForUser(String uid) {
    return _db
        .collection('sessions')
        .where('participants', arrayContains: uid)
        .snapshots()
        .map((snap) => snap.docs.map(SessionModel.fromDoc).toList());
  }

  /// Crear sesión nueva (versión similar a la lógica de OffersPage)
  Future<String> createSessionFromOffer({
    required String currentUserId,
    required String currentUserAlias,
    required Map<String, dynamic> offerData,
    required String offerId,
  }) async {
    final speakerId = offerData['speakerId'] ?? '';
    final speakerAlias = offerData['speakerAlias'] ?? '';
    final duration = offerData['durationMinutes'] ?? 30;
    final priceCents = offerData['priceCents'] ?? 0;
    final currency = offerData['currency'] ?? 'usd';

    final ref = await _db.collection('sessions').add({
      'speakerId': speakerId,
      'speakerAlias': speakerAlias,
      'companionId': currentUserId,
      'companionAlias': currentUserAlias,
      'offerId': offerId,
      'status': 'active',
      'durationMinutes': duration,
      'priceCents': priceCents,
      'currency': currency,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      // opcional: lista de participantes para el where('participants')
      'participants': [speakerId, currentUserId],
    });

    return ref.id;
  }

  /// Reusar sesión si existe, crear si no
  Future<String> createOrReuseSession({
    required String currentUserId,
    required String currentUserAlias,
    required String offerId,
    required Map<String, dynamic> offerData,
  }) async {
    final sessionsRef = _db.collection('sessions');

    // Buscar sesión existente
    final q = await sessionsRef
        .where('companionId', isEqualTo: currentUserId)
        .where('offerId', isEqualTo: offerId)
        .limit(1)
        .get();

    if (q.docs.isNotEmpty) {
      final data = q.docs.first.data();
      final status = data['status'] ?? 'active';
      if (status != 'cancelled') {
        return q.docs.first.id;
      }
    }

    // Crear nueva si no hay válida
    return createSessionFromOffer(
      currentUserId: currentUserId,
      currentUserAlias: currentUserAlias,
      offerId: offerId,
      offerData: offerData,
    );
  }

  /// Marcar sesión como finalizada
  Future<void> completeSession(String sessionId) async {
    await _db.collection('sessions').doc(sessionId).update({
      'status': 'completed',
      'completedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
