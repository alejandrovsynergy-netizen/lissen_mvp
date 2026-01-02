import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:just_audio/just_audio.dart';

import 'waiting_for_speaker_screen.dart';
import 'create_offer_dialog.dart';
import '../features/sessions/ui/session_screen.dart';
import 'incoming_companion_dialog.dart';
import '../features/offers/data/offers_service.dart';
import '../features/offers/ui/widgets/filter_dropdown.dart';
import '../features/offers/ui/widgets/offer_card.dart';
import '../features/offers/ui/utils/offers_utils.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../features/payments/payments_api.dart';

import 'profile/money_activity_screen.dart';

class OffersPage extends StatefulWidget {
  const OffersPage({super.key});

  @override
  State<OffersPage> createState() => _OffersPageState();
}

class _OffersPageState extends State<OffersPage> {
  bool _busy = false;
  String? _processingOfferId;

  static const Duration _exploreAlertDuration = Duration(minutes: 2);

  late final AudioPlayer _exploreAlertPlayer;
  bool _exploreAudioReady = false;
  bool _exploreAudioInitialized = false;
  bool _exploreAlertPlayerDisposed = false;
  Timer? _exploreAlertTimer;
  Timer? _exploreAlertStopTimer;
  String? _exploreAlertOfferId;
  DateTime? _exploreAlertUntil;

  // ✅ bandera para evitar loop de autopublicación
  bool _autoPublishingPaymentOffers = false;

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

    _exploreAlertPlayer = AudioPlayer();

    _user = FirebaseAuth.instance.currentUser;

    if (_user != null) {
      _userRef = FirebaseFirestore.instance.collection('users').doc(_user!.uid);
      _userStream = _userRef!.snapshots();
    }

