import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_stripe/flutter_stripe.dart' as stripe;
import 'package:url_launcher/url_launcher.dart';

import 'package:lissen_mvp/features/payments/connect_api.dart';

class MoneyActivityScreen extends StatefulWidget {
  final String uid;

  const MoneyActivityScreen({super.key, required this.uid});

  @override
  State<MoneyActivityScreen> createState() => _MoneyActivityScreenState();
}

class _MoneyActivityScreenState extends State<MoneyActivityScreen> {
  // 0 = Métodos de pago (Stripe), 1 = Historial
  int _selectedTab = 0;

  bool _busy = false;

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _prettyFunctionsError(FirebaseFunctionsException e) {
    final code = e.code;
    final message = e.message ?? 'Sin mensaje';
    final details = e.details;
    if (details == null) return '[$code] $message';
    return '[$code] $message • details: $details';
  }

  // ============================================================
  // HABLANTE: configurar método de pago (PaymentSheet -> SetupIntent)
  // ============================================================
  Future<void> _setupSpeakerPaymentMethod() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = functions.httpsCallable('payments_prepareSetupIntent');

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

      // Configura Stripe (runtime)
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

      // ✅ Finalizar y guardar PM en Firestore (brand/last4/id)
      await functions.httpsCallable('payments_finalizeSetupIntent').call({
        'setupIntentClientSecret': setupIntentClientSecret,
      });

