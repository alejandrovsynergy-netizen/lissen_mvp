import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lissen_mvp/screens/create_offer_dialog.dart';

import 'public_profile_screen.dart'; // PublicProfileBody

class ExploreProfilesScreen extends StatefulWidget {
  const ExploreProfilesScreen({super.key});

  @override
  State<ExploreProfilesScreen> createState() => _ExploreProfilesScreenState();
}

class _ExploreProfilesScreenState extends State<ExploreProfilesScreen> {
  // ✅ Stream estable del "me"
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _meStream;
  String? _meUid;

  // ✅ Streams estables por rol objetivo (para NO recrearlos en cada build)
  final Map<String, Stream<QuerySnapshot<Map<String, dynamic>>>> _usersStreamsByRole = {};

  // ✅ Orden estable
  List<String> _stableOrderIds = const [];
  int _stableHash = 0;

  // ✅ Índice actual
  int _index = 0;

  void _ensureStreamsForUser(String uid) {
    if (_meUid == uid && _meStream != null) return;

    _meUid = uid;
    _meStream = FirebaseFirestore.instance.collection('users').doc(uid).snapshots();

    // si cambió de usuario, resetea caches y orden
    _usersStreamsByRole.clear();
    _stableOrderIds = const [];
    _stableHash = 0;
    _index = 0;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _usersStreamForRole(String targetRole) {
    return _usersStreamsByRole.putIfAbsent(
      targetRole,
      () => FirebaseFirestore.instance
          .collection('users')
          .where('onboardingCompleted', isEqualTo: true)
          .where('role', isEqualTo: targetRole)
          .snapshots(),
    );
  }

  void _setStableOrderIfChanged(List<String> ids) {
    final h = Object.hashAll(ids);
    if (h == _stableHash) return;

    _stableHash = h;
    _stableOrderIds = ids;
    _index = 0;
    // OJO: NO hacemos setState aquí porque esto se llama dentro de build()
    // y el build actual ya va a pintar con el nuevo orden.
  }

  void _goNext(int total) {
    if (total <= 0) return;
    setState(() => _index = (_index + 1) % total);
  }

  void _goPrev(int total) {
    if (total <= 0) return;
    setState(() => _index = (_index - 1 + total) % total);
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const Scaffold(
        body: SafeArea(
          child: Center(child: Text('Debes iniciar sesion.')),
        ),
      );
    }

    final myUid = currentUser.uid;
    _ensureStreamsForUser(myUid);

    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _meStream,
          builder: (context, meSnap) {
            // ✅ Solo loader si aún NO hay data (evita blink)
            if (meSnap.connectionState == ConnectionState.waiting && !meSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (meSnap.hasError || !meSnap.hasData || !meSnap.data!.exists) {
              return const Center(child: Text('Error cargando tu perfil.'));
            }

            final me = meSnap.data!.data() ?? {};
            final myRole = (me['role'] as String?) ?? 'speaker';
            final targetRole = (myRole == 'speaker') ? 'companion' : 'speaker';
            final canMakeOffer = myRole == 'speaker';

            final double? myLat = _asDouble(me['geoLat']);
            final double? myLng = _asDouble(me['geoLng']);
            final bool hasMyGeo = myLat != null && myLng != null;

            final myAlias = (me['alias'] ?? me['displayName'] ?? '').toString();
            final myCountry = (me['country'] ?? '').toString();
            final myCity = (me['city'] ?? '').toString();
            final myPhotoUrl = (me['photoUrl'] ?? '').toString();
            final myBio = (me['bio'] ?? '').toString();

            final usersStream = _usersStreamForRole(targetRole);

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: usersStream,
              builder: (context, snapshot) {
                // ✅ Solo loader si aún NO hay data (evita blink)
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const Center(child: Text('Error cargando perfiles.'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs.where((d) => d.id != myUid).toList();

                // Map por id para usar data actual SIN cambiar el orden
                final mapById = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
                for (final d in docs) {
                  mapById[d.id] = d;
                }

                // Orden calculado (cercanía si hay geo)
                List<String> computedOrderIds;
                if (hasMyGeo) {
                  final withGeo = <_IdWithDist>[];
                  final withoutGeo = <String>[];

                  for (final d in docs) {
                    final data = d.data();
                    final lat = _asDouble(data['geoLat']);
                    final lng = _asDouble(data['geoLng']);
                    if (lat == null || lng == null) {
                      withoutGeo.add(d.id);
                      continue;
                    }
                    final distKm = _haversineKm(myLat!, myLng!, lat, lng);
                    withGeo.add(_IdWithDist(id: d.id, distKm: distKm));
                  }

                  withGeo.sort((a, b) => a.distKm.compareTo(b.distKm));
                  computedOrderIds = [
                    ...withGeo.map((e) => e.id),
                    ...withoutGeo,
                  ];
                } else {
                  computedOrderIds = docs.map((e) => e.id).toList();
                }

                // ✅ fija un orden estable (sin setState extra)
                _setStableOrderIfChanged(computedOrderIds);

                // Lista final con orden estable + data actual
                final orderedDocs = _stableOrderIds
                    .map((id) => mapById[id])
                    .whereType<QueryDocumentSnapshot<Map<String, dynamic>>>()
                    .toList();

                final bottomInset = MediaQuery.of(context).padding.bottom + 90;

                return Padding(
                  padding: EdgeInsets.only(bottom: bottomInset),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
                        child: _ExploreHeader(),
                      ),

                    if (!hasMyGeo)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Activa ubicacion para ordenar perfiles por cercania.',
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.location_on_outlined),
                              onPressed: () async {
                                final ok = await _requestAndSaveLocation(myUid);
                                if (!ok && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Permiso de ubicacion no concedido.',
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ),

                    if (orderedDocs.isEmpty)
                      const Expanded(
                        child: Center(
                          child: Text('No hay perfiles disponibles.'),
                        ),
                      )
                    else
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, c) {
                            final screenH = MediaQuery.of(context).size.height;
                            final cardH = math.min(screenH * 0.72, 560.0);

                            final total = orderedDocs.length;
                            final safeIndex = (_index % total + total) % total;

                            final current = orderedDocs[safeIndex];
                            final next = (total > 1) ? orderedDocs[(safeIndex + 1) % total] : null;

                            return Column(
                              children: [
                                Expanded(
                                  child: Center(
                                    child: SizedBox(
                                      height: cardH,
                                      child: _TinderDeck(
                                        key: ValueKey('deck_${_stableHash}'),
                                        hasPrev: total > 1,
                                        hasNext: total > 1,
                                        backgroundCard: next == null
                                            ? null
                                            : _SwipeProfileCard(
                                                key: ValueKey('bg_${next.id}'),
                                                userId: next.id,
                                                data: next.data(),
                                                onViewProfile: () {
                                                  Navigator.of(context).push(
                                                    MaterialPageRoute(
                                                      builder: (_) => PublicProfileScreen(
                                                        companionUid: next.id,
                                                      ),
                                                    ),
                                                  );
                                                },
                                                onMakeOffer: canMakeOffer
                                                    ? () async {
                                                        final data = next.data();
                                                        final companionCode = (data['companionCode'] ?? '')
                                                            .toString()
                                                            .trim();

                                                        await showCreateOfferDialog(
                                                          context: context,
                                                          userId: myUid,
                                                          alias: myAlias,
                                                          country: myCountry,
                                                          city: myCity,
                                                          photoUrl: myPhotoUrl,
                                                          bio: myBio,
                                                          prefillCompanionCode: companionCode.isNotEmpty ? companionCode : null,
                                                        );
                                                      }
                                                    : null,
                                              ),
                                        topCard: _SwipeProfileCard(
                                          key: ValueKey('top_${current.id}'),
                                          userId: current.id,
                                          data: current.data(),
                                          onViewProfile: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) => PublicProfileScreen(
                                                  companionUid: current.id,
                                                ),
                                              ),
                                            );
                                          },
                                          onMakeOffer: canMakeOffer
                                              ? () async {
                                                  final data = current.data();
                                                  final companionCode = (data['companionCode'] ?? '')
                                                      .toString()
                                                      .trim();

                                                  await showCreateOfferDialog(
                                                    context: context,
                                                    userId: myUid,
                                                    alias: myAlias,
                                                    country: myCountry,
                                                    city: myCity,
                                                    photoUrl: myPhotoUrl,
                                                    bio: myBio,
                                                    prefillCompanionCode: companionCode.isNotEmpty ? companionCode : null,
                                                  );
                                                }
                                              : null,
                                        ),

                                        // ✅ Swipe izquierda = siguiente
                                        onSwipeLeft: () => _goNext(total),

                                        // ✅ Swipe derecha = anterior
                                        onSwipeRight: () => _goPrev(total),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.35),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      '${(safeIndex + 1).clamp(1, total)} / $total',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  static Future<bool> _requestAndSaveLocation(String uid) async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      return false;
    }

    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.low,
    );

    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'geoLat': pos.latitude,
      'geoLng': pos.longitude,
    }, SetOptions(merge: true));

    return true;
  }

  static double? _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return null;
  }

  static double _haversineKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const r = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  static double _deg2rad(double deg) => deg * (math.pi / 180.0);
}

/// ✅ Deck Tinder: una tarjeta arriba, la siguiente atrás.
class _TinderDeck extends StatefulWidget {
  final Widget topCard;
  final Widget? backgroundCard;
  final VoidCallback onSwipeLeft; // siguiente
  final VoidCallback onSwipeRight; // anterior

