import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Clipboard
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:video_player/video_player.dart';
import 'package:firebase_auth/firebase_auth.dart'; // <-- para saber quién ve el perfil

// ====== Tarifas mínimas estándar (centavos MXN) ======
const int kMinChat15Cents = 7000; // $70
const int kMinVoice15Cents = 10500; // $105
const int kMinVideo15Cents = 15500; // $155

// ============================
// 🎨 Gradiente principal (Tailwind)
// from-slate-900/95 via-blue-900/95 to-slate-800/95
// ============================
const Color _slate900 = Color(0xFF0F172A);
const Color _slate800 = Color(0xFF1E293B);
const Color _blue900 = Color(0xFF1E3A8A);

final LinearGradient kProfileCardGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [
    _slate900.withOpacity(0.95),
    _blue900.withOpacity(0.95),
    _slate800.withOpacity(0.95),
  ],
);

class PublicProfileScreen extends StatelessWidget {
  final String companionUid;
  final void Function(String companionUid, Map<String, dynamic> profileData)?
      onMakeOffer;
  final bool enableMakeOfferButton;

  const PublicProfileScreen({
    super.key,
    required this.companionUid,
    this.onMakeOffer,
    this.enableMakeOfferButton = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(companionUid)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _ErrorView(error: snapshot.error.toString());
            }

            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final doc = snapshot.data!;
            if (!doc.exists) {
              return const _ErrorView(
                error: 'Este perfil ya no está disponible.',
              );
            }

            final data = doc.data() ?? <String, dynamic>{};

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: PublicProfileBody(
                userId: doc.id,
                data: data,
                showCloseButton: true,
                onClose: () => Navigator.of(context).pop(),
                onMakeOffer: enableMakeOfferButton && onMakeOffer != null
                    ? () => onMakeOffer!(companionUid, data)
                    : null,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  const _ErrorView({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(error, textAlign: TextAlign.center));
  }
}

/// Cuerpo reutilizable del perfil público.
class PublicProfileBody extends StatefulWidget {
  final Map<String, dynamic> data;
  final String? userId; // uid del dueño del perfil (doc id)
  final bool showCloseButton;
  final VoidCallback? onClose;
  final VoidCallback? onMakeOffer;

  const PublicProfileBody({
    super.key,
    required this.data,
    this.userId,
    this.showCloseButton = false,
    this.onClose,
    this.onMakeOffer,
  });

  @override
  State<PublicProfileBody> createState() => _PublicProfileBodyState();
}

class _PublicProfileBodyState extends State<PublicProfileBody> {
  late PageController _photosPageController;
  late PageController _videosPageController;

  late bool _isSpeaker;
  late bool _isCompanion;
  late String _role;

  bool _showingPhotos = true;

  // Galería cargada desde subcolección
  List<String>? _galleryPhotosFromSubcollection;
  List<String>? _galleryVideosFromSubcollection;
  String? _galleryError;
  bool _galleryLoaded = false;

  // Usuario que está viendo este perfil
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _photosPageController = PageController();
    _videosPageController = PageController();

    _role = (widget.data['role'] ?? 'speaker') as String;
    _isSpeaker = _role == 'speaker';
    _isCompanion = _role == 'companion';

    _currentUserId = _auth.currentUser?.uid;

    _loadGalleryFromSubcollection();
  }

  @override
  void dispose() {
    _photosPageController.dispose();
    _videosPageController.dispose();
    super.dispose();
  }

  Future<void> _loadGalleryFromSubcollection() async {
    final String? uid = widget.userId ?? (widget.data['uid'] as String?);

    if (uid == null) {
      setState(() {
        _galleryLoaded = true;
      });
      return;
    }

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('gallery')
          .orderBy('createdAt', descending: false)
          .get();

      final List<String> photos = [];
      final List<String> videos = [];

      for (final doc in snap.docs) {
        final gData = doc.data();
        final url = (gData['url'] ?? '') as String;
        if (url.isEmpty) continue;
        final type = (gData['type'] ?? 'image').toString();

        if (type == 'video') {
          videos.add(url);
        } else {
          photos.add(url);
        }
      }

      if (!mounted) return;
      setState(() {
        _galleryPhotosFromSubcollection = photos;
        _galleryVideosFromSubcollection = videos;
        _galleryLoaded = true;
        _galleryError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _galleryError = e.toString();
        _galleryLoaded = true;
      });
    }
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
        return gender?.toString() ?? 'No especificado';
    }
  }

  (String daysText, String hoursText) _availabilityParts() {
    final days = (widget.data['availabilityDays'] as List<dynamic>?) ?? [];
    if (days.isEmpty) return ('Sin horario definido', '');

    final dayNames = {
      1: 'Lun',
      2: 'Mar',
      3: 'Mié',
      4: 'Jue',
      5: 'Vie',
      6: 'Sáb',
      7: 'Dom',
    };

    final sorted = days.whereType<int>().where((d) => d >= 1 && d <= 7).toList()
      ..sort();

    final startHour = widget.data['availabilityStartHour'];
    final endHour = widget.data['availabilityEndHour'];

    final hoursText = (startHour is int && endHour is int)
        ? '${startHour.toString().padLeft(2, '0')}:00 - ${endHour.toString().padLeft(2, '0')}:00'
        : 'Horario no definido';

    final daysText = sorted.map((d) => dayNames[d] ?? '').join(', ');
    if (daysText.isEmpty) return ('Sin horario definido', '');

    return (daysText, hoursText);
  }

  String _formatRate(int? cents, int fallbackCents) {
    final effective = cents ?? fallbackCents;
    final value = effective / 100.0;
    return '\$${value.toStringAsFixed(0)} MXN';
  }

  void _openFullScreenMedia({
    required List<String> items,
    required int initialIndex,
    required bool isVideo,
  }) {
    if (items.isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullScreenMediaViewer(
          items: items,
          initialIndex: initialIndex,
          isVideo: isVideo,
        ),
      ),
    );
  }

  // ============================================================
  // LÓGICA: REPORTAR PERFIL
  // ============================================================
  Future<void> _handleReport() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final reportedUid = widget.userId;

    if (currentUser == null || reportedUid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes iniciar sesión para reportar.')),
      );
      return;
    }

    if (currentUser.uid == reportedUid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No puedes reportarte a ti mismo.')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reportar perfil'),
        content: const Text(
          '¿Deseas reportar este perfil por comportamiento inapropiado?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reportar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance.collection('reports').add({
        'reporterUid': currentUser.uid,
        'reportedUid': reportedUid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Reporte enviado.')));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error al reportar: $e')));
    }
  }

  // ============================================================
  // LÓGICA: BLOQUEAR PERFIL
  // ============================================================
  Future<void> _handleBlock() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final blockedUid = widget.userId;

    if (currentUser == null || blockedUid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes iniciar sesión para bloquear.')),
      );
      return;
    }

    if (currentUser.uid == blockedUid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No puedes bloquear tu propio perfil.')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Bloquear usuario'),
        content: const Text(
          'Una vez bloqueado, dejarás de ver la actividad de este usuario.\n\n'
          '¿Deseas continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Bloquear'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .set({
        'blockedUsers': FieldValue.arrayUnion([blockedUid]),
      }, SetOptions(merge: true));

      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Usuario bloqueado.')));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error al bloquear: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final alias = (widget.data['alias'] ?? '') as String? ?? '';
    final age = widget.data['age'];
    final city = (widget.data['city'] ?? '') as String? ?? '';
    final state = (widget.data['state'] ?? '') as String? ?? '';
    final country = (widget.data['country'] ?? '') as String? ?? '';
    final countryFlag = (widget.data['countryFlag'] ?? '') as String? ?? '';
    final genderRaw = widget.data['gender'];
    final gender = _formatGender(genderRaw);

    final bio = (widget.data['bio'] ?? '') as String? ?? '';
    final companionCode = (widget.data['companionCode'] ?? '') as String? ?? '';

    final chatCents = widget.data['rateChat15Cents'] as int?;
    final voiceCents = widget.data['rateVoice15Cents'] as int?;
    final videoCents = widget.data['rateVideo15Cents'] as int?;

    // ✅ solo mostrar si NO es mínima
    final bool showChatRate = chatCents != null && chatCents != kMinChat15Cents;
    final bool showVoiceRate =
        voiceCents != null && voiceCents != kMinVoice15Cents;
    final bool showVideoRate =
        videoCents != null && videoCents != kMinVideo15Cents;

    final chat15 = _formatRate(chatCents, kMinChat15Cents);
    final voice15 = _formatRate(voiceCents, kMinVoice15Cents);
    final video15 = _formatRate(videoCents, kMinVideo15Cents);

    final bool showRatesSection =
        _isCompanion && (showChatRate || showVoiceRate || showVideoRate);

    final bool isOnline = widget.data['isOnline'] == true;

    final String? photoUrl =
        (widget.data['photoUrl'] as String?)?.isNotEmpty == true
            ? widget.data['photoUrl'] as String
            : null;

    List<String> galleryPhotos = _galleryPhotosFromSubcollection ??
        (widget.data['galleryPhotos'] as List<dynamic>?)?.cast<String>() ??
        (widget.data['gallery'] as List<dynamic>?)?.cast<String>() ??
        [];

    if (galleryPhotos.isEmpty && photoUrl != null) {
      galleryPhotos = [photoUrl];
    }

    final List<String> galleryVideos = _galleryVideosFromSubcollection ??
        (widget.data['galleryVideos'] as List<dynamic>?)?.cast<String>() ??
        [];

    final (availabilityDays, availabilityHours) = _availabilityParts();

    final bool hasPhotos = galleryPhotos.isNotEmpty;
    final bool hasVideos = galleryVideos.isNotEmpty;

    if (!hasVideos && !_showingPhotos) _showingPhotos = true;

    final List<String> currentItems =
        _showingPhotos ? galleryPhotos : galleryVideos;
    final PageController currentController =
        _showingPhotos ? _photosPageController : _videosPageController;

    // ✅ Ancho reducido (en pantallas grandes), como en tu imagen.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          decoration: BoxDecoration(
            gradient: kProfileCardGradient,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Colors.white.withOpacity(0.16),
              width: 1.6,
            ),
            boxShadow: [
              // shadow-cyan-500/20 (suave)
              BoxShadow(
                color: const Color(0xFF06B6D4).withOpacity(0.20),
                blurRadius: 24,
                spreadRadius: 1,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.showCloseButton && widget.onClose != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        icon: const Icon(Icons.close),
                        color: Colors.white.withOpacity(0.9),
                        onPressed: widget.onClose,
                      ),
                    ),

                  if (_galleryError != null) ...[
                    Text(
                      'No se pudo cargar galería: $_galleryError',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],

                  // ====== Selector simple FOTOS / VIDEOS (como tu imagen) ======
                  if (hasPhotos || hasVideos) ...[
                    Row(
                      children: [
                        _TopTab(
                          text: 'FOTOS',
                          selected: _showingPhotos,
                          enabled: hasPhotos,
                          onTap: () {
                            if (!_showingPhotos) {
                              setState(() => _showingPhotos = true);
                            }
                          },
                        ),
                        const SizedBox(width: 18),
                        _TopTab(
                          text: 'VIDEOS',
                          selected: !_showingPhotos,
                          enabled: hasVideos,
                          onTap: () {
                            if (_showingPhotos && hasVideos) {
                              setState(() => _showingPhotos = false);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // ====== GALERÍA (foto siempre a ANCHO COMPLETO, recorta altura) ======
                    SizedBox(
                      height: 240,
                      child: currentItems.isEmpty
                          ? Center(
                              child: Text(
                                _showingPhotos ? 'Sin fotos' : 'Sin videos',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white.withOpacity(0.9),
                                ),
                              ),
                            )
                          : Stack(
                              children: [
                                PageView.builder(
                                  controller: currentController,
                                  itemCount: currentItems.length,
                                  itemBuilder: (context, index) {
                                    final url = currentItems[index];
                                    final isVideo = !_showingPhotos;

                                    return GestureDetector(
                                      onTap: () {
                                        _openFullScreenMedia(
                                          items: currentItems,
                                          initialIndex: index,
                                          isVideo: isVideo,
                                        );
                                      },
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: _showingPhotos
                                            ? Image.network(
                                                url,
                                                // ✅ CLAVE: cubre el ancho, recorta alto
                                                fit: BoxFit.cover,
                                                width: double.infinity,
                                                height: double.infinity,
                                                alignment: Alignment.center,
                                                errorBuilder:
                                                    (context, error, stackTrace) =>
                                                        Container(
                                                  color: Colors.white.withOpacity(0.06),
                                                  alignment: Alignment.center,
                                                  child: Icon(
                                                    Icons.broken_image,
                                                    color: Colors.white.withOpacity(0.75),
                                                  ),
                                                ),
                                              )
                                            : Container(
                                                color: Colors.white.withOpacity(0.06),
                                                alignment: Alignment.center,
                                                child: Icon(
                                                  Icons.play_circle_outline,
                                                  size: 64,
                                                  color: Colors.white.withOpacity(0.85),
                                                ),
                                              ),
                                      ),
                                    );
                                  },
                                ),
                                if (currentItems.isNotEmpty)
                                  Positioned(
                                    left: 4,
                                    top: 0,
                                    bottom: 0,
                                    child: IconButton(
                                      icon: const Icon(Icons.chevron_left, size: 28),
                                      color: Colors.white.withOpacity(0.9),
                                      onPressed: () {
                                        final page =
                                            currentController.page?.round() ?? 0;
                                        final prevPage = page == 0
                                            ? currentItems.length - 1
                                            : page - 1;
                                        currentController.animateToPage(
                                          prevPage,
                                          duration: const Duration(milliseconds: 250),
                                          curve: Curves.easeInOut,
                                        );
                                      },
                                    ),
                                  ),
                                if (currentItems.isNotEmpty)
                                  Positioned(
                                    right: 4,
                                    top: 0,
                                    bottom: 0,
                                    child: IconButton(
                                      icon: const Icon(Icons.chevron_right, size: 28),
                                      color: Colors.white.withOpacity(0.9),
                                      onPressed: () {
                                        final page =
                                            currentController.page?.round() ?? 0;
                                        final nextPage = page == currentItems.length - 1
                                            ? 0
                                            : page + 1;
                                        currentController.animateToPage(
                                          nextPage,
                                          duration: const Duration(milliseconds: 250),
                                          curve: Curves.easeInOut,
                                        );
                                      },
                                    ),
                                  ),
                                Positioned(
                                  bottom: 8,
                                  left: 10,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.55),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Text(
                                      'Toca para ver en grande · desliza para más',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.95),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 12),
                  ] else ...[
                    const SizedBox(height: 6),
                  ],

                  // ====== Nombre + estado ======
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          alias.isNotEmpty ? alias : 'Usuario',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isOnline ? Colors.green : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  Text(
                    '${age ?? '--'} años · $gender',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withOpacity(0.90),
                    ),
                  ),

                  if (city.isNotEmpty || state.isNotEmpty || country.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      _formatLocationLine(
                        city: city,
                        state: state,
                        country: country,
                        flag: countryFlag,
                      ),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withOpacity(0.90),
                      ),
                    ),
                  ],

                  const SizedBox(height: 10),

                  if (bio.isNotEmpty) ...[
                    Text(
                      'Biografía',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white.withOpacity(0.95),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      bio,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontStyle: FontStyle.italic,
                        height: 1.35,
                        color: Colors.white.withOpacity(0.92),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  if (_isCompanion) ...[
                    Text(
                      'Disponibilidad:',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white.withOpacity(0.95),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      availabilityDays,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withOpacity(0.92),
                      ),
                    ),
                    if (availabilityHours.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        availabilityHours,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.92),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                  ],

                  // ✅ Tarifas: solo si NO son mínimas
                  if (showRatesSection) ...[
                    Text(
                      'Tarifas (15 min)',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white.withOpacity(0.95),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (showChatRate) 'Chat: $chat15',
                        if (showVoiceRate) 'Voz: $voice15',
                        if (showVideoRate) 'Video: $video15',
                      ].join(' · '),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withOpacity(0.92),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // ✅ Código resaltado (sin tarjetas internas, pero sí caja fuerte)
                  if (_isCompanion && companionCode.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.20),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.18),
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: SelectableText(
                              companionCode,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy),
                            color: Colors.white.withOpacity(0.9),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: companionCode));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Código copiado al portapapeles'),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  if (widget.onMakeOffer != null) ...[
                    const SizedBox(height: 4),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: widget.onMakeOffer,
                        icon: const Icon(Icons.local_offer_outlined),
                        label: const Text('Hacer oferta'),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: 'Reportar',
                        icon: const Icon(Icons.flag_outlined, size: 20),
                        color: Colors.white.withOpacity(0.85),
                        onPressed: _handleReport,
                      ),
                      IconButton(
                        tooltip: 'Bloquear',
                        icon: const Icon(Icons.lock_outline, size: 20),
                        color: Colors.white.withOpacity(0.85),
                        onPressed: _handleBlock,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatLocationLine({
    required String city,
    required String state,
    required String country,
    required String flag,
  }) {
    final parts = <String>[];
    if (city.trim().isNotEmpty) parts.add(city.trim());
    if (state.trim().isNotEmpty) parts.add(state.trim());

    final left = parts.join(', ');
    final rightCountry = country.trim();
    final rightFlag = flag.trim();

    final right = [
      if (rightCountry.isNotEmpty) rightCountry,
      if (rightFlag.isNotEmpty) rightFlag,
    ].join(' ');

    if (left.isEmpty) return right;
    if (right.isEmpty) return left;
    return '$left · $right';
  }
}

class _TopTab extends StatelessWidget {
  final String text;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _TopTab({
    required this.text,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color textColor = enabled
        ? Colors.white.withOpacity(selected ? 1.0 : 0.85)
        : Colors.white.withOpacity(0.35);

    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: TextStyle(
                color: textColor,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w800,
                letterSpacing: 0.6,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 6),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 2.5,
              width: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: selected
                    ? const Color(0xFF06B6D4) // cyan-ish underline
                    : Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Visor fullscreen para fotos/videos.
class _FullScreenMediaViewer extends StatefulWidget {
  final List<String> items;
  final int initialIndex;
  final bool isVideo;

  const _FullScreenMediaViewer({
    required this.items,
    required this.initialIndex,
    required this.isVideo,
  });

  @override
  State<_FullScreenMediaViewer> createState() => _FullScreenMediaViewerState();
}

class _FullScreenMediaViewerState extends State<_FullScreenMediaViewer> {
  late PageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.isVideo;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.items.length,
        itemBuilder: (context, index) {
          final url = widget.items[index];

          if (!isVideo) {
            return InteractiveViewer(
              child: Center(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: Colors.black12,
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.broken_image,
                      color: Colors.white70,
                      size: 48,
                    ),
                  ),
                ),
              ),
            );
          } else {
            return _FullScreenVideoPage(url: url);
          }
        },
      ),
    );
  }
}

