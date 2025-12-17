import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // para vibración
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:just_audio/just_audio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart'; // para kIsWeb

import 'home_tab.dart';
import 'offers_page.dart';
import 'profile_page.dart';
import 'incoming_companion_dialog.dart';
import '../features/sessions/ui/session_screen.dart';
import 'waiting_for_speaker_screen.dart';
import '../features/explorer/ui/explore_profiles_screen.dart';

class LissenHome extends StatefulWidget {
  const LissenHome({super.key});

  @override
  State<LissenHome> createState() => _LissenHomeState();
}

class _LissenHomeState extends State<LissenHome> {
  int _index = 0;

  // ============================
  // PESTAÑAS PRINCIPALES
  // ============================
  final List<Widget> _pages = [
    HomeTab(), // 0: Inicio
    const OffersPage(), // 1: Ofertas
    const ExploreProfilesScreen(), // 2: Explorar
    const ProfilePage(), // 3: Perfil
  ];

  // ============================
  // AUDIO + VIBRACIÓN TIPO LLAMADA
  // ============================
  late final AudioPlayer _incomingPlayer;
  bool _audioReady = false;
  Timer? _vibrationTimer;

  bool _playerDisposed = false;

  bool _audioInitialized = false;
  bool _locationRequested = false;

  // ============================
  // LISTENER GLOBAL DE OFERTAS (HABLANTE)
  // ============================
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _pendingOffersSub;

  bool _isDecisionModalOpen = false;
  String? _currentPendingOfferId;
  bool _busy = false;

  // ============================
  // RESTAURAR PANTALLAS PEGADAS
  // ============================
  bool _stickyRestoreRunning = false;
  bool _stickyRestoredOnce = false;

