import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart' as stripe;

/// Utilidad compartida:
/// - Revisa si el hablante ya tiene método de pago guardado.
/// - Si no, abre PaymentSheet (SetupIntent) y finaliza para guardar tarjeta.
/// - Devuelve true si al final el usuario ya tiene tarjeta guardada.
class SpeakerPaymentMethod {
  SpeakerPaymentMethod({
    FirebaseFirestore? db,
    FirebaseFunctions? functions,
  })  : _db = db ?? FirebaseFirestore.instance,
        _functions =
            functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  Future<bool> hasSavedCard(String uid) async {
    final snap = await _db.collection('users').doc(uid).get();
    final data = snap.data() ?? {};
    final last4 = (data['stripeDefaultPmLast4'] as String?)?.trim() ?? '';
    return last4.isNotEmpty;
  }

  /// Abre PaymentSheet (SetupIntent). Si el usuario cancela o falla, regresa false.
  Future<bool> ensureHasPaymentMethod({
    required BuildContext context,
    required String uid,
  }) async {
    final already = await hasSavedCard(uid);
    if (already) return true;

    try {
      final callable = _functions.httpsCallable('payments_prepareSetupIntent');
      final resp = await callable.call();
      final raw = resp.data;

      if (raw == null || raw is! Map) {
        throw Exception('Respuesta inválida de payments_prepareSetupIntent.');
      }

      final data = Map<String, dynamic>.from(raw as Map);

      final customerId = (data['customerId'] as String?)?.trim() ?? '';
      final ephemeralKeySecret =
          (data['ephemeralKeySecret'] as String?)?.trim() ?? '';
      final setupIntentClientSecret =
          (data['setupIntentClientSecret'] as String?)?.trim() ?? '';
      final publishableKey = (data['publishableKey'] as String?)?.trim() ?? '';

      if (customerId.isEmpty ||
          ephemeralKeySecret.isEmpty ||
          setupIntentClientSecret.isEmpty ||
          publishableKey.isEmpty) {
        throw Exception(
          'Faltan datos de Stripe desde el backend. '
          'customerId/ephemeralKey/setupIntent/publishableKey deben venir completos.',
        );
      }

      stripe.Stripe.publishableKey = publishableKey;
      await stripe.Stripe.instance.applySettings();

      await stripe.Stripe.instance.initPaymentSheet(
        paymentSheetParameters: stripe.SetupPaymentSheetParameters(
          merchantDisplayName: 'Lissen',
          customerId: customerId,
          customerEphemeralKeySecret: ephemeralKeySecret,
          setupIntentClientSecret: setupIntentClientSecret,
          allowsDelayedPaymentMethods: false,
        ),
      );

      await stripe.Stripe.instance.presentPaymentSheet();

      await _functions.httpsCallable('payments_finalizeSetupIntent').call({
        'setupIntentClientSecret': setupIntentClientSecret,
      });

      return await hasSavedCard(uid);
    } on stripe.StripeException catch (e) {
      final msg = e.error.localizedMessage ?? e.toString();
      final lower = msg.toLowerCase();

      // cancelado por usuario
      if (lower.contains('canceled') || lower.contains('cancelled')) {
        return false;
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Stripe error: $msg')),
        );
      }
      return false;
    } on FirebaseFunctionsException catch (e) {
      final pretty = '[${e.code}] ${e.message ?? 'Sin mensaje'}'
          '${e.details != null ? ' • details: ${e.details}' : ''}';
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Functions error: $pretty')),
        );
      }
      return false;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error PaymentSheet: $e')),
        );
      }
      return false;
    }
  }
}