  final bool hasNext;
  final bool hasPrev;

  const _TinderDeck({
    super.key,
    required this.topCard,
    required this.backgroundCard,
    required this.onSwipeLeft,
    required this.onSwipeRight,
    required this.hasNext,
    required this.hasPrev,
  });

  @override
  State<_TinderDeck> createState() => _TinderDeckState();
}

class _TinderDeckState extends State<_TinderDeck> with SingleTickerProviderStateMixin {
  Offset _offset = Offset.zero;

  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  late Animation<Offset> _offsetAnim;
  VoidCallback? _offsetListener;

  @override
  void dispose() {
    if (_offsetListener != null) {
      _offsetAnim.removeListener(_offsetListener!);
    }
    _anim.dispose();
    super.dispose();
  }

  void _animateTo(Offset target, VoidCallback? onDone) {
    // limpia listener anterior (si existía)
    if (_offsetListener != null) {
      _offsetAnim.removeListener(_offsetListener!);
      _offsetListener = null;
    }

    _offsetAnim = Tween<Offset>(begin: _offset, end: target).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic),
    );

    final listener = () {
      setState(() => _offset = _offsetAnim.value);
    };
    _offsetListener = listener;
    _offsetAnim.addListener(listener);

    _anim
      ..stop()
      ..reset();

