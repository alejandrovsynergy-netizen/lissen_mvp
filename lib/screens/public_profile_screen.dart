import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Clipboard
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:video_player/video_player.dart';
import 'package:firebase_auth/firebase_auth.dart'; // <-- para saber quién ve el perfil

// ====== Tarifas mínimas estándar (centavos MXN) ======
const int kMinChat15Cents = 7000; // $70
const int kMinVoice15Cents = 10500; // $105
const int kMinVideo15Cents = 15500; // $155

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

            // Importante: aquí pasamos también el userId
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
    // Tomamos primero el userId pasado explícitamente,
    // y si no hay, intentamos con widget.data['uid'].
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

  String _onlineStatus() {
    final online = widget.data['onlineStatus'];
    switch (online) {
      case 'online':
        return 'En línea';
      case 'busy':
        return 'Ocupado';
      case 'offline':
        return 'Desconectado';
      default:
        return 'Estado desconocido';
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

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Reporte enviado.')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al reportar: $e')));
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

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Usuario bloqueado.')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al bloquear: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final alias = (widget.data['alias'] ?? '') as String? ?? '';
    final age = widget.data['age'];
    final city = (widget.data['city'] ?? '') as String? ?? '';
    final country = (widget.data['country'] ?? '') as String? ?? '';
    final genderRaw = widget.data['gender'];
    final gender = _formatGender(genderRaw);

    final ratingRaw = widget.data['rating'];
    final rating = ratingRaw is num ? ratingRaw.toDouble() : 0.0;

    final onlineInfo = _onlineStatus();
    final bio = (widget.data['bio'] ?? '') as String? ?? '';
    final companionCode = (widget.data['companionCode'] ?? '') as String? ?? '';

    final chatCents = widget.data['rateChat15Cents'] as int?;
    final voiceCents = widget.data['rateVoice15Cents'] as int?;
    final videoCents = widget.data['rateVideo15Cents'] as int?;

    final chat15 = _formatRate(chatCents, kMinChat15Cents);
    final voice15 = _formatRate(voiceCents, kMinVoice15Cents);
    final video15 = _formatRate(videoCents, kMinVideo15Cents);

    final String? photoUrl =
        (widget.data['photoUrl'] as String?)?.isNotEmpty == true
        ? widget.data['photoUrl'] as String
        : null;

    // 1) Preferimos los datos de la subcolección si ya se cargaron
    List<String> galleryPhotos =
        _galleryPhotosFromSubcollection ??
        (widget.data['galleryPhotos'] as List<dynamic>?)?.cast<String>() ??
        (widget.data['gallery'] as List<dynamic>?)?.cast<String>() ??
        [];

    if (galleryPhotos.isEmpty && photoUrl != null) {
      galleryPhotos = [photoUrl];
    }

    final List<String> galleryVideos =
        _galleryVideosFromSubcollection ??
        (widget.data['galleryVideos'] as List<dynamic>?)?.cast<String>() ??
        [];

    final (availabilityDays, availabilityHours) = _availabilityParts();

    // Color de la tarjeta según GÉNERO
    final String genderLower = (genderRaw ?? '').toString().toLowerCase();
    final Color baseColor;
    if (genderLower == 'female') {
      baseColor = Colors.pinkAccent;
    } else if (genderLower == 'male') {
      baseColor = Colors.blueAccent;
    } else {
      baseColor = Colors.deepPurpleAccent;
    }

    final bgColor = baseColor.withOpacity(0.12);
    final borderColor = baseColor.withOpacity(0.6);

    final bool hasPhotos = galleryPhotos.isNotEmpty;
    final bool hasVideos = galleryVideos.isNotEmpty;

    final List<String> currentItems = _showingPhotos
        ? galleryPhotos
        : galleryVideos;
    final PageController currentController = _showingPhotos
        ? _photosPageController
        : _videosPageController;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showCloseButton && widget.onClose != null)
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                icon: const Icon(Icons.close),
                onPressed: widget.onClose,
              ),
            ),

          // (Opcional) Mensaje muy pequeño si hubo error cargando galería
          if (_galleryError != null) ...[
            Text(
              'No se pudo cargar galería: $_galleryError',
              style: const TextStyle(fontSize: 11, color: Colors.redAccent),
            ),
            const SizedBox(height: 4),
          ],

          // ====== GALERÍA + selector FOTOS/VIDEOS ======
          if (hasPhotos || hasVideos) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () {
                    if (!_showingPhotos) {
                      setState(() {
                        _showingPhotos = true;
                      });
                    }
                  },
                  child: Text(
                    'FOTOS',
                    style: TextStyle(
                      fontWeight: _showingPhotos
                          ? FontWeight.bold
                          : FontWeight.normal,
                      decoration: _showingPhotos
                          ? TextDecoration.underline
                          : TextDecoration.none,
                      color: _showingPhotos
                          ? baseColor
                          : theme.textTheme.bodyMedium?.color,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: () {
                    if (_showingPhotos) {
                      setState(() {
                        _showingPhotos = false;
                      });
                    }
                  },
                  child: Text(
                    'VIDEOS',
                    style: TextStyle(
                      fontWeight: !_showingPhotos
                          ? FontWeight.bold
                          : FontWeight.normal,
                      decoration: !_showingPhotos
                          ? TextDecoration.underline
                          : TextDecoration.none,
                      color: !_showingPhotos
                          ? baseColor
                          : theme.textTheme.bodyMedium?.color,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            SizedBox(
              height: 260,
              child: currentItems.isEmpty
                  ? Center(
                      child: Text(
                        _showingPhotos ? 'Sin fotos' : 'Sin videos',
                        style: const TextStyle(fontSize: 14),
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
                                        // Imagen completa, sin recorte
                                        fit: BoxFit.contain,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                Container(
                                                  color: Colors.black12,
                                                  alignment: Alignment.center,
                                                  child: const Icon(
                                                    Icons.broken_image,
                                                  ),
                                                ),
                                      )
                                    : Container(
                                        color: Colors.black,
                                        alignment: Alignment.center,
                                        child: const Icon(
                                          Icons.play_circle_outline,
                                          size: 64,
                                          color: Colors.white70,
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
                              color: Colors.white70,
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
                              color: Colors.white70,
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
                          bottom: 6,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Toca para ver en grande · desliza para más',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),

            const SizedBox(height: 16),
          ] else ...[
            const SizedBox(height: 8),
          ],

          // ====== HEADER: alias + estado online ======
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  alias.isNotEmpty ? alias : 'Usuario',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.circle,
                    size: 10,
                    color: onlineInfo == 'En línea'
                        ? Colors.greenAccent
                        : onlineInfo == 'Ocupado'
                        ? Colors.orangeAccent
                        : Colors.grey,
                  ),
                  const SizedBox(width: 6),
                  Text(onlineInfo, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ],
          ),

          const SizedBox(height: 4),

          Text(
            '${age ?? '--'} años · $gender',
            style: theme.textTheme.bodyMedium,
          ),

          if (city.isNotEmpty || country.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              '$city${city.isNotEmpty && country.isNotEmpty ? ', ' : ''}$country',
              style: theme.textTheme.bodyMedium,
            ),
          ],

          const SizedBox(height: 8),

          Row(
            children: [
              const Text('Calificación', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 8),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: baseColor, width: 2),
                ),
                alignment: Alignment.center,
                child: Text(
                  rating.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          if (bio.isNotEmpty) ...[
            const Text(
              'Biografía',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              bio,
              style: const TextStyle(
                fontSize: 14,
                fontStyle: FontStyle.italic, // mismo estilo que en EditProfile
              ),
            ),
            const SizedBox(height: 16),
          ],

          if (_isCompanion) ...[
            const Text(
              'Disponibilidad:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(availabilityDays, style: const TextStyle(fontSize: 14)),
            if (availabilityHours.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(availabilityHours, style: const TextStyle(fontSize: 14)),
            ],
            const SizedBox(height: 16),
          ],

          if (_isCompanion) ...[
            const Text(
              'Tarifas (15 min)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text('Chat:  $chat15', style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 2),
            Text('Voz:   $voice15', style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 2),
            Text('Video: $video15', style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 16),
          ],

          if (_isCompanion && companionCode.isNotEmpty) ...[
            const Text(
              'Código de compañera',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    companionCode,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
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
            const SizedBox(height: 16),
          ],

          if (widget.onMakeOffer != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: widget.onMakeOffer,
                icon: const Icon(Icons.local_offer_outlined),
                label: const Text('Hacer oferta'),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ====== Reportar / Bloquear funcionales ======
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'Reportar',
                icon: const Icon(Icons.flag_outlined, size: 20),
                onPressed: _handleReport,
              ),
              IconButton(
                tooltip: 'Bloquear',
                icon: const Icon(Icons.lock_outline, size: 20),
                onPressed: _handleBlock,
              ),
            ],
          ),
        ],
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
            // AQUÍ YA SE IMPLEMENTA EL VIDEO
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
        ..initialize()
            .then((_) {
              if (!mounted) return;
              setState(() {
                _initialized = true;
              });
              _controller!.play();
              setState(() {
                _isPlaying = true;
              });
            })
            .catchError((error) {
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

    final aspect = _controller!.value.aspectRatio == 0
        ? 16 / 9
        : _controller!.value.aspectRatio;

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
          // Icono de play/pausa sobre el video
          AnimatedOpacity(
            opacity: _isPlaying ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              decoration: BoxDecoration(
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
          // Barra de posición simple abajo
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
