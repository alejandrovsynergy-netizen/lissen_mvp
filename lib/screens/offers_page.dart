import 'dart:math';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'waiting_for_speaker_screen.dart';
import 'create_offer_dialog.dart';
import '../features/sessions/ui/session_screen.dart';
import 'incoming_companion_dialog.dart';
import '../features/offers/data/offers_service.dart';

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
  double _deg2rad(double deg) {
    return deg * (3.1415926535897932 / 180.0);
  }

  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const double R = 6371.0; // radio aproximado de la Tierra en km
    final double dLat = _deg2rad(lat2 - lat1);
    final double dLon = _deg2rad(lon2 - lon1);

    final double a =
        (sin(dLat / 2) * sin(dLat / 2)) +
        cos(_deg2rad(lat1)) *
            cos(_deg2rad(lat2)) *
            (sin(dLon / 2) * sin(dLon / 2));

    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return R * c;
  }

  int _createdAtMs(Map<String, dynamic> data) {
    final createdAt = data['createdAt'];
    if (createdAt is Timestamp) return createdAt.millisecondsSinceEpoch;

    final updatedAt = data['updatedAt'];
    if (updatedAt is Timestamp) return updatedAt.millisecondsSinceEpoch;

    return 0;
  }

  int _priceCents(Map<String, dynamic> data) {
    final v = data['priceCents'] ?? data['totalMinAmountCents'] ?? 0;
    if (v is num) return v.toInt();
    return 0;
  }

  double? _offerDistanceForDoc({
    required Map<String, dynamic> offerData,
    required double? userLat,
    required double? userLng,
  }) {
    final double? offerLat = (offerData['locationCenterLat'] as num?)
        ?.toDouble();
    final double? offerLng = (offerData['locationCenterLng'] as num?)
        ?.toDouble();

    if (userLat == null ||
        userLng == null ||
        offerLat == null ||
        offerLng == null) {
      return null;
    }
    return _distanceKm(userLat, userLng, offerLat, offerLng);
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
        final companionCodeUser = (userData['companionCode'] ?? '')
            .toString()
            .trim();

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
              final List<QueryDocumentSnapshot<Map<String, dynamic>>>
              candidates = [];

              for (final doc in allDocs) {
                final data = doc.data();
                final status = (data['status'] ?? 'active') as String;
                final speakerId = (data['speakerId'] ?? '') as String;
                final offerCompanionCode = (data['companionCode'] ?? '')
                    .toString()
                    .trim();

                // Estado y dueño
                if (status != 'active') continue;
                if (speakerId.isEmpty || speakerId == currentUserId) {
                  continue;
                }

                // Privacidad: pública vs privada con código
                if (offerCompanionCode.isNotEmpty) {
                  if (companionCodeUser.isEmpty ||
                      companionCodeUser != offerCompanionCode) {
                    continue;
                  }
                }

                // Filtro de género objetivo
                final targetGender = (data['targetGender'] ?? 'todos')
                    .toString()
                    .toLowerCase();
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
                final aCents = _priceCents(aData);
                final bCents = _priceCents(bData);

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
                final aCreated = _createdAtMs(aData);
                final bCreated = _createdAtMs(bData);
                final cmpCreated = aCreated.compareTo(bCreated);
                if (cmpCreated != 0) return cmpCreated;

                // 4) Último desempate estable
                return a.id.compareTo(b.id);
              });
            }

            final screenH = MediaQuery.of(context).size.height;

            return Scaffold(
              floatingActionButton: isSpeaker
                  ? FloatingActionButton(
                      onPressed: () {
                        if (_busy) return;

                        // ✅ Hablante solo puede tener 1 oferta activa a la vez
                        final hasActiveOffer = allDocs.any((d) {
                          final data = d.data();
                          final speakerId = (data['speakerId'] ?? '')
                              .toString()
                              .trim();
                          final status = (data['status'] ?? 'active')
                              .toString();

                          if (speakerId != currentUserId) return false;

                          // Consideramos "activa" tanto active como pending_speaker
                          return status == 'active' ||
                              status == 'pending_speaker';
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
                    )
                  : null,
              body: SafeArea(
                child: isSpeaker
                    ? CustomScrollView(
                        slivers: [
                          // 1/4 pantalla vacía arriba
                          SliverToBoxAdapter(
                            child: SizedBox(height: screenH * 0.125),
                          ),

                          // Título
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

                          // Empujar el inicio de tarjetas a aprox. media altura
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
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final doc = docs[index];
                                  final data = doc.data();
                                  final status =
                                      (data['status'] ?? 'active') as String;

                                  final isPendingForSpeaker =
                                      status == 'pending_speaker' &&
                                      (data['pendingSpeakerId'] ?? '') ==
                                          currentUserId;

                                  return Align(
                                    alignment: Alignment.topCenter,
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 520,
                                      ),
                                      child: _OfferCard(
                                        docId: doc.id,
                                        data: data,
                                        isSpeaker: true,
                                        isPendingForSpeaker:
                                            isPendingForSpeaker,
                                        currentUserId: currentUserId,
                                        currentUserAlias: alias,
                                        isProcessing:
                                            _busy &&
                                            _processingOfferId == doc.id,
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
                                        onDelete: (offerId) =>
                                            _handleDeleteOffer(offerId),
                                        onSpeakerPendingDecision:
                                            isPendingForSpeaker
                                            ? (offerId, offerData) =>
                                                  _handleSpeakerPendingDecision(
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
                          // 2–3 líneas aprox. de espacio arriba
                          const SliverToBoxAdapter(child: SizedBox(height: 28)),

                          // Título
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

                          // Filtros (Montos / Cercanía)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _FilterDropdown(
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
                                    child: _FilterDropdown(
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              sliver: SliverList.separated(
                                itemCount: docs.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final doc = docs[index];
                                  final data = doc.data();
                                  final status =
                                      (data['status'] ?? 'active') as String;

                                  final isPendingForSpeaker =
                                      false; // compañera no usa esto

                                  return Align(
                                    alignment: Alignment.topCenter,
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 520,
                                      ),
                                      child: _OfferCard(
                                        docId: doc.id,
                                        data: data,
                                        isSpeaker: false,
                                        isPendingForSpeaker:
                                            isPendingForSpeaker,
                                        currentUserId: currentUserId,
                                        currentUserAlias: alias,
                                        isProcessing:
                                            _busy &&
                                            _processingOfferId == doc.id,
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

  // ======================
  // COMPAÑERA TOMA OFERTA
  // ======================
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al tomar oferta: $e')));
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

  // ===================================
  // HABLANTE: DECIDIR OFERTA PENDIENTE
  // ===================================
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
      final companionUserId = (offerData['pendingCompanionId'] ?? '')
          .toString()
          .trim();

      // Datos para el modal
      final companionAlias = (offerData['pendingCompanionAlias'] ?? 'Alguien')
          .toString();
      final durationMinutes =
          (offerData['durationMinutes'] ?? offerData['minMinutes'] ?? 30)
              as int;
      final int rawPriceCents =
          (offerData['priceCents'] ?? offerData['totalMinAmountCents'] ?? 0)
              as int;
      final double amount = rawPriceCents <= 0 ? 0.0 : rawPriceCents / 100.0;
      final currency = (offerData['currency'] ?? 'usd')
          .toString()
          .toUpperCase();
      final communicationType = (offerData['communicationType'] ?? 'chat')
          .toString();

      final decision = await showIncomingCompanionDialog(
        context: context,
        companionAlias: companionAlias,
        durationMinutes: durationMinutes,
        amountUsd: amount,
        currency: currency,
        communicationType: communicationType,
        companionUid: companionUserId, // 👈 agregar esta línea
      );

      if (decision == true) {
        await _acceptPendingCompanion(offerId);
      } else if (decision == false) {
        await _rejectPendingCompanion(offerId);
      } else {
        // null -> no hacemos nada
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
              content: Text(
                'No se pudo obtener la sesión creada, intenta de nuevo.',
              ),
            ),
          );
          return;
        }

        // Navegamos a la sesión
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
            content: Text(
              'Rechazaste la solicitud. La oferta volvió a estar disponible.',
            ),
          ),
        );
      } else if (result == 'already_used') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'La sesión ya se encuentra activa, no se puede rechazar.',
            ),
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

  // ======================
  // EDITAR OFERTA (HABLANTE)
  // ======================
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

  // ======================
  // ELIMINAR OFERTA (HABLANTE)
  // ======================
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
      await FirebaseFirestore.instance
          .collection('offers')
          .doc(offerId)
          .delete();

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Oferta eliminada.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al eliminar oferta: $e')));
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

class _FilterDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?> onChanged;

  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: value,
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
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
  })
  onTakeOffer;

  final void Function(String offerId, Map<String, dynamic> offerData)? onEdit;
  final Future<void> Function(String offerId)? onDelete;

  // decisión hablante ante compañera pendiente
  final Future<void> Function(String offerId, Map<String, dynamic> offerData)?
  onSpeakerPendingDecision;

  const _OfferCard({
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

    if (speakerId.isEmpty) {
      // Oferta rara sin hablante: mostramos la tarjeta con datos mínimos
      return _buildCardContent(context, null, '');
    }

    // Leemos el perfil del hablante en users/{speakerId}
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(speakerId)
          .get(),
      builder: (context, snapshot) {
        Map<String, dynamic>? speakerProfile;
        if (snapshot.hasData && snapshot.data!.exists) {
          speakerProfile = snapshot.data!.data();
        }
        return _buildCardContent(context, speakerProfile, speakerId);
      },
    );
  }

  // speakerProfile puede ser null (si no existe el doc).
  Widget _buildCardContent(
    BuildContext context,
    Map<String, dynamic>? speakerProfile,
    String speakerId,
  ) {
    final status = (data['status'] ?? 'active') as String;

    // ===== DATOS DEL HABLANTE (perfil) =====
    final profileAlias =
        (speakerProfile?['alias'] ?? data['speakerAlias'] ?? 'Anónimo')
            .toString();

    final profileGenderRaw = (speakerProfile?['gender'] ?? '')
        .toString()
        .toLowerCase();
    String profileGenderLabel;
    switch (profileGenderRaw) {
      case 'hombre':
        profileGenderLabel = 'Hombre';
        break;
      case 'mujer':
        profileGenderLabel = 'Mujer';
        break;
      default:
        profileGenderLabel = 'Género no especificado';
    }

    final int? profileAge = (speakerProfile?['age'] as num?)?.toInt();

    final profilePhotoUrl =
        (speakerProfile?['photoUrl'] ??
                speakerProfile?['profilePhotoUrl'] ??
                '')
            .toString()
            .trim();

    // ===== DATOS DE LA OFERTA =====
    final title = (data['title'] ?? 'Oferta').toString();
    final description = (data['description'] ?? '').toString();
    final currency = (data['currency'] ?? 'usd').toString().toUpperCase();
    final durationMinutes =
        (data['durationMinutes'] ?? data['minMinutes'] ?? 30) as int;

    final int rawPriceCents =
        (data['priceCents'] ?? data['totalMinAmountCents'] ?? 0) as int;
    final double price = rawPriceCents / 100.0;

    // A quién va dirigida la oferta
    final targetGender = (data['targetGender'] ?? 'todos').toString();
    String targetGenderLabel;
    switch (targetGender) {
      case 'hombre':
        targetGenderLabel = 'Buscando: solo hombres';
        break;
      case 'mujer':
        targetGenderLabel = 'Buscando: solo mujeres';
        break;
      default:
        targetGenderLabel = 'Buscando: todos';
    }

    final communicationType = (data['communicationType'] ?? 'chat').toString();
    String communicationLabel;
    switch (communicationType) {
      case 'voice':
        communicationLabel = 'Llamada de voz';
        break;
      case 'video':
        communicationLabel = 'Videollamada';
        break;
      default:
        communicationLabel = 'Solo chat';
    }

    final speakerCity = (data['speakerCity'] ?? '').toString();
    final speakerCountry = (data['speakerCountry'] ?? '').toString();
    final locationText = [
      speakerCity,
      speakerCountry,
    ].where((e) => e.isNotEmpty).join(', ');

    final pendingCompanionAlias = (data['pendingCompanionAlias'] ?? 'Alguien')
        .toString();

    final canTake = !isSpeaker && status == 'active' && !isProcessing;

    // ===== UI =====
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Encabezado (título + precio + menú)
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '\$${price.toStringAsFixed(2)} $currency',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                if (isSpeaker)
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') {
                        if (onEdit != null) {
                          onEdit!(docId, data);
                        }
                      } else if (value == 'delete') {
                        if (onDelete != null) {
                          onDelete!(docId);
                        }
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'edit', child: Text('Editar')),
                      PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                    ],
                    child: const Padding(
                      padding: EdgeInsets.only(left: 4.0),
                      child: Icon(Icons.more_vert, size: 20),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // FOTO + DATOS DEL HABLANTE
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () {
                    _showSpeakerGallery(context, speakerId, profilePhotoUrl);
                  },
                  child: CircleAvatar(
                    radius: 18,
                    backgroundImage: profilePhotoUrl.isNotEmpty
                        ? NetworkImage(profilePhotoUrl)
                        : null,
                    child: profilePhotoUrl.isEmpty
                        ? const Icon(Icons.person, size: 20)
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profileAlias,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        profileAge != null
                            ? '$profileAge años • $profileGenderLabel'
                            : profileGenderLabel,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 6),

            Text(
              'Duración estimada: $durationMinutes min',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),

            if (description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],

            if (locationText.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.location_on, size: 14),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      locationText,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 4),

            Text(
              communicationLabel,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),

            const SizedBox(height: 2),

            Text(
              targetGenderLabel,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),

            const SizedBox(height: 12),

            // BOTONES SEGÚN ROL / ESTADO
            if (canTake)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isProcessing
                      ? null
                      : () {
                          onTakeOffer(
                            offerId: docId,
                            offerData: data,
                            currentUserId: currentUserId,
                            currentUserAlias: currentUserAlias,
                          );
                        },
                  child: isProcessing
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Aceptar oferta'),
                ),
              )
            else if (isSpeaker && isPendingForSpeaker) ...[
              Text(
                '$pendingCompanionAlias quiere tomar esta oferta.',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Decide si aceptas o rechazas.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: onSpeakerPendingDecision == null
                      ? null
                      : () => onSpeakerPendingDecision!(docId, data),
                  child: const Text('Decidir ahora'),
                ),
              ),
            ] else
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  status == 'pending_speaker'
                      ? 'Esperando respuesta del hablante...'
                      : 'Estado: $status',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // =========
  // GALERÍA
  // =========
  Future<void> _showSpeakerGallery(
    BuildContext context,
    String speakerId,
    String profilePhotoUrl,
  ) async {
    try {
      // Leemos fotos de users/{speakerId}/gallery
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(speakerId)
          .collection('gallery')
          .get();

      final urls = <String>[];

      // Primero la foto de perfil
      if (profilePhotoUrl.isNotEmpty) {
        urls.add(profilePhotoUrl);
      }

      // Luego las demás fotos del sub-collection
      for (final doc in snap.docs) {
        final url = (doc.data()['url'] ?? '').toString().trim();
        if (url.isNotEmpty && !urls.contains(url)) {
          urls.add(url);
        }
      }

      if (urls.isEmpty) {
        return;
      }

      final controller = PageController(initialPage: 0);

      // ignore: use_build_context_synchronously
      await showDialog(
        context: context,
        builder: (ctx) {
          int currentPage = 0;
          return StatefulBuilder(
            builder: (ctx, setState) {
              return Dialog(
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 40,
                ),
                backgroundColor: Colors.black87,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.topRight,
                      child: IconButton(
                        icon: const Icon(Icons.close),
                        color: Colors.white,
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ),
                    SizedBox(
                      height: 260,
                      width: double.infinity,
                      child: PageView.builder(
                        controller: controller,
                        itemCount: urls.length,
                        onPageChanged: (i) => setState(() => currentPage = i),
                        itemBuilder: (_, index) => ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.network(urls[index], fit: BoxFit.cover),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        urls.length,
                        (i) => Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == currentPage
                                ? Colors.white
                                : Colors.white24,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              );
            },
          );
        },
      );
    } catch (_) {
      // si truena, simplemente no mostramos nada
    }
  }
}
