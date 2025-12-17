import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../explorer/ui/public_profile_screen.dart';

class OfferCard extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final bool isSpeaker;
  final bool isPendingForSpeaker;
  final String currentUserId;
  final String currentUserAlias;
  final bool isProcessing;

  final Future<void> Function({
    required String offerId,
    required Map<String, dynamic> offerData,
    required String currentUserId,
    required String currentUserAlias,
  }) onTakeOffer;

  final void Function(String offerId, Map<String, dynamic> offerData)? onEdit;
  final Future<void> Function(String offerId)? onDelete;
  final Future<void> Function(String offerId, Map<String, dynamic> offerData)?
      onSpeakerPendingDecision;

  const OfferCard({
    super.key,
    required this.docId,
    required this.data,
    required this.isSpeaker,
    required this.isPendingForSpeaker,
    required this.currentUserId,
    required this.currentUserAlias,
    required this.isProcessing,
    required this.onTakeOffer,
    this.onEdit,
    this.onDelete,
    this.onSpeakerPendingDecision,
  });

  @override
  Widget build(BuildContext context) {
    final speakerId = (data['speakerId'] ?? '').toString().trim();
    if (speakerId.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('users').doc(speakerId).get(),
      builder: (context, snapshot) {
        final profile = snapshot.data?.data();
        return _buildCard(context, profile, speakerId);
      },
    );
  }

  // ===== Etiquetas con emoji =====
  String _labelCategory(String raw) {
    switch (raw) {
      case 'vida_diaria':
        return '🏠 Vida diaria';
      case 'relaciones_familia':
        return '❤️ Relaciones y familia';
      case 'trabajo_dinero':
        return '💼 Trabajo y dinero';
      case 'estudios_futuro':
        return '📚 Estudios y futuro';
      case 'metas_proyectos':
        return '🎯 Metas y proyectos';
      case 'hobbies_entretenimiento':
        return '🎮 Hobbies y entretenimiento';
      default:
        return raw.replaceAll('_', ' ');
    }
  }

  String _labelTone(String raw) {
    switch (raw) {
      case 'relajada_cercana':
        return '😌 Relajada y cercana';
      case 'directa':
        return '⚡ Directa y sin rodeos';
      case 'motivadora':
        return '🚀 Motivadora';
      case 'escucha_tranquila':
        return '👂 Escucha tranquila';
      case 'analitica':
        return '🧠 Analítica';
      case 'humor_ligero':
        return '😄 Humor ligero';
      default:
        return raw.replaceAll('_', ' ');
    }
  }

  Widget _buildCard(
    BuildContext context,
    Map<String, dynamic>? profile,
    String speakerId,
  ) {
    final alias =
        (profile?['alias'] ?? data['speakerAlias'] ?? 'Anónimo').toString();
    final age = (profile?['age'] as num?)?.toInt();
    final gender = (profile?['gender'] ?? '').toString().toLowerCase();
    final photoUrl =
        (profile?['photoUrl'] ?? profile?['profilePhotoUrl'] ?? '')
            .toString()
            .trim();

    final genderLabel =
        gender == 'hombre' ? 'Hombre' : gender == 'mujer' ? 'Mujer' : '—';

    final title = (data['title'] ?? 'Oferta').toString();
    final description = (data['description'] ?? '').toString();

    final int cents =
        (data['priceCents'] ?? data['totalMinAmountCents'] ?? 0) as int;
    final price = cents / 100.0;
    final currency =
        (data['currency'] ?? 'usd').toString().toUpperCase();

    final duration =
        (data['durationMinutes'] ?? data['minMinutes'] ?? 30) as int;

    final type = (data['communicationType'] ?? 'chat').toString();
    final typeLabel =
        type == 'voice' ? 'Llamada' : type == 'video' ? 'Video' : 'Chat';

    final category = (data['category'] ?? '').toString();
    final tone = (data['tone'] ?? '').toString();

    final city = (data['speakerCity'] ?? '').toString();
    final country = (data['speakerCountry'] ?? '').toString();
    final location = [city, country].where((e) => e.isNotEmpty).join(', ');

    final canTake = !isSpeaker && !isProcessing;

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '\$${price.toStringAsFixed(2)} $currency',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (isSpeaker)
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit' && onEdit != null) {
                        onEdit!(docId, data);
                      } else if (v == 'delete' && onDelete != null) {
                        onDelete!(docId);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Editar')),
                      PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                    ],
                  ),
              ],
            ),

            const SizedBox(height: 8),

            // Perfil
            InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        PublicProfileScreen(companionUid: speakerId),
                  ),
                );
              },
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundImage:
                        photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                    child: photoUrl.isEmpty
                        ? const Icon(Icons.person, size: 20)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        alias,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        age != null ? '$age años • $genderLabel' : genderLabel,
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Texto descriptivo
            Text(
              'Duración estimada: $duration min • $typeLabel',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            if (category.isNotEmpty)
              Text(
                'Tema de conversación: ${_labelCategory(category)}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            if (tone.isNotEmpty)
              Text(
                'Estilo de conversación: ${_labelTone(tone)}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),

            if (description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],

            if (location.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.location_on, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    location,
                    style:
                        const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ],

            if (canTake) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    onTakeOffer(
                      offerId: docId,
                      offerData: data,
                      currentUserId: currentUserId,
                      currentUserAlias: currentUserAlias,
                    );
                  },
                  child: isProcessing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Aceptar conversación'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