    // Este stream ya no se recrea en cada build
    _offersStream = FirebaseFirestore.instance.collection('offers').snapshots();
  }

  @override
  void dispose() {
    _exploreAlertPlayerDisposed = true;
    _exploreAlertTimer?.cancel();
    _exploreAlertStopTimer?.cancel();
    try {
      _exploreAlertPlayer.dispose();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _openMoneyActivity(String uid) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MoneyActivityScreen(uid: uid)),
    );
  }

  // ✅ Autopublicar ofertas bloqueadas cuando ya hay tarjeta guardada
  Future<void> _autoPublishPaymentRequiredOffers({
    required List<String> offerIds,
  }) async {
    if (_autoPublishingPaymentOffers) return;

    setState(() => _autoPublishingPaymentOffers = true);

    try {
      final db = FirebaseFirestore.instance;
      final batch = db.batch();

      for (final id in offerIds) {
        batch.update(db.collection('offers').doc(id), {
          'status': 'active',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
    } catch (_) {
      // Si falla, no truena la app.
    } finally {
      if (mounted) {
        setState(() => _autoPublishingPaymentOffers = false);
      }
    }
  }

  // ============================
  // Cálculo de distancia en km
  // ============================
  double? _offerDistanceForDoc({
    required Map<String, dynamic> offerData,
    required double? userLat,
    required double? userLng,
  }) {
    final double? offerLat =
        (offerData['locationCenterLat'] as num?)?.toDouble();
    final double? offerLng =
        (offerData['locationCenterLng'] as num?)?.toDouble();

    if (userLat == null ||
        userLng == null ||
        offerLat == null ||
        offerLng == null) {
      return null;
    }
    return distanceKm(userLat, userLng, offerLat, offerLng);
  }

  DateTime? _createdAtFromData(Map<String, dynamic> data) {
    final ts = data['createdAt'];
    if (ts is Timestamp) return ts.toDate();
    return null;
  }

  Future<void> _loadExploreAlertSound() async {
    if (_exploreAlertPlayerDisposed || _exploreAudioInitialized) return;
    try {
      await _exploreAlertPlayer.setAsset('assets/sounds/offer_request.wav');
      if (_exploreAlertPlayerDisposed) return;
      _exploreAudioReady = true;
      _exploreAudioInitialized = true;
    } catch (_) {
      _exploreAudioReady = false;
      _exploreAudioInitialized = false;
    }
  }

  Future<void> _playExploreAlertOnce() async {
    if (!_exploreAudioReady || _exploreAlertPlayerDisposed) return;
    try {
      await _exploreAlertPlayer.stop();
      await _exploreAlertPlayer.seek(Duration.zero);
      await _exploreAlertPlayer.play();
      HapticFeedback.vibrate();
      await Future.delayed(const Duration(milliseconds: 120));
      HapticFeedback.vibrate();
    } catch (_) {}
  }

  Future<void> _startExploreAlert({
    required String offerId,
    required Duration remaining,
  }) async {
    if (_exploreAlertPlayerDisposed) return;

    _exploreAlertOfferId = offerId;
    _exploreAlertUntil = DateTime.now().add(remaining);

    _exploreAlertStopTimer?.cancel();
    _exploreAlertTimer?.cancel();

    if (!_exploreAudioInitialized) {
      await _loadExploreAlertSound();
    }
    if (!_exploreAudioReady || _exploreAlertPlayerDisposed) return;

    await _playExploreAlertOnce();

    _exploreAlertTimer =
        Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_exploreAlertPlayerDisposed) return;
      final until = _exploreAlertUntil;
      if (until != null && DateTime.now().isAfter(until)) {
        _stopExploreAlert();
        return;
      }
      await _playExploreAlertOnce();
    });

    _exploreAlertStopTimer = Timer(remaining, _stopExploreAlert);
  }

  Future<void> _stopExploreAlert() async {
    if (_exploreAlertPlayerDisposed) return;
    _exploreAlertTimer?.cancel();
    _exploreAlertStopTimer?.cancel();
    _exploreAlertTimer = null;
    _exploreAlertStopTimer = null;
    _exploreAlertOfferId = null;
    _exploreAlertUntil = null;
    try {
      await _exploreAlertPlayer.stop();
    } catch (_) {}
  }

  bool _isExploreAlertEligible(
    Map<String, dynamic> data,
    String currentUserId,
  ) {
    final createdFrom = (data['createdFrom'] ?? '').toString();
    if (createdFrom != 'explore') return false;
    final status = (data['status'] ?? 'active').toString();
    if (status != 'active') return false;
    final targetCompanionId =
        (data['targetCompanionId'] ?? '').toString().trim();
    if (targetCompanionId.isEmpty) return false;
    if (targetCompanionId != currentUserId) return false;
    return true;
  }

  void _maybeHandleExploreAlert({
    required String currentUserId,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  }) {
    if (_exploreAlertPlayerDisposed) return;

    if (_exploreAlertOfferId != null) {
      QueryDocumentSnapshot<Map<String, dynamic>>? currentDoc;
      for (final doc in docs) {
        if (doc.id == _exploreAlertOfferId) {
          currentDoc = doc;
          break;
        }
      }

      if (currentDoc == null) {
        _stopExploreAlert();
        return;
      }

      final data = currentDoc.data();
      if (!_isExploreAlertEligible(data, currentUserId)) {
        _stopExploreAlert();
        return;
      }

      final createdAt = _createdAtFromData(data);
      if (createdAt == null) {
        _stopExploreAlert();
        return;
      }

      final remaining =
          _exploreAlertDuration - DateTime.now().difference(createdAt);
      if (remaining <= Duration.zero) {
        _stopExploreAlert();
      }
      return;
    }

    QueryDocumentSnapshot<Map<String, dynamic>>? targetDoc;
    DateTime? targetCreatedAt;

    for (final doc in docs) {
      final data = doc.data();
      if (!_isExploreAlertEligible(data, currentUserId)) continue;
      final createdAt = _createdAtFromData(data);
      if (createdAt == null) continue;

      final remaining =
          _exploreAlertDuration - DateTime.now().difference(createdAt);
      if (remaining <= Duration.zero) continue;

      if (targetDoc == null || createdAt.isAfter(targetCreatedAt!)) {
        targetDoc = doc;
        targetCreatedAt = createdAt;
      }
    }

    if (targetDoc == null || targetCreatedAt == null) return;

    final remaining =
        _exploreAlertDuration - DateTime.now().difference(targetCreatedAt);
    if (remaining <= Duration.zero) return;

    _startExploreAlert(offerId: targetDoc.id, remaining: remaining);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // === Solo visual (como preview) ===
    const emeraldA = Color(0xFF10B981);
    const emeraldB = Color(0xFF059669);
    final cyanGlow = const Color(0xFF22D3EE);

    final user = _user;
    if (user == null) {
      return Center(
        child: Text(
          'Debes iniciar sesión.',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }

    final userStream = _userStream;
    if (userStream == null) {
      return Center(
        child: Text(
          'No se encontró tu perfil.',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userStream,
      builder: (context, userSnap) {
        if (userSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!userSnap.hasData || !userSnap.data!.exists) {
          return Center(
            child: Text(
              'No se encontró tu perfil.',
              style: theme.textTheme.bodyMedium,
            ),
          );
        }

        final userData = userSnap.data!.data() ?? {};
        final role = (userData['role'] as String?) ?? 'speaker';
        final alias = (userData['alias'] as String?) ?? 'Usuario';
        final country = (userData['country'] as String?) ?? '';
        final city = (userData['city'] as String?) ?? '';
        final companionCodeUser =
            (userData['companionCode'] ?? '').toString().trim();

        final blockedByMe = (userData['blockedUsers'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toSet() ??
            <String>{};

        // género y geolocalización de la compañera
        final userGender = (userData['gender'] as String?)?.toLowerCase() ?? '';
        final double? userLat = (userData['geoLat'] as num?)?.toDouble();
        final double? userLng = (userData['geoLng'] as num?)?.toDouble();

        final isSpeaker = role == 'speaker';
        final currentUserId = user.uid;

        bool _isTrue(dynamic v) {
          if (v == true) return true;
          if (v is num) return v != 0;
          if (v is String) {
            final s = v.toLowerCase().trim();
            return s == 'true' || s == '1' || s == 'yes';
          }
          return false;
        }

        // ✅ Variables de método de pago (para panel + autopublish)
        final defaultPmBrand =
            (userData['stripeDefaultPmBrand'] as String?)?.trim() ?? '';
        final defaultPmLast4 =
            (userData['stripeDefaultPmLast4'] as String?)?.trim() ?? '';
        final hasSavedCard = defaultPmLast4.isNotEmpty;
        final bool companionStripeOk = (() {
          final roleOk = role == 'companion';
          if (!roleOk) return true;
          final connectId =
              (userData['stripeConnectAccountId'] ??
                      userData['stripeAccountId'] ??
                      '')
                  .toString()
                  .trim();
          final payoutsEnabled = _isTrue(
            userData['stripeConnectPayoutsEnabled'] ??
                userData['stripePayoutsEnabled'],
          );
          final detailsSubmitted = _isTrue(
            userData['stripeConnectDetailsSubmitted'] ??
                userData['stripeDetailsSubmitted'],
          );
          return connectId.isNotEmpty && payoutsEnabled && detailsSubmitted;
        })();

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _offersStream, // ✅ stream estable
          builder: (context, offerSnap) {
            if (offerSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!offerSnap.hasData) {
              return Center(
                child: Text(
                  'No se pudieron leer ofertas.',
                  style: theme.textTheme.bodyMedium,
                ),
              );
            }

            final allDocs = offerSnap.data!.docs;

            // ==============================
            // FILTRADO POR ROL / REGLAS
            // ==============================
            List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

            if (isSpeaker) {
              // Hablante: solo SUS ofertas activas o pendientes o bloqueadas por pago
              docs = allDocs.where((doc) {
                final data = doc.data();
                final status = (data['status'] ?? 'active').toString();
                final speakerId = (data['speakerId'] ?? '').toString();

                if (blockedByMe.contains(speakerId)) return false;

                if (speakerId != currentUserId) return false;
                return status == 'active' ||
                    status == 'pending_speaker' ||
                    status == 'payment_required';
              }).toList();
            } else {
              // ==============================
              // COMPAÑERA: filtros
              // ==============================
              final List<QueryDocumentSnapshot<Map<String, dynamic>>> candidates =
                  [];

              for (final doc in allDocs) {
                final data = doc.data();
                final status = (data['status'] ?? 'active').toString();
                final speakerId = (data['speakerId'] ?? '').toString();

                if (blockedByMe.contains(speakerId)) {
                  continue;
                }
                final offerCompanionCode =
                    (data['companionCode'] ?? '').toString().trim();

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
                final targetCompanionId =
                    (data['targetCompanionId'] ?? '').toString().trim();
                if (targetCompanionId.isNotEmpty &&
                    targetCompanionId != currentUserId) {
                  continue;
                }

                final targetGender =
                    (data['targetGender'] ?? 'todos').toString().toLowerCase();
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

            if (!isSpeaker) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _maybeHandleExploreAlert(
                  currentUserId: currentUserId,
                  docs: docs,
                );
              });
            } else {
              _stopExploreAlert();
            }

            // ✅ Autopublicar si ya hay tarjeta guardada
            if (isSpeaker && hasSavedCard) {
              final ids = docs
                  .where((d) =>
                      (d.data()['status'] ?? 'active').toString() ==
                      'payment_required')
                  .map((d) => d.id)
                  .toList();

              if (ids.isNotEmpty && !_autoPublishingPaymentOffers) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _autoPublishPaymentRequiredOffers(offerIds: ids);
                });
              }
            }

            return Scaffold(
              // ✅ Solo visual: deja ver tu fondo global (NO lo cambio)
              backgroundColor: Colors.transparent,

              floatingActionButton: isSpeaker
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 80),
                      child: _GradientFab(
                        onPressed: () {
                          if (_busy) return;

                          final hasActiveOffer = allDocs.any((d) {
                            final data = d.data();
                            final speakerId =
                                (data['speakerId'] ?? '').toString().trim();
                            final status =
                                (data['status'] ?? 'active').toString();

                            if (speakerId != currentUserId) return false;
                            return status == 'active' ||
                                status == 'pending_speaker' ||
                                status == 'payment_required';
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
                      ),
                    )
                  : null,

              body: SafeArea(
                child: isSpeaker
                    ? CustomScrollView(
                        slivers: [
                          const SliverToBoxAdapter(child: SizedBox(height: 12)),

                          // ===== Header tipo preview =====
                          SliverToBoxAdapter(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _GlowTitle(
                                    text: 'Lissen',
                                    glowColor: cyanGlow,
                                  ),
                                  const SizedBox(height: 14),
                                  _SectionHeader(
                                    icon: Icons.local_offer_outlined,
                                    iconBg: emeraldA.withOpacity(0.12),
                                    iconColor: emeraldA,
                                    title: 'Mis ofertas',
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Crea una oferta y encuentra alguien con quien conversar.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: cs.onBackground.withOpacity(0.70),
                                      height: 1.25,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SliverToBoxAdapter(child: SizedBox(height: 14)),

                          // ✅ Panel método de pago (envuelto en SliverToBoxAdapter)
                          SliverToBoxAdapter(
                            child: _PaymentMethodPanel(
                              hasSavedCard: hasSavedCard,
                              brand: defaultPmBrand,
                              last4: defaultPmLast4,
                              onManage: () => _openMoneyActivity(currentUserId),
                            ),
                          ),

                          if (docs.isNotEmpty) ...[
                            SliverToBoxAdapter(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: _InfoNote(
                                  text:
                                      'Importante: No se te cobrará nada si no hay conversación.\n'
                                      'Si alguien toma tu oferta, te avisaremos para que puedas aceptar o rechazar antes de empezar.',
                                ),
                              ),
                            ),
                            const SliverToBoxAdapter(
                              child: SizedBox(height: 12),
                            ),
                          ],

                          if (docs.isEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: Center(
                                  child: _EmptyPanel(
                                    text:
                                        'Aquí aparecerán tus ofertas.\n\n'
                                        'Crea una para que otras personas puedan encontrarte y pedirte conversar. '
                                        'Solo se te cobrará si la conversación realmente sucede.\n\n'
                                        'Cuando alguien tome tu oferta, te avisaremos para que puedas aceptar o rechazar.',
                                    borderColor: cyanGlow.withOpacity(0.25),
                                  ),
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
                                      (data['status'] ?? 'active').toString();

                                  final isPendingForSpeaker =
                                      status == 'pending_speaker' &&
                                          (data['pendingSpeakerId'] ?? '') ==
                                              currentUserId;

                                  return Align(
                                    alignment: Alignment.topCenter,
                                    child: ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(maxWidth: 520),
                                      child: _CardFrame(
                                        borderColor: cyanGlow.withOpacity(0.22),
                                        child: OfferCard(
                                          docId: doc.id,
                                          data: data,
                                          isSpeaker: true,
                                          isPendingForSpeaker:
                                              isPendingForSpeaker,
                                          currentUserId: currentUserId,
                                          currentUserAlias: alias,
                                          isProcessing: _busy &&
                                              _processingOfferId == doc.id,
                                          blockedUserIds: blockedByMe,
                                          onTakeOffer: ({
                                            required offerId,
                                            required offerData,
                                            required currentUserId,
                                            required currentUserAlias,
                                          }) =>
                                              _handleCompanionTakeOffer(
                                                offerId: offerId,
                                                offerData: offerData,
                                                currentUserId: currentUserId,
                                                currentUserAlias:
                                                    currentUserAlias,
                                                companionStripeOk: true,
                                              ),
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
                                          onRejectWithCode: null,
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
                                    ),
                                  );
                                },
                              ),
                            ),

                          const SliverToBoxAdapter(child: SizedBox(height: 24)),
                        ],
                      )
                    : CustomScrollView(
                        slivers: [
                          const SliverToBoxAdapter(child: SizedBox(height: 12)),

                          // ===== Header tipo preview =====
                          SliverToBoxAdapter(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _GlowTitle(
                                    text: 'Lissen',
                                    glowColor: cyanGlow,
                                  ),
                                  const SizedBox(height: 14),
                                  _SectionHeader(
                                    icon: Icons.explore_outlined,
                                    iconBg: emeraldA.withOpacity(0.12),
                                    iconColor: emeraldA,
                                    title: 'Ofertas disponibles',
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SliverToBoxAdapter(child: SizedBox(height: 12)),

                          // ===== Filtros (mismo widget, solo enmarcado visual) =====
                          SliverToBoxAdapter(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: _CardFrame(
                                borderColor: cyanGlow.withOpacity(0.18),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
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
                                              child:
                                                  Text('Más cercanas primero'),
                                            ),
                                            DropdownMenuItem(
                                              value: 'far',
                                              child:
                                                  Text('Más lejanas primero'),
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
                            ),
                          ),

                          const SliverToBoxAdapter(child: SizedBox(height: 12)),

                          if (docs.isEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: Center(
                                  child: _EmptyPanel(
                                    text:
                                        'No hay ofertas disponibles en este momento.',
                                    borderColor: cyanGlow.withOpacity(0.25),
                                  ),
                                ),
                              ),
                            )
                          else ...[
                            SliverPadding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              sliver: SliverList.separated(
                                itemCount: docs.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final doc = docs[index];
                                  final data = doc.data();

                                  return Align(
                                    alignment: Alignment.topCenter,
                                    child: ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(maxWidth: 520),
                                      child: _CardFrame(
                                        borderColor: cyanGlow.withOpacity(0.22),
                                        child: OfferCard(
                                          docId: doc.id,
                                          data: data,
                                          isSpeaker: false,
                                          isPendingForSpeaker: false,
                                          currentUserId: currentUserId,
                                          currentUserAlias: alias,
                                          isProcessing: _busy &&
                                              _processingOfferId == doc.id,
                                          blockedUserIds: blockedByMe,
                                          allowTake: companionStripeOk,
                                          takeBlockedMessage: companionStripeOk
                                              ? null
                                              : 'Conecta tu cuenta de Stripe para poder tomar ofertas.',
                                          onTakeOffer:
                                              ({
                                                required offerId,
                                                required offerData,
                                                required currentUserId,
                                                required currentUserAlias,
                                              }) =>
                                                  _handleCompanionTakeOffer(
                                                    offerId: offerId,
                                                    offerData: offerData,
                                                    currentUserId:
                                                        currentUserId,
                                                    currentUserAlias:
                                                        currentUserAlias,
                                                    companionStripeOk:
                                                        companionStripeOk,
                                                  ),
                                          onEdit: null,
                                          onDelete: null,
                                          onRejectWithCode: (offerId, offerData) =>
                                              _handleCompanionRejectWithCode(
                                                offerId: offerId,
                                                offerData: offerData,
                                              ),
                                          onSpeakerPendingDecision: null,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],

                          const SliverToBoxAdapter(child: SizedBox(height: 24)),
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
    required bool companionStripeOk,
  }) async {
    if (_busy) return;

    if (!companionStripeOk) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Conecta tu cuenta de Stripe para poder tomar ofertas.',
            ),
          ),
        );
      }
      return;
    }

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

  Future<void> _handleCompanionRejectWithCode({
    required String offerId,
    required Map<String, dynamic> offerData,
  }) async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _processingOfferId = offerId;
    });

    try {
      final res = await FirebaseFirestore.instance
          .runTransaction<String?>((tx) async {
        final ref =
            FirebaseFirestore.instance.collection('offers').doc(offerId);
        final snap = await tx.get(ref);
        if (!snap.exists) return 'not_exists';

        final data = snap.data() as Map<String, dynamic>;
        final status = (data['status'] ?? 'active').toString();
        final code = (data['companionCode'] ?? '').toString().trim();
        final pendingCompanionId =
            (data['pendingCompanionId'] ?? '').toString().trim();

        if (status == 'active' && code.isNotEmpty && pendingCompanionId.isEmpty) {
          tx.delete(ref);
          return 'deleted';
        }
        return 'no_action';
      });

      if (!mounted) return;

      if (res == 'deleted') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Oferta rechazada.')),
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
      final companionUserId =
          (offerData['pendingCompanionId'] ?? '').toString().trim();

      final companionAlias =
          (offerData['pendingCompanionAlias'] ?? 'Alguien').toString();
      final durationMinutes =
          (offerData['durationMinutes'] ?? offerData['minMinutes'] ?? 30) as int;
      final int rawPriceCents =
          (offerData['priceCents'] ?? offerData['totalMinAmountCents'] ?? 0)
              as int;
      final double amount = rawPriceCents <= 0 ? 0.0 : rawPriceCents / 100.0;
      final currency =
          (offerData['currency'] ?? 'usd').toString().toUpperCase();
      final communicationType =
          (offerData['communicationType'] ?? 'chat').toString();

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
      // 1) Generamos un sessionId, pero NO creamos sesión todavía.
      final sessionsRef = FirebaseFirestore.instance.collection('sessions');
      final newSessionId = sessionsRef.doc().id;

      // 2) HOLD sí o sí. Si falla -> NO se crea sesión.
      Map<String, dynamic> hold;
      try {
        hold = await PaymentsApi().authorizeOfferHold(
          offerId: offerId,
          sessionId: newSessionId,
        );
      } catch (e) {
        // Revertimos la oferta a activa para liberar a la compañera.
        await FirebaseFirestore.instance.runTransaction<void>((tx) async {
          final offerRef =
              FirebaseFirestore.instance.collection('offers').doc(offerId);
          final snap = await tx.get(offerRef);
          if (!snap.exists) return;

          final data = snap.data() as Map<String, dynamic>;
          final status = (data['status'] ?? 'active') as String;
          final speakerId = (data['speakerId'] ?? '') as String;
          final pendingCompanionId =
              (data['pendingCompanionId'] ?? '') as String?;
          final lastSessionId = (data['lastSessionId'] ?? '') as String?;

          if (status == 'pending_speaker' &&
              speakerId == uid &&
              (lastSessionId == null || lastSessionId.isEmpty) &&
              pendingCompanionId != null &&
              pendingCompanionId.isNotEmpty) {
            tx.update(offerRef, {
              'status': 'active',
              'pendingSpeakerId': FieldValue.delete(),
              'pendingCompanionId': FieldValue.delete(),
              'pendingCompanionAlias': FieldValue.delete(),
              'pendingSince': FieldValue.delete(),
              'holdFailedBySpeakerId': uid,
              'holdFailedAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No se pudo autorizar el monto (HOLD).\n'
              'No se creó la sesión.\n$e',
            ),
          ),
        );
        return;
      }

      if (hold['alreadyUsed'] == true) {
        final existing = (hold['sessionId'] ?? '').toString().trim();
        if (existing.isNotEmpty && mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SessionConversationScreen(sessionId: existing),
            ),
          );
        }
        return;
      }

      final reservedSessionId =
          (hold['reservedSessionId'] ?? newSessionId).toString().trim();
      final paymentIntentId = (hold['paymentIntentId'] ?? '').toString().trim();
      final paymentIntentStatus = (hold['status'] ?? '').toString().trim();
      final holdAmountCents = hold['holdAmountCents'];
      final holdCurrency = (hold['holdCurrency'] ?? '').toString().trim();

      if (reservedSessionId.isEmpty || paymentIntentId.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Hold inválido: faltan datos (paymentIntent/sessionId).'),
          ),
        );
        return;
      }

      final created = await FirebaseFirestore.instance
          .runTransaction<Map<String, dynamic>>((tx) async {
        final offerRef =
            FirebaseFirestore.instance.collection('offers').doc(offerId);
        final offerSnap = await tx.get(offerRef);
        if (!offerSnap.exists) return {'result': 'not_exists'};

        final data = offerSnap.data() as Map<String, dynamic>;
        final status = (data['status'] ?? 'active') as String;
        final speakerId = (data['speakerId'] ?? '') as String;
        final pendingCompanionId =
            (data['pendingCompanionId'] ?? '') as String?;
        final lastSessionId = (data['lastSessionId'] ?? '') as String?;

        if (status == 'used' &&
            lastSessionId != null &&
            lastSessionId.isNotEmpty) {
          return {'result': 'already_used', 'sessionId': lastSessionId};
        }

        if (status == 'pending_speaker' &&
            speakerId == uid &&
            pendingCompanionId != null &&
            pendingCompanionId.isNotEmpty &&
            (lastSessionId == null || lastSessionId.isEmpty)) {
          final newSessionRef = sessionsRef.doc(reservedSessionId);

          final speakerAlias = (data['speakerAlias'] ?? 'Hablante').toString();
          final companionAlias =
              (data['pendingCompanionAlias'] ?? 'Compañera').toString();

          final dynamic dm = data['durationMinutes'] ?? data['minMinutes'] ?? 30;
          final int durationMinutes =
              dm is int ? dm : int.tryParse(dm.toString()) ?? 30;

          final dynamic pc =
              data['priceCents'] ?? data['totalMinAmountCents'] ?? 0;
          final int rawPriceCents =
              pc is int ? pc : int.tryParse(pc.toString()) ?? 0;

          final communicationType =
              (data['communicationType'] ?? 'chat').toString();
          final currency = (data['currency'] ?? 'mxn').toString();

          tx.set(newSessionRef, {
            'speakerId': speakerId,
            'companionId': pendingCompanionId,
            'speakerAlias': speakerAlias,
            'companionAlias': companionAlias,
            'offerId': offerId,
            'status': 'active',
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'durationMinutes': durationMinutes,
            'communicationType': communicationType,
            'currency': currency,
            'priceCents': rawPriceCents,
            'participants': [speakerId, pendingCompanionId],

            // ✅ Stripe hold
            'paymentIntentId': paymentIntentId,
            'paymentIntentStatus': paymentIntentStatus,
            'holdAmountCents': holdAmountCents ?? rawPriceCents,
            'holdCurrency': holdCurrency.isNotEmpty ? holdCurrency : currency,
            'holdAuthorizedAt': FieldValue.serverTimestamp(),
          });

          tx.update(offerRef, {
            'status': 'used',
            'lastSessionId': reservedSessionId,
            'pendingSpeakerId': FieldValue.delete(),
            'pendingCompanionId': FieldValue.delete(),
            'pendingCompanionAlias': FieldValue.delete(),
            'pendingSince': FieldValue.delete(),
            'updatedAt': FieldValue.serverTimestamp(),
          });

          return {'result': 'ok', 'sessionId': reservedSessionId};
        }

        return {'result': 'not_pending'};
      });

      if (!mounted) return;
      final res = created['result'] as String;
      if (res == 'ok' || res == 'already_used') {
        final sessionId = (created['sessionId'] ?? '').toString().trim();
        if (sessionId.isNotEmpty) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SessionConversationScreen(sessionId: sessionId),
            ),
          );
          return;
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La solicitud ya no está disponible.')),
      );
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
                'Rechazaste la solicitud. La oferta volvió a estar disponible.'),
          ),
        );
      } else if (result == 'already_used') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('La sesión ya se encuentra activa, no se puede rechazar.'),
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

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

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
            child: Text(
              'Eliminar',
              style: TextStyle(color: cs.error),
            ),
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

// ============================================================================
// SOLO VISUAL (helpers de UI). No tocan lógica.
// ============================================================================

class _GlowTitle extends StatelessWidget {
  final String text;
  final Color glowColor;

  const _GlowTitle({required this.text, required this.glowColor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ShaderMask(
      shaderCallback: (rect) => const LinearGradient(
        colors: [
          Color(0xFF22D3EE),
          Color(0xFF60A5FA),
          Color(0xFF22D3EE),
        ],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ).createShader(rect),
      child: Text(
        text,
        style: theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w900,
          color: Colors.white,
          shadows: [
            Shadow(
              color: glowColor.withOpacity(0.55),
              blurRadius: 28,
              offset: const Offset(0, 0),
            ),
            Shadow(
              color: glowColor.withOpacity(0.35),
              blurRadius: 44,
              offset: const Offset(0, 0),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;

  const _SectionHeader({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: iconColor.withOpacity(0.20), width: 1),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
            color: cs.onBackground,
          ),
        ),
      ],
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  final String text;
  final Color borderColor;

  const _EmptyPanel({required this.text, required this.borderColor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: cs.onBackground.withOpacity(0.78),
          height: 1.25,
        ),
      ),
    );
  }
}

class _CardFrame extends StatelessWidget {
  final Widget child;
  final Color borderColor;

  const _CardFrame({required this.child, required this.borderColor});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.62),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: child,
      ),
    );
  }
}