/// Página individual de video en fullscreen
class _FullScreenVideoPage extends StatefulWidget {
  final String url;

  const _FullScreenVideoPage({required this.url});

  @override
  State<_FullScreenVideoPage> createState() => _FullScreenVideoPageState();
}

class _FullScreenVideoPageState extends State<_FullScreenVideoPage> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _isPlaying = false;
  bool _hasError = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    try {
      _controller = VideoPlayerController.network(widget.url)
        ..setLooping(true)
        ..initialize().then((_) {
          if (!mounted) return;
          setState(() => _initialized = true);
          _controller!.play();
          setState(() => _isPlaying = true);
        }).catchError((error) {
          if (!mounted) return;
          setState(() {
            _hasError = true;
            _errorMessage = error.toString();
          });
        });
    } catch (e) {
      _hasError = true;
      _errorMessage = e.toString();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (!_initialized || _controller == null) return;
    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
        _isPlaying = false;
      } else {
        _controller!.play();
        _isPlaying = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.redAccent,
                size: 60,
              ),
              const SizedBox(height: 12),
              const Text(
                'No se pudo reproducir el video.',
                style: TextStyle(color: Colors.white70, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (!_initialized || _controller == null) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      );
    }

    final aspect =
        _controller!.value.aspectRatio == 0 ? 16 / 9 : _controller!.value.aspectRatio;

    return GestureDetector(
      onTap: _togglePlayPause,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: aspect,
              child: VideoPlayer(_controller!),
            ),
          ),
          AnimatedOpacity(
            opacity: _isPlaying ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.black45,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(12),
              child: const Icon(
                Icons.play_arrow,
                color: Colors.white,
                size: 60,
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Column(
              children: [
                VideoProgressIndicator(
                  _controller!,
                  allowScrubbing: true,
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(_controller!.value.position),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      _formatDuration(_controller!.value.duration),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final minutes = two(d.inMinutes.remainder(60));
    final seconds = two(d.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}