  @override
  void initState() {
    super.initState();

    _incomingPlayer = AudioPlayer();

    _setupGlobalPendingListener();

    if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initUserLocation();
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreStickyScreensIfNeeded();
    });
  }

  Future<void> _loadIncomingSound() async {
    if (_playerDisposed || _audioInitialized) return;

    try {
      await _incomingPlayer.setAsset('assets/sounds/offer_request.wav');
      if (_playerDisposed) return;
      _audioReady = true;
      _audioInitialized = true;
    } catch (e) {
      debugPrint('❌ Error cargando sonido offer_request.wav: $e');
      _audioReady = false;
      _audioInitialized = false;
    }
  }

  Future<void> _initUserLocation() async {
    if (_locationRequested) return;
    _locationRequested = true;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
      }

      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'geoLat': position.latitude,
        'geoLng': position.longitude,
        'geoUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('❌ Error obteniendo ubicación: $e');
    }
  }

  Future<void> _startCallAlert() async {
    if (_playerDisposed) return;

    if (!_audioInitialized) {
      await _loadIncomingSound();
    }

    if (!_audioReady || _playerDisposed) return;

    try {
      await _incomingPlayer.setLoopMode(LoopMode.off);
      await _incomingPlayer.stop();
      await _incomingPlayer.seek(Duration.zero);
      await _incomingPlayer.play();
      HapticFeedback.heavyImpact();
    } catch (e) {
      debugPrint('❌ Error reproduciendo sonido inicial: $e');
    }

    _vibrationTimer?.cancel();
    _vibrationTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!_audioReady || _playerDisposed) return;

      try {
        await _incomingPlayer.stop();
        await _incomingPlayer.seek(Duration.zero);
        await _incomingPlayer.play();
        HapticFeedback.heavyImpact();
      } catch (e) {
        debugPrint('❌ Error en beep periódico: $e');
      }
    });
  }

  Future<void> _stopCallAlert() async {
    if (_playerDisposed) return;

    try {
      await _incomingPlayer.stop();
    } catch (_) {}
    _vibrationTimer?.cancel();
    _vibrationTimer = null;
  }

  void _setupGlobalPendingListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _pendingOffersSub?.cancel();

    final query = FirebaseFirestore.instance
        .collection('offers')
        .where('pendingSpeakerId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'pending_speaker');

    _pendingOffersSub = query.snapshots().listen((snapshot) {
      if (!mounted) return;

      if (snapshot.docs.isEmpty) {
        _currentPendingOfferId = null;

        if (_isDecisionModalOpen) {
          _stopCallAlert();
          Navigator.of(context, rootNavigator: true).maybePop();
          _isDecisionModalOpen = false;
        }
        return;
      }

      final doc = snapshot.docs.first;
      final offerId = doc.id;

      if (_isDecisionModalOpen && _currentPendingOfferId == offerId) {
        return;
      }

      if (_currentPendingOfferId != offerId) {
        _currentPendingOfferId = offerId;
        _showGlobalDecisionModalForOffer(doc);
      }
    });
  }

  Future<void> _showGlobalDecisionModalForOffer(
    QueryDocumentSnapshot<Map<String, dynamic>> pendingDoc,
  ) async {
    if (_isDecisionModalOpen || _busy) return;

    _isDecisionModalOpen = true;

    final offerId = pendingDoc.id;
    final offerData = pendingDoc.data();

    final companionAlias =
        (offerData['pendingCompanionAlias'] ?? 'Compañera').toString();

    final companionUid =
        (offerData['pendingCompanionId'] ?? '').toString().trim();

    int durationMinutes =
        offerData['durationMinutes'] ?? offerData['minMinutes'] ?? 0;
    if (durationMinutes is! int) {
      durationMinutes = int.tryParse(durationMinutes.toString()) ?? 0;
    }

    int rawTotalMinCents =
        offerData['totalMinAmountCents'] ?? offerData['priceCents'] ?? 0;

    if (rawTotalMinCents == 0) {
      final int pricePerMinuteCents = offerData['pricePerMinuteCents'] ?? 0;
      if (pricePerMinuteCents > 0 && durationMinutes > 0) {
        rawTotalMinCents = pricePerMinuteCents * durationMinutes;
      }
    }

    final double amountUsd = rawTotalMinCents / 100.0;
    final String currency = (offerData['currency'] ?? 'usd').toString();
    final String communicationType =
        (offerData['communicationType'] ?? 'chat').toString();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _isDecisionModalOpen = false;
        return;
      }

      await _startCallAlert();

      final result = await showIncomingCompanionDialog(
        context: context,
        companionAlias: companionAlias,
        durationMinutes: durationMinutes,
        amountUsd: amountUsd,
        currency: currency,
        communicationType: communicationType,
        companionUid: companionUid,
      );

      await _stopCallAlert();

      if (!mounted) {
        _isDecisionModalOpen = false;
        return;
      }

      if (result == true) {
        await _handleSpeakerAccept(offerId: offerId, offerData: offerData);
      } else if (result == false) {
        await _handleSpeakerReject(offerId: offerId);
      }

      _isDecisionModalOpen = false;
    });
  }

  Future<void> _handleSpeakerReject({required String offerId}) async {
    if (_busy) return;
    _busy = true;

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;
      final uid = currentUser.uid;

      final result =
          await FirebaseFirestore.instance.runTransaction<String>((tx) async {
        final offerRef =
            FirebaseFirestore.instance.collection('offers').doc(offerId);
        final offerSnap = await tx.get(offerRef);

        if (!offerSnap.exists) {
          return 'not_exists';
        }

        final data = offerSnap.data() as Map<String, dynamic>;
        final status = (data['status'] ?? 'active') as String;
        final speakerId = (data['speakerId'] ?? '') as String;
        final pendingCompanionId = (data['pendingCompanionId'] ?? '') as String?;
        final lastSessionId = (data['lastSessionId'] ?? '') as String?;

        if (status == 'used' &&
            lastSessionId != null &&
            lastSessionId.isNotEmpty) {
          return 'already_used';
        }

        if (status == 'pending_speaker' &&
            speakerId == uid &&
            pendingCompanionId != null &&
            pendingCompanionId.isNotEmpty &&
            (lastSessionId == null || lastSessionId.isEmpty)) {
          tx.update(offerRef, {
            'status': 'active',
            'pendingSpeakerId': FieldValue.delete(),
            'pendingCompanionId': FieldValue.delete(),
            'pendingCompanionAlias': FieldValue.delete(),
            'pendingSince': FieldValue.delete(),
            'rejectedBySpeakerId': uid,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          return 'ok';
        }

        return 'not_pending';
      });

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
          const SnackBar(content: Text('La sesión ya está activa.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La solicitud ya no estaba pendiente.')),
        );
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _handleSpeakerAccept({
    required String offerId,
    required Map<String, dynamic> offerData,
  }) async {
    if (_busy) return;
    _busy = true;

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;
      final uid = currentUser.uid;

      final result = await FirebaseFirestore.instance
          .runTransaction<Map<String, dynamic>>((tx) async {
        final offerRef =
            FirebaseFirestore.instance.collection('offers').doc(offerId);
        final offerSnap = await tx.get(offerRef);

        if (!offerSnap.exists) {
          return {'result': 'not_exists'};
        }

        final data = offerSnap.data() as Map<String, dynamic>;
        final status = (data['status'] ?? 'active') as String;
        final speakerId = (data['speakerId'] ?? '') as String;
        final pendingCompanionId = (data['pendingCompanionId'] ?? '') as String?;
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
          final sessionsRef = FirebaseFirestore.instance.collection('sessions');
          final newSessionRef = sessionsRef.doc();

          final speakerAlias = (data['speakerAlias'] ?? 'Hablante').toString();
          final companionAlias =
              (data['pendingCompanionAlias'] ?? 'Compañera').toString();
          final durationMinutes =
              (data['durationMinutes'] ?? data['minMinutes'] ?? 30) as int;
          final int rawPriceCents =
              (data['priceCents'] ?? data['totalMinAmountCents'] ?? 0) as int;
          final communicationType =
              (data['communicationType'] ?? 'chat').toString();
          final currency = (data['currency'] ?? 'usd').toString();

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
          });

          tx.update(offerRef, {
            'status': 'used',
            'lastSessionId': newSessionRef.id,
            'pendingSpeakerId': FieldValue.delete(),
            'pendingCompanionId': FieldValue.delete(),
            'pendingCompanionAlias': FieldValue.delete(),
            'pendingSince': FieldValue.delete(),
            'updatedAt': FieldValue.serverTimestamp(),
          });

          return {'result': 'ok', 'sessionId': newSessionRef.id};
        }

        return {'result': 'not_pending'};
      });

      if (!mounted) return;

      final res = result['result'] as String;

      if (res == 'ok' || res == 'already_used') {
        final sessionId = result['sessionId'] as String?;
        if (sessionId != null && sessionId.isNotEmpty) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SessionConversationScreen(sessionId: sessionId),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La solicitud ya no está disponible.')),
        );
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _restoreStickyScreensIfNeeded() async {
    if (!mounted) return;
    if (_stickyRestoreRunning || _stickyRestoredOnce) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _stickyRestoreRunning = true;
    final uid = user.uid;

    try {
      final sessionsRef = FirebaseFirestore.instance.collection('sessions');

      QuerySnapshot<Map<String, dynamic>> sessionsSnap = await sessionsRef
          .where('status', isEqualTo: 'active')
          .where('speakerId', isEqualTo: uid)
          .limit(1)
          .get();

      if (sessionsSnap.docs.isEmpty) {
        sessionsSnap = await sessionsRef
            .where('status', isEqualTo: 'active')
            .where('companionId', isEqualTo: uid)
            .limit(1)
            .get();
      }

      if (sessionsSnap.docs.isNotEmpty) {
        final sessionId = sessionsSnap.docs.first.id;
        if (!mounted) return;

        _stickyRestoredOnce = true;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SessionConversationScreen(sessionId: sessionId),
          ),
        );
        return;
      }

      final offersSnap = await FirebaseFirestore.instance
          .collection('offers')
          .where('status', isEqualTo: 'pending_speaker')
          .where('pendingCompanionId', isEqualTo: uid)
          .limit(1)
          .get();

      if (offersSnap.docs.isNotEmpty) {
        final offerId = offersSnap.docs.first.id;
        final speakerAlias =
            (offersSnap.docs.first.data()['speakerAlias'] ?? 'Hablante')
                .toString();

        if (!mounted) return;

        _stickyRestoredOnce = true;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => WaitingForSpeakerScreen(
              offerId: offerId,
              speakerAlias: speakerAlias,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error restaurando pantallas pegadas: $e');
    } finally {
      _stickyRestoreRunning = false;
    }
  }

  @override
  void dispose() {
    _playerDisposed = true;

    _pendingOffersSub?.cancel();
    _vibrationTimer?.cancel();

    try {
      _incomingPlayer.dispose();
    } catch (_) {}

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      body: Stack(
        children: [
          // Mantiene vivas las pantallas (no se reinician al cambiar)
          IndexedStack(
            index: _index,
            children: _pages,
          ),

          // 4 botones flotantes
          Positioned(
            left: 12,
            right: 12,
            bottom: 10 + bottomPad,
            child: _FloatingQuadNav(
              index: _index,
              onTap: (i) => setState(() => _index = i),
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingQuadNav extends StatelessWidget {
  final int index;
  final void Function(int) onTap;

  const _FloatingQuadNav({
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget btn({
      required int i,
      required IconData icon,
      required String label,
    }) {
      final selected = i == index;

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            elevation: selected ? 10 : 6,
            shape: const CircleBorder(),
            color: selected
                ? theme.colorScheme.primary.withOpacity(0.95)
                : Colors.black.withOpacity(0.55),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => onTap(i),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(
                  icon,
                  size: 24,
                  color: selected ? Colors.black : Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? theme.colorScheme.primary : Colors.white70,
            ),
          ),
        ],
      );
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            btn(i: 0, icon: Icons.home_outlined, label: 'Inicio'),
            btn(i: 1, icon: Icons.local_offer_outlined, label: 'Ofertas'),
            btn(i: 2, icon: Icons.explore_outlined, label: 'Explorar'),
            btn(i: 3, icon: Icons.person_outline, label: 'Perfil'),
          ],
        ),
      ),
    );
  }
}

