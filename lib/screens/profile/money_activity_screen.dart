import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MoneyActivityScreen extends StatefulWidget {
  final String uid;

  const MoneyActivityScreen({super.key, required this.uid});

  @override
  State<MoneyActivityScreen> createState() => _MoneyActivityScreenState();
}

class _MoneyActivityScreenState extends State<MoneyActivityScreen> {
  // 0 = Métodos de pago (Stripe), 1 = Historial
  int _selectedTab = 0;

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
                        onPressed: () {
                          setState(() => _selectedTab = 0);
                        },
                        child: const Text('Métodos de pago'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() => _selectedTab = 1);
                        },
                        child: const Text('Historial de pagos'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
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
  // SECCIÓN "MÉTODOS DE PAGO" (estructura pensada para Stripe)
  // ============================================================
  Widget _buildStripeConfig(
    Map<String, dynamic> userData, {
    required bool isSpeaker,
    required bool isCompanion,
  }) {
    // Estos campos se llenarán desde tu backend cuando Stripe esté integrado.
    final stripeCustomerId = (userData['stripeCustomerId'] as String?)?.trim();
    final stripeAccountId = (userData['stripeAccountId'] as String?)?.trim();
    final chargesEnabled = userData['stripeChargesEnabled'] as bool?;
    final payoutsEnabled = userData['stripePayoutsEnabled'] as bool?;
    final defaultPmBrand = (userData['stripeDefaultPmBrand'] as String?)?.trim();
    final defaultPmLast4 = (userData['stripeDefaultPmLast4'] as String?)?.trim();

    String _statusPagosComoHablante() {
      if (stripeCustomerId == null || stripeCustomerId.isEmpty) {
        return 'Aún no tienes un método de pago registrado.';
      }
      final enabledText =
          chargesEnabled == true ? 'Cobros habilitados' : 'Cobros pendientes';
      if (defaultPmBrand != null && defaultPmLast4 != null) {
        return '$enabledText • $defaultPmBrand • **** $defaultPmLast4';
      }
      return enabledText;
    }

    String _statusCobrosComoCompanera() {
      if (stripeAccountId == null || stripeAccountId.isEmpty) {
        return 'Aún no tienes una cuenta de cobro conectada.';
      }
      final payoutsText =
          payoutsEnabled == true ? 'Retiros habilitados' : 'Retiros pendientes';
      return '$payoutsText • Cuenta conectada: $stripeAccountId';
    }

    final bool noRoleDefined = !isSpeaker && !isCompanion;

    final List<Widget> children = [
      const Text(
        'Desde aquí vas a manejar tus cobros y pagos reales. '
        'Cuando conectemos Stripe, esta pantalla usará estos mismos bloques '
        'para mostrar tu información actualizada.',
        style: TextStyle(fontSize: 14),
      ),
      const SizedBox(height: 16),
    ];

    // PAGOS COMO HABLANTE
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
                        stripeCustomerId == null || stripeCustomerId.isEmpty
                            ? 'Sin tarjeta guardada.'
                            : _statusPagosComoHablante(),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'La conexión con Stripe se activará en una etapa posterior.',
                          ),
                        ),
                      );
                    },
                    child: const Text(
                      'Configurar método de pago',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
      ]);
    }

    // COBROS COMO COMPAÑERA
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
                        _statusCobrosComoCompanera(),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'La conexión de cuenta para recibir dinero se activará cuando Stripe esté integrado.',
                          ),
                        ),
                      );
                    },
                    child: const Text(
                      'Conectar cuenta para recibir dinero',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
      ]);
    }

    children.add(
      const Text(
        'Cuando Stripe esté listo, estos mismos botones abrirán las pantallas '
        'oficiales para agregar tu tarjeta o conectar tu cuenta bancaria.',
        style: TextStyle(fontSize: 12),
      ),
    );

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