    _anim.forward().whenComplete(() {
      // quita el listener correcto (mismo closure)
      _offsetAnim.removeListener(listener);
      if (_offsetListener == listener) _offsetListener = null;
      onDone?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    // Umbral: si arrastras más de esto, cambia
    final threshold = size.width * 0.22;

    final canGoNext = widget.hasNext;
    final canGoPrev = widget.hasPrev;

    // Rotación leve para sentir “tinder”
    final rotation = (_offset.dx / size.width) * 0.10;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (widget.backgroundCard != null)
          Transform.scale(
            scale: 0.96,
            child: Opacity(
              opacity: 0.95,
              child: RepaintBoundary(child: widget.backgroundCard!),
            ),
          ),

        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanUpdate: (d) {
            setState(() {
              _offset += d.delta;
            });
          },
          onPanEnd: (_) {
            // Izquierda = siguiente
            if (_offset.dx < -threshold && canGoNext) {
              final target = Offset(-size.width * 1.2, 0);
              _animateTo(target, () {
                setState(() => _offset = Offset.zero);
                widget.onSwipeLeft();
              });
              return;
            }

            // Derecha = anterior
            if (_offset.dx > threshold && canGoPrev) {
              final target = Offset(size.width * 1.2, 0);
              _animateTo(target, () {
                setState(() => _offset = Offset.zero);
                widget.onSwipeRight();
              });
              return;
            }

            // Si no pasó el umbral: regresa suave al centro
            _animateTo(Offset.zero, null);
          },
          child: RepaintBoundary(
            child: Transform.translate(
              offset: _offset,
              child: Transform.rotate(
                angle: rotation,
                child: widget.topCard,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _IdWithDist {
  final String id;
  final double distKm;
  _IdWithDist({required this.id, required this.distKm});
}

class _SwipeProfileCard extends StatefulWidget {
  final String userId;
  final Map<String, dynamic> data;
  final VoidCallback onViewProfile;
  final VoidCallback? onMakeOffer;

  const _SwipeProfileCard({
    super.key,
    required this.userId,
    required this.data,
    required this.onViewProfile,
    required this.onMakeOffer,
  });

  @override
  State<_SwipeProfileCard> createState() => _SwipeProfileCardState();
}

class _SwipeProfileCardState extends State<_SwipeProfileCard> {
  late final PageController _photoController;
  int _photoIndex = 0;

  @override
  void initState() {
    super.initState();
    _photoController = PageController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ✅ precache para reducir “flash” al cambiar de perfil
    final urls = _photoUrls(widget.data);
    for (final u in urls.take(2)) {
      precacheImage(NetworkImage(u), context);
    }
  }

  @override
  void dispose() {
    _photoController.dispose();
    super.dispose();
  }

  String _formatGender(dynamic gender) {
    final g = (gender ?? '').toString().toLowerCase();
    switch (g) {
      case 'male':
        return 'Hombre';
      case 'female':
        return 'Mujer';
      case 'non_binary':
        return 'No binario';
      default:
        return gender?.toString() ?? '';
    }
  }

  String _locationLine({
    required String city,
    required String country,
  }) {
    final parts = [city.trim(), country.trim()].where((e) => e.isNotEmpty);
    return parts.join(', ');
  }

  String _pickPhotoUrl(Map<String, dynamic> data) {
    final primary = (data['photoUrl'] ?? data['profilePhotoUrl'] ?? '').toString().trim();
    if (primary.isNotEmpty) return primary;

    final gallery = (data['galleryPhotos'] as List<dynamic>?)
            ?.cast<String>()
            .where((e) => e.trim().isNotEmpty)
            .toList() ??
        const <String>[];
    if (gallery.isNotEmpty) return gallery.first;

    return '';
  }

  List<String> _photoUrls(Map<String, dynamic> data) {
    final urls = <String>[];

    final primary = _pickPhotoUrl(data);
    if (primary.isNotEmpty) urls.add(primary);

    final galleryPhotos = (data['galleryPhotos'] as List<dynamic>?)
            ?.map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList() ??
        const <String>[];

    final galleryLegacy = (data['gallery'] as List<dynamic>?)
            ?.map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList() ??
        const <String>[];

    for (final url in [...galleryPhotos, ...galleryLegacy]) {
      if (!urls.contains(url)) {
        urls.add(url);
      }
    }

    return urls;
  }

  void _goToPhoto(int index, int total) {
    if (index < 0 || index >= total) return;
    setState(() => _photoIndex = index);
    _photoController.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final alias = (widget.data['alias'] ?? 'Usuario').toString().trim();
    final age = widget.data['age'];
    final gender = _formatGender(widget.data['gender']);
    final city = (widget.data['city'] ?? '').toString();
    final country = (widget.data['country'] ?? '').toString();
    final location = _locationLine(city: city, country: country);
    final bio = (widget.data['bio'] ?? '').toString();
    final isOnline = widget.data['isOnline'] == true;

    final photos = _photoUrls(widget.data);
    final hasPhotos = photos.isNotEmpty;
    final hasMultiplePhotos = photos.length > 1;
    final clampedIndex = _photoIndex.clamp(0, hasPhotos ? photos.length - 1 : 0);

    if (clampedIndex != _photoIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _goToPhoto(clampedIndex, photos.length);
      });
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasPhotos)
              IgnorePointer(
                child: PageView.builder(
                  controller: _photoController,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: photos.length,
                  itemBuilder: (context, index) {
                    return Image.network(
                      photos[index],
                      fit: BoxFit.cover,
                      gaplessPlayback: true, // ✅ reduce flash al cambiar
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return Container(
                          color: Colors.black12,
                          alignment: Alignment.center,
                          child: const SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      },
                    );
                  },
                ),
              )
            else
              Container(
                color: Colors.blueGrey.shade200,
                child: const Icon(Icons.person, size: 120, color: Colors.white),
              ),

            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.15),
                    Colors.black.withOpacity(0.65),
                  ],
                ),
              ),
            ),

