import 'dart:math';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'waiting_for_speaker_screen.dart';
import 'create_offer_dialog.dart';
import '../features/sessions/ui/session_screen.dart';
import 'incoming_companion_dialog.dart';
import '../features/offers/data/offers_service.dart';
import '../features/offers/ui/widgets/filter_dropdown.dart';
import '../features/offers/ui/widgets/offer_card.dart';
import '../features/offers/ui/utils/offers_utils.dart';

class OffersPage extends StatefulWidget {
  const OffersPage({super.key});

  @override
  State<OffersPage> createState() => _OffersPageState();
}

class _OffersPageState extends State<OffersPage> {
  bool _busy = false;
  String? _processingOfferId;

  // ============================
  // Streams estabilizados
  // ============================
  User? _user;
  DocumentReference<Map<String, dynamic>>? _userRef;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _userStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _offersStream;

  // ============================
  // Filtros (solo compañeras)
  // ============================
  String _amountSort = 'high'; // high | low
  String _distanceSort = 'near'; // near | far

  @override
  void initState() {
    super.initState();

    _user = FirebaseAuth.instance.currentUser;

    if (_user != null) {
      _userRef = FirebaseFirestore.instance.collection('users').doc(_user!.uid);
      _userStream = _userRef!.snapshots();
    }

    // Este stream ya no se recrea en cada build
    _offersStream = FirebaseFirestore.instance.collection('offers').snapshots();
  }

  // ============================
  // Cálculo de distancia en km
  // ============================