class _GradientFab extends StatelessWidget {
  final VoidCallback onPressed;

  const _GradientFab({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    const emeraldA = Color(0xFF10B981);
    const emeraldB = Color(0xFF059669);

    return FloatingActionButton(
      onPressed: onPressed,
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [emeraldA, emeraldB],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: emeraldA.withOpacity(0.35),
              blurRadius: 22,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

class _InfoNote extends StatelessWidget {
  final String text;
  const _InfoNote({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    const cyan = Color(0xFF22D3EE);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cyan.withOpacity(0.22), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: cyan),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onBackground.withOpacity(0.80),
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentMethodPanel extends StatelessWidget {
  final bool hasSavedCard;
  final String brand;
  final String last4;
  final VoidCallback onManage;

  const _PaymentMethodPanel({
    required this.hasSavedCard,
    required this.brand,
    required this.last4,
    required this.onManage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final title = hasSavedCard ? 'Método de pago listo ✅' : 'Falta método de pago';
    final subtitle = hasSavedCard
        ? (brand.isNotEmpty && last4.isNotEmpty
            ? '$brand • **** $last4'
            : 'Tarjeta guardada')
        : 'Guarda un método de pago para poder publicar ofertas.';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            hasSavedCard ? Icons.credit_card : Icons.warning_amber_rounded,
            color: hasSavedCard ? cs.primary : Colors.redAccent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onBackground.withOpacity(0.75),
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: onManage,
            child: Text(hasSavedCard ? 'Administrar' : 'Guardar'),
          ),
        ],
      ),
    );
  }
}
  
