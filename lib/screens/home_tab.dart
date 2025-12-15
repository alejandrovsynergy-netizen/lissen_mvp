import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/companion_schedule_and_rates_block.dart';

import '../features/sessions/ui/session_screen.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  bool _historyExpanded = false;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Center(
        child: Text('Debes iniciar sesión para ver tus sesiones.'),
      );
    }

    final uid = user.uid;

    // 🔹 Antes filtrabas por 'participants', pero las sesiones nuevas no lo tienen.
    // 🔹 Traemos todas las sesiones y filtramos en Dart por speakerId/companionId/participants.
    final sessionsStream = FirebaseFirestore.instance
        .collection('sessions')
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: sessionsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error leyendo sesiones: ${snapshot.error}',
              textAlign: TextAlign.center,
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final rawDocs = snapshot.data?.docs ?? [];

        // 🔹 Aquí filtramos SOLO las sesiones donde participa este usuario
        final allDocs = rawDocs.where((doc) {
          final d = doc.data();
          final speakerId = d['speakerId'] as String? ?? '';
          final companionId = d['companionId'] as String? ?? '';
          final participants =
              (d['participants'] as List<dynamic>?)?.cast<String>() ?? const [];

          return speakerId == uid ||
              companionId == uid ||
              participants.contains(uid);
        }).toList();

        // 1) Separar activas e historial
        final activeSessions = allDocs.where((doc) {
          final d = doc.data();
          final status = d['status'] as String? ?? 'active';
          return status == 'active';
        }).toList();

        final historySessions = allDocs.where((doc) {
          final d = doc.data();
          final status = d['status'] as String? ?? '';
          return status == 'completed' || status == 'cancelled';
        }).toList();

        historySessions.sort((a, b) {
          final ad = a.data()['completedAt'];
          final bd = b.data()['completedAt'];
          if (ad == null || bd == null) return 0;
          return (bd as Timestamp).compareTo(ad as Timestamp);
        });

        // 2) Resumen como compañera (solo cuando tú eres companionId y la sesión está completada)
        int totalSessionsAsCompanion = 0;
        int totalBillingMinutes = 0;
        int totalAmountCents = 0;

        for (final doc in historySessions) {
          final data = doc.data();
          final companionId = data['companionId'] as String? ?? '';
          final status = data['status'] as String? ?? '';

          if (companionId != uid || status != 'completed') continue;

          totalSessionsAsCompanion++;

          final durationMinutes = data['durationMinutes'] as int? ?? 0;
          final billingMinutes =
              data['billingMinutes'] as int? ?? durationMinutes;
          final priceCents = data['priceCents'] as int? ?? 0;

          if (durationMinutes > 0 && billingMinutes > 0 && priceCents > 0) {
            final sessionAmount =
                (priceCents * billingMinutes ~/ durationMinutes);
            totalAmountCents += sessionAmount;
            totalBillingMinutes += billingMinutes;
          }
        }

        final totalAmountUsd = totalAmountCents / 100.0;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ================================================================
            // 🔸 Resumen como compañera (si aplica)
            // ================================================================
            if (totalSessionsAsCompanion > 0) ...[
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.account_balance_wallet, size: 18),
                          SizedBox(width: 6),
                          Text(
                            "Resumen como compañera (simulado)",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Sesiones completadas: $totalSessionsAsCompanion",
                        style: const TextStyle(fontSize: 13),
                      ),
                      Text(
                        "Minutos facturados: $totalBillingMinutes min",
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Total estimado a recibir: \$${totalAmountUsd.toStringAsFixed(2)} USD",
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "Solo referencia interna (sin Stripe ni comisiones).",
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // ================================================================
            // 🔵 Sesiones activas
            // ================================================================
            Row(
              children: const [
                Icon(Icons.bolt, color: Colors.amber, size: 20),
                SizedBox(width: 6),
                Text(
                  "Sesiones activas",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),

            if (activeSessions.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white10,
                ),
                child: const Text(
                  "No tienes sesiones activas.\nAcepta o crea una oferta para comenzar.",
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              )
            else
              Column(
                children: [
                  for (final doc in activeSessions)
                    _buildActiveSessionCard(doc, uid),
                ],
              ),

            const SizedBox(height: 24),

            // ================================================================
            // 🔥 Historial (colapsable)
            // ================================================================
            GestureDetector(
              onTap: () {
                setState(() => _historyExpanded = !_historyExpanded);
              },
              child: Row(
                children: [
                  const Icon(
                    Icons.history,
                    color: Colors.lightBlueAccent,
                    size: 20,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    "Historial",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Text(
                    historySessions.isEmpty
                        ? ""
                        : "${historySessions.length} sesión${historySessions.length == 1 ? '' : 'es'}",
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _historyExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 26,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),

            AnimatedCrossFade(
              duration: const Duration(milliseconds: 250),
              crossFadeState: _historyExpanded
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              firstChild: historySessions.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        "No hay sesiones finalizadas todavía.",
                        style: TextStyle(color: Colors.grey.shade400),
                      ),
                    )
                  : Column(
                      children: [
                        const SizedBox(height: 10),
                        for (final doc in historySessions)
                          _buildHistoryCard(doc, uid),
                      ],
                    ),
              secondChild: const SizedBox.shrink(),
            ),
          ],
        );
      },
    );
  }

  // ================================================================
  // 🔵 Tarjeta de sesión activa
  // ================================================================
  Widget _buildActiveSessionCard(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    String uid,
  ) {
    final data = doc.data();

    final speakerAlias = data['speakerAlias'] ?? 'Hablante';
    final companionAlias = data['companionAlias'] ?? 'Compañera';
    final duration = data['durationMinutes'] ?? 30;
    final priceCents = data['priceCents'] ?? 0;
    final currency = data['currency'] ?? 'usd';

    final price = priceCents / 100.0;
    final isSpeaker = data['speakerId'] == uid;
    final otherAlias = isSpeaker ? companionAlias : speakerAlias;

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: CircleAvatar(
          radius: 18,
          child: Text(
            otherAlias.isNotEmpty ? otherAlias[0].toUpperCase() : '?',
          ),
        ),
        title: Text(
          otherAlias,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        subtitle: Text(
          "Reservada: $duration min • Estado: Activa",
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              "\$${price.toStringAsFixed(2)} ${currency.toUpperCase()}",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              isSpeaker ? 'Eres hablante' : 'Eres compañera',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SessionConversationScreen(sessionId: doc.id),
            ),
          );
        },
      ),
    );
  }

  // ================================================================
  // 🔥 Tarjeta de historial
  // ================================================================
  Widget _buildHistoryCard(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    String uid,
  ) {
    final data = doc.data();

    final speakerAlias = data['speakerAlias'] ?? 'Hablante';
    final companionAlias = data['companionAlias'] ?? 'Compañera';

    final real = data['realDurationMinutes'] ?? 0;
    final billed = data['billingMinutes'] ?? 0;

    final endedBy = data['endedBy'] as String?;
    final status = data['status'] ?? 'completed';

    final priceCents = data['priceCents'] ?? 0;
    final currency = data['currency'] ?? 'usd';

    final price = priceCents / 100.0;
    final isSpeaker = data['speakerId'] == uid;
    final otherAlias = isSpeaker ? companionAlias : speakerAlias;

    String statusLabel = "Finalizada";
    Color statusColor = Colors.greenAccent;

    if (status == 'cancelled') {
      statusLabel = "Cancelada";
      statusColor = Colors.redAccent;
    } else {
      if (endedBy == 'speaker') {
        statusLabel = "Finalizada por hablante";
      } else if (endedBy == 'companion') {
        statusLabel = "Finalizada por compañera";
      } else if (endedBy == 'timeout') {
        statusLabel = "Finalizada por tiempo";
        statusColor = Colors.greenAccent;
      } else {
        statusLabel = "Finalizada";
      }
    }

    return Card(
      color: Colors.white10,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: CircleAvatar(
          radius: 18,
          child: Text(
            otherAlias.isNotEmpty ? otherAlias[0].toUpperCase() : '?',
          ),
        ),
        title: Text(
          otherAlias,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              "Real: $real min • Cobro: $billed min",
              style: const TextStyle(fontSize: 11),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(fontSize: 10, color: statusColor),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isSpeaker ? 'Fuiste hablante' : 'Fuiste compañera',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
        trailing: Text(
          "\$${price.toStringAsFixed(2)} ${currency.toUpperCase()}",
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SessionConversationScreen(sessionId: doc.id),
            ),
          );
        },
      ),
    );
  }
}