            if (hasMultiplePhotos)
              Align(
                alignment: const Alignment(-0.96, 0.0),
                child: _NavButton(
                  icon: Icons.chevron_left,
                  enabled: _photoIndex > 0,
                  onTap: () => _goToPhoto(_photoIndex - 1, photos.length),
                ),
              ),
            if (hasMultiplePhotos)
              Align(
                alignment: const Alignment(0.96, 0.0),
                child: _NavButton(
                  icon: Icons.chevron_right,
                  enabled: _photoIndex < photos.length - 1,
                  onTap: () => _goToPhoto(_photoIndex + 1, photos.length),
                ),
              ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isOnline ? Colors.green : Colors.grey,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isOnline ? 'En linea' : 'Desconectado',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const Spacer(),

                  Text(
                    alias.isNotEmpty ? alias : 'Usuario',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (age != null) '$age años',
                      if (gender.isNotEmpty) gender,
                    ].join(' • '),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (location.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (bio.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      bio,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withOpacity(0.9),
                        height: 1.2,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: widget.onViewProfile,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white70),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          child: const Text('Ver perfil'),
                        ),
                      ),
                      if (widget.onMakeOffer != null) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: widget.onMakeOffer,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            child: const Text('Hacer oferta'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _NavButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1.0 : 0.35,
      child: IconButton(
        iconSize: 34,
        color: Colors.white,
        onPressed: enabled ? onTap : null,
        icon: Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.35),
            shape: BoxShape.circle,
          ),
          padding: const EdgeInsets.all(6),
          child: Icon(icon),
        ),
      ),
    );
  }
}

class _ExploreHeader extends StatelessWidget {
  const _ExploreHeader();

  @override
  Widget build(BuildContext context) {
    const cyanGlow = Color(0xFF22D3EE);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _GlowTitle(text: 'Lissen', glowColor: cyanGlow),
        const SizedBox(height: 10),
        _SectionHeader(
          icon: Icons.explore_outlined,
          iconBg: cyanGlow.withOpacity(0.12),
          iconColor: cyanGlow,
          title: 'Explorar',
        ),
        const SizedBox(height: 6),
        Text(
          'Descubre personas para conversar en minutos.',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: cs.onBackground.withOpacity(0.80),
          ),
        ),
      ],
    );
  }
}

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
