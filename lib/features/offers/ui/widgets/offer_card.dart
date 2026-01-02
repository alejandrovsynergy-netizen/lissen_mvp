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

  final bool allowTake;
  final String? takeBlockedMessage;
  final Set<String> blockedUserIds;

  final Future<void> Function({
    required String offerId,
    required Map<String, dynamic> offerData,
    required String currentUserId,
    required String currentUserAlias,
  }) onTakeOffer;

  final void Function(String offerId, Map<String, dynamic> offerData)? onEdit;
  final Future<void> Function(String offerId)? onDelete;
  final Future<void> Function(String offerId, Map<String, dynamic> offerData)?
      onRejectWithCode;
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
    this.allowTake = true,
    this.takeBlockedMessage,
    this.blockedUserIds = const {},
    required this.onTakeOffer,
    this.onEdit,
    this.onDelete,
    this.onRejectWithCode,
    this.onSpeakerPendingDecision,
  });

  @override
  Widget build(BuildContext context) {
    final speakerId = (data['speakerId'] ?? '').toString().trim();
    if (speakerId.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future:
          FirebaseFirestore.instance.collection('users').doc(speakerId).get(),
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final blockedByMe = blockedUserIds.contains(speakerId);
    final blockedBySpeaker = (profile?['blockedUsers'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .contains(currentUserId) ==
        true;
    if (blockedByMe || blockedBySpeaker) {
      return const SizedBox.shrink();
    }

    // ===== Colores "preview" (solo visual) =====
    const cyan = Color(0xFF22D3EE);
    const blue = Color(0xFF3B82F6);
    const cyan2 = Color(0xFF06B6D4);

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
    final currency = (data['currency'] ?? 'usd').toString().toUpperCase();

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
    final companionCode = (data['companionCode'] ?? '').toString().trim();
    final hasCompanionCode = companionCode.isNotEmpty;

    final canTake = !isSpeaker && !isProcessing && allowTake;
    final status = (data['status'] ?? 'active').toString();
    final isPaymentRequired = isSpeaker && status == 'payment_required';
    final canRejectWithCode = !isSpeaker &&
        !isProcessing &&
        hasCompanionCode &&
        onRejectWithCode != null;

    final showTakeBlocked = !isSpeaker && !isProcessing && !allowTake &&
        (takeBlockedMessage ?? '').isNotEmpty;


    // ✅ Contraste: borde + fondo de card (sin Colors.grey hardcodeado)
    final borderColor = isPaymentRequired
        ? Colors.redAccent.withOpacity(0.65)
        : isPendingForSpeaker
            ? cs.primary.withOpacity(0.55)
            : cyan.withOpacity(0.22);

    // Fondo tipo glass / night
    final cardFill = cs.surface.withOpacity(0.62);

    return Container(
      decoration: BoxDecoration(
        color: cardFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          if (hasCompanionCode)
            BoxShadow(
              color: cyan.withOpacity(0.45),
              blurRadius: 26,
              spreadRadius: 1,
              offset: const Offset(0, 8),
            ),
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ==========================================================
            // HEADER (gradiente cyan/azul como preview)
            // ==========================================================
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [cyan, blue, cyan2],
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'OFERTA',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white.withOpacity(0.95),
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.7,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '\$${price.toStringAsFixed(2)} $currency',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Menú (misma lógica)
                  if (isSpeaker)
                    Theme(
                      data: theme.copyWith(
                        popupMenuTheme: PopupMenuThemeData(
                          color: cs.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: cyan.withOpacity(0.20),
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                      child: PopupMenuButton<String>(
                        icon: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.22),
                              width: 1,
                            ),
                          ),
                          child: const Icon(
                            Icons.more_vert,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        onSelected: (v) {
                          if (v == 'edit' && onEdit != null) {
                            onEdit!(docId, data);
                          } else if (v == 'delete' && onDelete != null) {
                            onDelete!(docId);
                          } else if (v == 'decision' &&
                              onSpeakerPendingDecision != null) {
                            onSpeakerPendingDecision!(docId, data);
                          }
                        },
                        itemBuilder: (_) => [
                          if (isPendingForSpeaker &&
                              onSpeakerPendingDecision != null)
                            const PopupMenuItem(
                              value: 'decision',
                              child: Text('Ver solicitud'),
                            ),
                          const PopupMenuItem(
                              value: 'edit', child: Text('Editar')),
                          const PopupMenuItem(
                              value: 'delete', child: Text('Eliminar')),
                        ],
                      ),
                    )
                  else
                    const SizedBox(width: 4),
                ],
              ),
            ),

            // ==========================================================
            // BODY
            // ==========================================================
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Título (mantengo tu title pero más compacto)
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                    ),
                  ),
                  if (isPaymentRequired) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.redAccent.withOpacity(0.35)),
                      ),
                      child: Text(
                        'Necesitas ingresar método de pago para publicar esta oferta.',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],

                  if (isPendingForSpeaker) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: cs.primary.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: cs.primary.withOpacity(0.35)),
                      ),
                      child: Text(
                        'Solicitud pendiente',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 10),

                  // Perfil (mismo onTap)
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
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
                        // Avatar con gradiente tipo preview
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [cyan, Color(0xFF60A5FA), Color(0xFF818CF8)],
                            ),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.28),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.28),
                                blurRadius: 16,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: photoUrl.isNotEmpty
                                  ? Image.network(
                                      photoUrl,
                                      fit: BoxFit.cover,
                                    )
                                  : Center(
                                      child: Text(
                                        alias.isNotEmpty
                                            ? alias.trim()[0].toUpperCase()
                                            : '?',
                                        style: theme.textTheme.labelLarge
                                            ?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                alias,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: cs.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                age != null
                                    ? '$age años • $genderLabel'
                                    : genderLabel,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: cyan.withOpacity(0.80),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: cyan.withOpacity(0.90),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Separador sutil
                  Container(
                    height: 1,
                    width: double.infinity,
                    color: cyan.withOpacity(0.18),
                  ),

                  const SizedBox(height: 10),

                  // Detalles (mismo contenido, estilo tipo preview)
                  _DetailRow(
                    icon: '⏱',
                    text: 'Duración estimada: $duration min • $typeLabel',
                  ),
                  if (category.isNotEmpty)
                    _DetailRow(
                      icon: '💬',
                      text: 'Tema de conversación: ${_labelCategory(category)}',
                    ),
                  if (tone.isNotEmpty)
                    _DetailRow(
                      icon: '✨',
                      text: 'Estilo de conversación: ${_labelTone(tone)}',
                    ),

                  if (hasCompanionCode) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: cyan.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: cyan.withOpacity(0.40)),
                        boxShadow: [
                          BoxShadow(
                            color: cyan.withOpacity(0.55),
                            blurRadius: 18,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Text(
                        'Codigo de companera: $companionCode',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cyan.withOpacity(0.95),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],

                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onBackground.withOpacity(0.82),
                        height: 1.25,
                      ),
                    ),
                  ],

                  if (location.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 16,
                          color: cyan.withOpacity(0.90),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: cyan.withOpacity(0.80),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  if (showTakeBlocked) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.redAccent.withOpacity(0.35),
                        ),
                      ),
                      child: Text(
                        takeBlockedMessage ??
                            'Conecta tu cuenta de Stripe para poder tomar ofertas.',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                  if (canTake) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF10B981), Color(0xFF059669)],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF10B981).withOpacity(0.30),
                              blurRadius: 20,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
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
                              : const Text(
                                  'Aceptar conversación',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                  if (canRejectWithCode) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          onRejectWithCode!(docId, data);
                        },
                        child: const Text('Rechazar'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// SOLO VISUAL. No toca lógica.
// ============================================================================
class _DetailRow extends StatelessWidget {
  final String icon;
  final String text;

  const _DetailRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    const cyan = Color(0xFF22D3EE);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            icon,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cyan.withOpacity(0.95),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onBackground.withOpacity(0.92),
                fontWeight: FontWeight.w800,
                height: 1.15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