      _snack('Tarjeta guardada ✅');
    } on stripe.StripeException catch (e) {
      final msg = e.error.localizedMessage ?? e.toString();
      final lower = msg.toLowerCase();

      // Si el usuario cerró/canceló, lo ignoramos
      if (lower.contains('canceled') || lower.contains('cancelled')) {
        // no snackbar
      } else {
        _snack('Stripe error: $msg');
      }
    } on FirebaseFunctionsException catch (e) {
      _snack('Functions error: ${_prettyFunctionsError(e)}');
    } catch (e) {
      _snack('Error PaymentSheet: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ============================================================
  // HABLANTE: borrar método de pago
  // ============================================================
  Future<void> _removeSpeakerPaymentMethod() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      await functions.httpsCallable('payments_detachDefaultPaymentMethod').call();

      _snack('Método de pago eliminado ✅');
    } on FirebaseFunctionsException catch (e) {
      _snack('Functions error: ${_prettyFunctionsError(e)}');
    } catch (e) {
      _snack('No se pudo eliminar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dinero y actividad')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(widget.uid)
            .snapshots(),
        builder: (context, userSnap) {
          if (userSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final userData = userSnap.data?.data() ?? {};

          // Rol del usuario para controlar lo que se muestra
          final String role = (userData['role'] as String?) ?? '';
          final bool isCompanion = role == 'companion';
          final bool isSpeaker = role == 'speaker';

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            _busy ? null : () => setState(() => _selectedTab = 0),
                        child: const Text('Métodos de pago'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            _busy ? null : () => setState(() => _selectedTab = 1),
                        child: const Text('Historial de pagos'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _selectedTab == 0
                      ? _buildStripeConfig(
                          userData,
                          isSpeaker: isSpeaker,
                          isCompanion: isCompanion,
                        )
                      : _buildPaymentsHistory(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ============================================================
  // SECCIÓN "MÉTODOS DE PAGO" (Stripe / Connect)
  // ============================================================
  Widget _buildStripeConfig(
    Map<String, dynamic> userData, {
    required bool isSpeaker,
    required bool isCompanion,
  }) {
    // ===== Hablanate (paga) =====
    final stripeCustomerId = (userData['stripeCustomerId'] as String?)?.trim();
    final chargesEnabled = userData['stripeChargesEnabled'] as bool?;
    final defaultPmBrand = (userData['stripeDefaultPmBrand'] as String?)?.trim();
    final defaultPmLast4 = (userData['stripeDefaultPmLast4'] as String?)?.trim();
    final bool hasCard = defaultPmLast4 != null && defaultPmLast4.isNotEmpty;

    // ===== Compañera (cobra) =====
    // Soporta ambos nombres por compat:
    final connectId = ((userData['stripeConnectAccountId'] ??
                userData['stripeAccountId']) ??
            '')
        .toString()
        .trim();

    final connectPayoutsEnabled = (userData['stripeConnectPayoutsEnabled'] ??
            userData['stripePayoutsEnabled']) ==
        true;

    final connectDetailsSubmitted =
        (userData['stripeConnectDetailsSubmitted'] ??
                userData['stripeDetailsSubmitted']) ==
            true;

    final bool isConnected = connectId.isNotEmpty;

    String statusPagosComoHablante() {
      if (stripeCustomerId == null || stripeCustomerId.isEmpty) {
        return 'Aún no tienes un método de pago registrado.';
      }
      final enabledText =
          chargesEnabled == true ? 'Cobros habilitados' : 'Cobros pendientes';

      if (defaultPmBrand != null &&
          defaultPmBrand.isNotEmpty &&
          defaultPmLast4 != null &&
          defaultPmLast4.isNotEmpty) {
        return '$enabledText • $defaultPmBrand • **** $defaultPmLast4';
      }
      return enabledText;
    }

    String statusCobrosComoCompanera() {
      if (!isConnected) return 'Aún no tienes una cuenta de cobro conectada.';
      if (connectPayoutsEnabled && connectDetailsSubmitted) {
        return '✅ Cuenta conectada y lista para recibir dinero.';
      }
      return '⚠️ Cuenta conectada, pero falta completar/verificar datos en Stripe.';
    }

    final bool noRoleDefined = !isSpeaker && !isCompanion;

    final List<Widget> children = [
      const SizedBox(height: 6),
      const Text(
        'Aquí administras pagos (hablante) y cobros (compañera).',
        style: TextStyle(fontSize: 14),
      ),
      const SizedBox(height: 16),
    ];

    // ============================================================
    // PAGOS COMO HABLANTE
    // ============================================================
    if (isSpeaker || noRoleDefined) {
      children.addAll([
        const Text(
          'Pagos como hablante',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Método de pago para tus sesiones como hablante.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.credit_card, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hasCard ? statusPagosComoHablante() : 'Sin tarjeta guardada.',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _setupSpeakerPaymentMethod,
                    child: const Text(
                      'Configurar método de pago',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ),

                if (hasCard) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _busy ? null : _removeSpeakerPaymentMethod,
                      child: const Text('Remover método de pago'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
      ]);
    }

    // ============================================================
    // COBROS COMO COMPAÑERA (STRIPE CONNECT)
    // ============================================================
    if (isCompanion || noRoleDefined) {
      children.addAll([
        const Text(
          'Cobros como compañera',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cuenta donde recibirás el dinero de tus sesiones.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.account_balance_wallet_outlined, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        statusCobrosComoCompanera(),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),

                if (isConnected) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Connect ID: $connectId',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.70),
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                // Botón principal: Conectar / Verificar
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            setState(() => _busy = true);
                            try {
                              final api = ConnectApi();

                              if (!isConnected) {
                                final url = await api.createOnboardingLink(
                                  returnUrl:
                                      'https://lissen-mvp.web.app/stripe-return',
                                  refreshUrl:
                                      'https://lissen-mvp.web.app/stripe-refresh',
                                );

                                final ok = await launchUrl(
                                  Uri.parse(url),
                                  mode: LaunchMode.externalApplication,
                                );
                                if (!ok) {
                                  throw Exception('No se pudo abrir el navegador.');
                                }

                                _snack(
                                    'Completa Stripe Connect en el navegador y regresa a la app.');
                              } else {
                                await api.getAccountStatus();
                                _snack('Estado actualizado ✅');
                              }
                            } catch (e) {
                              _snack('Stripe Connect: $e');
                            } finally {
                              if (mounted) setState(() => _busy = false);
                            }
                          },
                    child: Text(
                      isConnected
                          ? 'Verificar estado de cuenta'
                          : 'Conectar cuenta para recibir dinero',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ),

                // ✅ Botón secundario: Abrir panel Express
                if (isConnected) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              setState(() => _busy = true);
                              try {
                                final api = ConnectApi();
                                final url = await api.createExpressLoginLink();

                                final ok = await launchUrl(
                                  Uri.parse(url),
                                  mode: LaunchMode.externalApplication,
                                );
                                if (!ok) {
                                  throw Exception('No se pudo abrir el navegador.');
                                }
                              } catch (e) {
                                _snack('No se pudo abrir el panel: $e');
                              } finally {
                                if (mounted) setState(() => _busy = false);
                              }
                            },
                      child: const Text('Abrir panel de Stripe'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
      ]);
    }

    return ListView(
      key: const ValueKey('metodos_pago'),
      padding: const EdgeInsets.all(16),
      children: children,
    );
  }

  // ============================================================
  // SECCIÓN "HISTORIAL DE PAGOS"
  // ============================================================
  Widget _buildPaymentsHistory() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      key: const ValueKey('historial_pagos'),
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .collection('payments')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data?.docs ?? [];

        if (docs.isEmpty) {
          return const Center(
            child: Text(
              'No hay movimientos registrados.',
              style: TextStyle(fontSize: 15),
              textAlign: TextAlign.center,
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(height: 8),
          itemBuilder: (context, index) {
            final p = docs[index].data();

            final num amountCents = p['amountCents'] ?? 0;
            final String currency = (p['currency'] ?? 'MXN') as String;
            final String type = (p['type'] ?? 'sesión') as String;
            final String direction =
                (p['direction'] ?? 'payout') as String; // payout / charge
            final String status =
                (p['status'] ?? 'pendiente') as String; // pagado / pendiente

            final ts = p['createdAt'];
            DateTime? date;
            if (ts is Timestamp) date = ts.toDate();

            final sign = direction == 'charge' ? '-' : '+';
            final amount = amountCents / 100.0;

            final dateStr = date != null
                ? '${date.day.toString().padLeft(2, '0')}/'
                    '${date.month.toString().padLeft(2, '0')}/'
                    '${date.year}'
                : '';

            return ListTile(
              dense: true,
              leading: Icon(
                direction == 'charge' ? Icons.call_made : Icons.call_received,
                color: direction == 'charge' ? Colors.redAccent : Colors.green,
              ),
              title: Text(
                '$sign\$${amount.toStringAsFixed(2)} $currency',
                style: const TextStyle(fontSize: 15),
              ),
              subtitle: Text(
                '$type • $status${dateStr.isNotEmpty ? ' • $dateStr' : ''}',
                style: const TextStyle(fontSize: 12),
              ),
            );
          },
        );
      },
    );
  }
}
