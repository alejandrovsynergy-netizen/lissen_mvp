import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/offer_model.dart';

class OfferService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Leer una oferta por ID
  Future<OfferModel?> getOfferById(String offerId) async {
    final doc = await _db.collection('offers').doc(offerId).get();
    if (!doc.exists || doc.data() == null) return null;
    return OfferModel.fromDoc(doc);
  }

  /// Stream de TODAS las ofertas (ya filtrarás por rol/usuario en la UI si quieres)
  Stream<List<OfferModel>> streamAllOffers() {
    return _db
        .collection('offers')
        .snapshots()
        .map((snap) => snap.docs.map(OfferModel.fromDoc).toList());
  }

  /// Crear oferta nueva (misma estructura que ya usas en OffersPage)
  Future<String> createOffer({
    required String userId,
    required String alias,
    required String country,
    required String city,
    required String title,
    required String description,
    required int priceCents,
    required int durationMinutes,
    required String targetGender, // 'todos' | 'hombre' | 'mujer'
  }) async {
    final ref = await _db.collection('offers').add({
      'speakerId': userId,
      'speakerAlias': alias,
      'speakerCountry': country,
      'speakerCity': city,
      'title': title,
      'description': description,
      'priceCents': priceCents,
      'currency': 'usd',
      'durationMinutes': durationMinutes,
      'targetGender': targetGender,
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return ref.id;
  }

  /// Marcar oferta como inactiva
  Future<void> deactivateOffer(String offerId) async {
    await _db.collection('offers').doc(offerId).update({
      'status': 'inactive',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
