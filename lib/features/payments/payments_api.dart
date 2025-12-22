import 'package:cloud_functions/cloud_functions.dart';

/// Capa mínima: solo llama Cloud Functions.
/// Aquí NO va lógica de UI, NO va Firestore, NO va navegación.
class PaymentsApi {
  PaymentsApi({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  final FirebaseFunctions _functions;

  /// Prepara SetupIntent + EphemeralKey + Customer para que el hablante guarde tarjeta.
  /// (La Cloud Function la crearemos en el siguiente paso)
  Future<Map<String, dynamic>> prepareSetupIntent() async {
    final callable = _functions.httpsCallable('payments_prepareSetupIntent');
    final res = await callable.call(<String, dynamic>{});
    final data = res.data;
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    throw StateError('payments_prepareSetupIntent devolvió un tipo inesperado: ${data.runtimeType}');
  }

  /// Autoriza el hold para una sesión (manual capture).
  /// (La Cloud Function la crearemos después)
  Future<Map<String, dynamic>> authorizeSessionHold({required String sessionId}) async {
    final callable = _functions.httpsCallable('payments_authorizeSessionHold');
    final res = await callable.call(<String, dynamic>{'sessionId': sessionId});
    final data = res.data;
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    throw StateError('payments_authorizeSessionHold devolvió un tipo inesperado: ${data.runtimeType}');
  }

  /// Autoriza el hold para una oferta (manual capture) y reserva un sessionId.
  /// Este flujo sirve para que **NO** se cree ninguna sesión si el hold falla.
  Future<Map<String, dynamic>> authorizeOfferHold({
    required String offerId,
    required String sessionId,
  }) async {
    final callable = _functions.httpsCallable('payments_authorizeOfferHold');
    final res = await callable.call(<String, dynamic>{
      'offerId': offerId,
      'sessionId': sessionId,
    });
    final data = res.data;
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    throw StateError('payments_authorizeOfferHold devolvió un tipo inesperado: ${data.runtimeType}');
  }

  /// Captura el pago al finalizar sesión.
  /// (La Cloud Function la crearemos después)
  Future<Map<String, dynamic>> captureSessionPayment({required String sessionId}) async {
    final callable = _functions.httpsCallable('payments_captureSessionPayment');
    final res = await callable.call(<String, dynamic>{'sessionId': sessionId});
    final data = res.data;
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    throw StateError('payments_captureSessionPayment devolvió un tipo inesperado: ${data.runtimeType}');
  }
}