  double? _offerDistanceForDoc({
    required Map<String, dynamic> offerData,
    required double? userLat,
    required double? userLng,
  }) {
    final double? offerLat = (offerData['locationCenterLat'] as num?)?.toDouble();
    final double? offerLng = (offerData['locationCenterLng'] as num?)?.toDouble();

    if (userLat == null || userLng == null || offerLat == null || offerLng == null) {
      return null;
    }
    return distanceKm(userLat, userLng, offerLat, offerLng);
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    if (user == null) {
      return const Center(child: Text('Debes iniciar sesión.'));
    }

    final userStream = _userStream;
    if (userStream == null) {
      return const Center(child: Text('No se encontró tu perfil.'));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userStream,
      builder: (context, userSnap) {
        if (userSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!userSnap.hasData || !userSnap.data!.exists) {
          return const Center(child: Text('No se encontró tu perfil.'));
        }

        final userData = userSnap.data!.data() ?? {};
        final role = (userData['role'] as String?) ?? 'speaker';
        final alias = (userData['alias'] as String?) ?? 'Usuario';
        final country = (userData['country'] as String?) ?? '';
        final city = (userData['city'] as String?) ?? '';
        final companionCodeUser = (userData['companionCode'] ?? '').toString().trim();

        // género y geolocalización de la compañera
        final userGender = (userData['gender'] as String?)?.toLowerCase() ?? '';
        final double? userLat = (userData['geoLat'] as num?)?.toDouble();
        final double? userLng = (userData['geoLng'] as num?)?.toDouble();

        final isSpeaker = role == 'speaker';
        final currentUserId = user.uid;

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _offersStream, // ✅ stream estable
          builder: (context, offerSnap) {
            if (offerSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!offerSnap.hasData) {
              return const Center(child: Text('No se pudieron leer ofertas.'));
            }

            final allDocs = offerSnap.data!.docs;

            // ==============================
            // FILTRADO POR ROL / REGLAS
            // ==============================
            List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

            if (isSpeaker) {
              // Hablante: solo SUS ofertas activas o pendientes
              docs = allDocs.where((doc) {
                final data = doc.data();
                final status = (data['status'] ?? 'active') as String;
                final speakerId = (data['speakerId'] ?? '') as String;

                if (speakerId != currentUserId) return false;
                return status == 'active' || status == 'pending_speaker';
              }).toList();
            } else {
              // ==============================
              // COMPAÑERA: filtros
              // ==============================
              final List<QueryDocumentSnapshot<Map<String, dynamic>>> candidates = [];

              for (final doc in allDocs) {
                final data = doc.data();
                final status = (data['status'] ?? 'active') as String;
                final speakerId = (data['speakerId'] ?? '') as String;
                final offerCompanionCode = (data['companionCode'] ?? '').toString().trim();

                // Estado y dueño
                if (status != 'active') continue;
                if (speakerId.isEmpty || speakerId == currentUserId) {
                  continue;
                }

                // Privacidad: pública vs privada con código
                if (offerCompanionCode.isNotEmpty) {
                  if (companionCodeUser.isEmpty || companionCodeUser != offerCompanionCode) {
                    continue;
                  }
                }

                // Filtro de género objetivo
                final targetGender = (data['targetGender'] ?? 'todos').toString().toLowerCase();
                bool genderOk = true;

                if (targetGender == 'hombre') {
                  genderOk = userGender == 'hombre';
                } else if (targetGender == 'mujer') {
                  genderOk = userGender == 'mujer';
                } else {
                  genderOk = true;
                }

                if (!genderOk) continue;

                candidates.add(doc);
              }

              // Mostramos todas las candidatas; el orden lo controlan los filtros
              docs = candidates;

              // ==============================
              // ORDENAMIENTO (montos + cercanía + empate por quien publicó primero)
              // ==============================
              final Map<String, double?> distCache = {};

              double? distOf(QueryDocumentSnapshot<Map<String, dynamic>> d) {
                if (distCache.containsKey(d.id)) return distCache[d.id];
                final v = _offerDistanceForDoc(
                  offerData: d.data(),
                  userLat: userLat,
                  userLng: userLng,
                );
                distCache[d.id] = v;
                return v;
              }

              docs.sort((a, b) {
                final aData = a.data();
                final bData = b.data();

                // 1) Montos
                final aCents = priceCents(aData);
                final bCents = priceCents(bData);

                int cmpAmount = 0;
                if (_amountSort == 'high') {
                  cmpAmount = bCents.compareTo(aCents); // desc
                } else {
                  cmpAmount = aCents.compareTo(bCents); // asc
                }
                if (cmpAmount != 0) return cmpAmount;

                // 2) Cercanía (si hay datos)
                final aDist = distOf(a);
                final bDist = distOf(b);

                // null siempre al final
                if (aDist == null && bDist != null) return 1;
                if (aDist != null && bDist == null) return -1;
                if (aDist != null && bDist != null) {
                  int cmpDist = 0;
                  if (_distanceSort == 'near') {
                    cmpDist = aDist.compareTo(bDist); // asc
                  } else {
                    cmpDist = bDist.compareTo(aDist); // desc
                  }
                  if (cmpDist != 0) return cmpDist;
                }

                // 3) Empate: quien publicó primero (createdAt asc)
                final aCreated = createdAtMs(aData);
                final bCreated = createdAtMs(bData);
                final cmpCreated = aCreated.compareTo(bCreated);
                if (cmpCreated != 0) return cmpCreated;

                // 4) Último desempate estable
                return a.id.compareTo(b.id);
              });
            }

            final screenH = MediaQuery.of(context).size.height;

            return Scaffold(
              floatingActionButton: isSpeaker
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 80),
                      child: FloatingActionButton(
                        onPressed: () {
                          if (_busy) return;

                          final hasActiveOffer = allDocs.any((d) {
                            final data = d.data();
                            final speakerId = (data['speakerId'] ?? '').toString().trim();
                            final status = (data['status'] ?? 'active').toString();

                            if (speakerId != currentUserId) return false;
                            return status == 'active' || status == 'pending_speaker';
                          });

                          if (hasActiveOffer) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Solo puedes tener 1 oferta activa a la vez.\n'
                                  'Edita o elimina tu oferta actual para crear otra.',
                                ),
                              ),
                            );
                            return;
                          }

                          showCreateOfferDialog(
                            context: context,
                            userId: currentUserId,
                            alias: alias,
                            country: country,
                            city: city,
                          );
                        },
                        child: const Icon(Icons.add),
                      ),
                    )
                  : null,
              body: SafeArea(
                child: isSpeaker
                    ? CustomScrollView(
                        slivers: [
                          SliverToBoxAdapter(
                            child: SizedBox(height: screenH * 0.125),
                          ),
                          const SliverToBoxAdapter(
                            child: Center(
                              child: Text(
                                'Mis ofertas',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: SizedBox(height: screenH * 0.12),
                          ),
                          if (docs.isEmpty)
                            const SliverFillRemaining(
                              hasScrollBody: false,
                              child: Center(
                                child: Text(
                                  'Aún no tienes ofertas.\nCrea una para comenzar.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          else
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 0,
                              ),
                              sliver: SliverList.separated(
                                itemCount: docs.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final doc = docs[index];
                                  final data = doc.data();
                                  final status = (data['status'] ?? 'active') as String;

                                  final isPendingForSpeaker =
                                      status == 'pending_speaker' &&
                                      (data['pendingSpeakerId'] ?? '') == currentUserId;

                                  return Align(
                                    alignment: Alignment.topCenter,
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 520),
                                      child: OfferCard(
                                        docId: doc.id,
                                        data: data,
                                        isSpeaker: true,
                                        isPendingForSpeaker: isPendingForSpeaker,
                                        currentUserId: currentUserId,
                                        currentUserAlias: alias,
                                        isProcessing: _busy && _processingOfferId == doc.id,
                                        onTakeOffer: _handleCompanionTakeOffer,
                                        onEdit: (offerId, offerData) {
                                          _handleEditOffer(
                                            offerId: offerId,
                                            offerData: offerData,
                                            userId: currentUserId,
                                            alias: alias,
                                            country: country,
                                            city: city,
                                          );
                                        },
                                        onDelete: (offerId) => _handleDeleteOffer(offerId),
                                        onSpeakerPendingDecision: isPendingForSpeaker
                                            ? (offerId, offerData) => _handleSpeakerPendingDecision(
                                                  offerId: offerId,
                                                  offerData: offerData,
                                                )
                                            : null,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                        ],
                      )
                    : CustomScrollView(
                        slivers: [
                          const SliverToBoxAdapter(child: SizedBox(height: 28)),
                          const SliverToBoxAdapter(
                            child: Center(
                              child: Text(
                                'Ofertas disponibles',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 12)),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: FilterDropdown(
                                      label: 'Montos',
                                      value: _amountSort,
                                      items: const [
                                        DropdownMenuItem(
                                          value: 'high',
                                          child: Text('Mayores primero'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'low',
                                          child: Text('Menores primero'),
                                        ),
                                      ],
                                      onChanged: (v) {
                                        if (v == null) return;
                                        setState(() => _amountSort = v);
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: FilterDropdown(
                                      label: 'Cercanía',
                                      value: _distanceSort,
                                      items: const [
                                        DropdownMenuItem(
                                          value: 'near',
                                          child: Text('Más cercanas primero'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'far',
                                          child: Text('Más lejanas primero'),
                                        ),
                                      ],
                                      onChanged: (v) {
                                        if (v == null) return;
                                        setState(() => _distanceSort = v);
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 12)),
                          if (docs.isEmpty)
                            const SliverFillRemaining(
                              hasScrollBody: false,
                              child: Center(
                                child: Text(
                                  'No hay ofertas disponibles en este momento.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          else
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              sliver: SliverList.separated(
                                itemCount: docs.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final doc = docs[index];
                                  final data = doc.data();

                                  final isPendingForSpeaker = false;

                                  return Align(
                                    alignment: Alignment.topCenter,
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 520),
                                      child: OfferCard(
                                        docId: doc.id,
                                        data: data,
                                        isSpeaker: false,
                                        isPendingForSpeaker: isPendingForSpeaker,
                                        currentUserId: currentUserId,
                                        currentUserAlias: alias,
                                        isProcessing: _busy && _processingOfferId == doc.id,
                                        onTakeOffer: _handleCompanionTakeOffer,
                                        onEdit: null,
                                        onDelete: null,
                                        onSpeakerPendingDecision: null,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _handleCompanionTakeOffer({
    required String offerId,
    required Map<String, dynamic> offerData,
    required String currentUserId,
    required String currentUserAlias,
  }) async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _processingOfferId = offerId;
    });

    try {
      final speakerId = (offerData['speakerId'] ?? '') as String;
      final speakerAlias = (offerData['speakerAlias'] ?? 'Hablante').toString();

      if (speakerId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Oferta inválida (sin hablante).')),
          );
        }
        return;
      }

      await OffersService().companionTakeOffer(
        offerId: offerId,
        speakerId: speakerId,
        currentUserId: currentUserId,
        currentUserAlias: currentUserAlias,
      );

      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => WaitingForSpeakerScreen(
            offerId: offerId,
            speakerAlias: speakerAlias,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al tomar oferta: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _processingOfferId = null;
        });
      }
    }
  }

  Future<void> _handleSpeakerPendingDecision({
    required String offerId,
    required Map<String, dynamic> offerData,
  }) async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _processingOfferId = offerId;
    });

    try {
      final companionUserId = (offerData['pendingCompanionId'] ?? '').toString().trim();

      final companionAlias = (offerData['pendingCompanionAlias'] ?? 'Alguien').toString();
      final durationMinutes =
          (offerData['durationMinutes'] ?? offerData['minMinutes'] ?? 30) as int;
      final int rawPriceCents =
          (offerData['priceCents'] ?? offerData['totalMinAmountCents'] ?? 0) as int;
      final double amount = rawPriceCents <= 0 ? 0.0 : rawPriceCents / 100.0;
      final currency = (offerData['currency'] ?? 'usd').toString().toUpperCase();
      final communicationType = (offerData['communicationType'] ?? 'chat').toString();

      final decision = await showIncomingCompanionDialog(
        context: context,
        companionAlias: companionAlias,
        durationMinutes: durationMinutes,
        amountUsd: amount,
        currency: currency,
        communicationType: communicationType,
        companionUid: companionUserId,
      );

      if (decision == true) {
        await _acceptPendingCompanion(offerId);
      } else if (decision == false) {
        await _rejectPendingCompanion(offerId);
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _processingOfferId = null;
        });
      }
    }
  }

  Future<void> _acceptPendingCompanion(String offerId) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    final uid = currentUser.uid;

    try {
      final result = await OffersService().acceptPendingCompanion(
        offerId: offerId,
        speakerUid: uid,
      );

      if (!mounted) return;

      final res = result['result'] as String;

      if (res == 'ok' || res == 'already_used') {
        final sessionId = result['sessionId'] as String?;
        if (sessionId == null || sessionId.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se pudo obtener la sesión creada, intenta de nuevo.'),
            ),
          );
          return;
        }

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SessionConversationScreen(sessionId: sessionId),
          ),
        );
      } else if (res == 'not_pending' || res == 'not_exists') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'La solicitud ya no está disponible.\n'
              'Es probable que la compañera haya cancelado o se acabó el tiempo.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al aceptar la compañera: $e')),
      );
    }
  }

  Future<void> _rejectPendingCompanion(String offerId) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    final uid = currentUser.uid;

    try {
      final result = await OffersService().rejectPendingCompanion(
        offerId: offerId,
        speakerUid: uid,
      );

      if (!mounted) return;

      if (result == 'ok') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rechazaste la solicitud. La oferta volvió a estar disponible.'),
          ),
        );
      } else if (result == 'already_used') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('La sesión ya se encuentra activa, no se puede rechazar.'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'La solicitud ya no estaba pendiente.\n'
              'Es probable que la compañera haya cancelado o se acabó el tiempo.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al rechazar la compañera: $e')),
      );
    }
  }

  Future<void> _handleEditOffer({
    required String offerId,
    required Map<String, dynamic> offerData,
    required String userId,
    required String alias,
    required String country,
    required String city,
  }) async {
    await showCreateOfferDialog(
      context: context,
      userId: userId,
      alias: alias,
      country: country,
      city: city,
      offerId: offerId,
      initialData: offerData,
    );
  }

  Future<void> _handleDeleteOffer(String offerId) async {
    if (_busy) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar oferta'),
        content: const Text(
          '¿Seguro que quieres eliminar esta oferta?\n'
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (mounted) {
      setState(() {
        _busy = true;
        _processingOfferId = offerId;
      });
    }

    try {
      await FirebaseFirestore.instance.collection('offers').doc(offerId).delete();

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Oferta eliminada.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al eliminar oferta: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _processingOfferId = null;
        });
      }
    }
  }
}
