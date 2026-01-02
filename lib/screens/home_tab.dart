import 'dart:async';
  import 'package:flutter/material.dart';
  import 'package:flutter/services.dart';
  import 'package:firebase_auth/firebase_auth.dart';
  import 'package:cloud_firestore/cloud_firestore.dart';

  import '../features/sessions/ui/session_screen.dart';
  import '../features/explorer/ui/public_profile_screen.dart';

  enum PeopleSortMode { newest, oldest }
  enum HistorySortMode { newest, oldest }

  class HomeTab extends StatefulWidget {
  final VoidCallback onGoToOffersTab;
  const HomeTab({super.key, required this.onGoToOffersTab});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  Timer? _tipTimer;
  int _tipIndex = 0;

  static const int _tipIntervalSeconds = 6; // ✅ misma duración para todos

  static const List<String> _tips = [
    'Explora perfiles y ten conversaciones profundas 💬',
    'Ingresa un método de pago para realizar ofertas 💳',
    'Las ofertas tienen un periodo de vida de 30 minutos ⏳',
    'Solo pagas por conversación; sin conversación no pagas nada 😉',
    'Un buen título ayuda a que te elijan rápido ⚡️',
    'Revisa el historial para retomar conversaciones 🗂️',
    'Califica al final: mejora la comunidad ⭐️',
    'Cuida tu privacidad: comparte solo lo necesario 🔒',
    'Si algo no te cuadra, puedes terminar la sesión con seguridad 🛡️',
    'Mantén tu perfil claro: mejores matches ✨',
  ];

  @override
  void initState() {
    super.initState();
    _tipTimer = Timer.periodic(const Duration(seconds: _tipIntervalSeconds), (_) {
      if (!mounted) return;
      setState(() => _tipIndex = (_tipIndex + 1) % _tips.length);
    });
  }

  @override
  void dispose() {
    _tipTimer?.cancel();
    super.dispose();
  }

  void _goToHistory(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HistoryScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Center(
        child: Text(
          'Debes iniciar sesión para ver tu inicio.',
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
      );
    }

    final uid = user.uid;

    return SafeArea(
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
        builder: (context, snap) {
          final userData = snap.data?.data() ?? const <String, dynamic>{};

          final alias = (userData['alias'] ?? userData['displayName'] ?? '').toString().trim();

          final roleRaw = (userData['role'] ?? userData['userRole'] ?? '').toString().toLowerCase().trim();

          final isSpeakerRole =
              roleRaw.contains('speaker') || roleRaw.contains('hablante') || roleRaw == 's';

          // 🔷 Identidad visual (mismo estilo que Offers)
          final cyanGlow = const Color(0xFF22D3EE);
          final cs = theme.colorScheme;

          // ✅ Bienvenida con signos de exclamación
          final welcomeLine = alias.isNotEmpty ? '¡Bienvenido, $alias!' : '¡Bienvenido a Lissen!';

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),

              // ===== Header tipo preview (idéntico estilo) =====
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _GlowTitle(text: 'Lissen', glowColor: cyanGlow),
                    const SizedBox(height: 14),
                    _SectionHeader(
                      icon: Icons.home_rounded,
                      iconBg: cyanGlow.withOpacity(0.12),
                      iconColor: cyanGlow,
                      title: 'Inicio',
                    ),
                    const SizedBox(height: 8),

                    // Bienvenida (fija)
                    Text(
                      welcomeLine,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                        color: cs.onBackground.withOpacity(0.88),
                        height: 1.2,
                        shadows: [
                          Shadow(
                            color: Colors.black.withOpacity(0.35),
                            blurRadius: 14,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ✅ Zona media: tip flotante (sin empujar tarjetas)
              Expanded(
                child: Align(
                  alignment: const Alignment(0, -0.05),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // ✅ Tarjetas fijas (NO se mueven cuando cambia el mensaje)
                          Align(
                            alignment: Alignment.center,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _RoleInviteBanner(
                                  isSpeaker: isSpeakerRole,
                                  onGoToOffers: widget.onGoToOffersTab,
                                ),
                                const SizedBox(height: 50),
                                _HistoryNavBanner(
                                  onTap: () => _goToHistory(context),
                                ),
                              ],
                            ),
                          ),

                          // ✅ Mensaje flotante MÁS ARRIBA (no interfiere con tarjetas)
                          Align(
                            alignment: const Alignment(0, -0.92),
                            child: _RotatingTipBlock(
                              tip: _tips[_tipIndex],
                              tipIndex: _tipIndex,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// ==============================
/// Bloque rotativo (shimmer + transición suave)
/// ==============================
class _RotatingTipBlock extends StatelessWidget {
  final String tip;
  final int tipIndex;

  const _RotatingTipBlock({
    required this.tip,
    required this.tipIndex,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final baseSize = theme.textTheme.bodyMedium?.fontSize ?? 14;

    return SizedBox(
      width: double.infinity,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 520),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, anim) {
          final fade = CurvedAnimation(parent: anim, curve: Curves.easeOut);
          final slide = Tween<Offset>(
            begin: const Offset(0, 0.18),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));
          final scale = Tween<double>(begin: 0.98, end: 1.0).animate(
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          );
          return FadeTransition(
            opacity: fade,
            child: SlideTransition(
              position: slide,
              child: ScaleTransition(scale: scale, child: child),
            ),
          );
        },
        child: _ShimmerText(
          key: ValueKey(tipIndex),
          text: tip,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            // ✅ antes era doble; ahora 70% del tamaño actual
            fontSize: baseSize * 2 * 0.70,
            fontWeight: FontWeight.w700,
            height: 1.15,
            shadows: [
              Shadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 16,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          // shimmer visible, base gris
          baseColor: const Color(0xFF9CA3AF),
          highlightColor: const Color(0xFFE5E7EB),
        ),
      ),
    );  }
}

/// ==============================
/// Shimmer SOLO visual (texto)
/// ==============================
class _ShimmerText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Color baseColor;
  final Color highlightColor;

  final TextAlign textAlign;
  final int? maxLines;
  final TextOverflow overflow;

  const _ShimmerText({
    super.key,
    required this.text,
    required this.style,
    required this.baseColor,
    required this.highlightColor,
    this.textAlign = TextAlign.left,
    this.maxLines,
    this.overflow = TextOverflow.clip,
  });

  @override
  State<_ShimmerText> createState() => _ShimmerTextState();
}

class _ShimmerTextState extends State<_ShimmerText> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) {
            final t = _c.value; // 0..1
            final dx = rect.width * (2 * t - 1); // -w..+w

            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                widget.baseColor,
                widget.baseColor,
                widget.highlightColor,
                widget.baseColor,
                widget.baseColor,
              ],
              stops: const [0.0, 0.35, 0.50, 0.65, 1.0],
            ).createShader(
              Rect.fromLTWH(-rect.width + dx, 0, rect.width * 2, rect.height),
            );
          },
          child: Text(
            widget.text,
            textAlign: widget.textAlign,
            maxLines: widget.maxLines,
            overflow: widget.overflow,
            style: widget.style?.copyWith(color: widget.baseColor),
          ),
        );
      },
    );
  }
}

/// ==============================
/// Shimmer sutil (tarjetas / bloques)
/// ==============================
class _ShimmerSweep extends StatefulWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final double intensity; // 0.0..1.0 (sugerido 0.06 - 0.10)

  const _ShimmerSweep({
    super.key,
    required this.child,
    required this.borderRadius,
    this.intensity = 0.08,
  });

  @override
  State<_ShimmerSweep> createState() => _ShimmerSweepState();
}

class _ShimmerSweepState extends State<_ShimmerSweep> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final intensity = widget.intensity.clamp(0.0, 0.25);

    return Stack(
      children: [
        widget.child,

        // ✅ Overlay interno, recortado (no corta sombras exteriores del child)
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: widget.borderRadius,
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  return ShaderMask(
                    blendMode: BlendMode.srcATop,
                    shaderCallback: (rect) {
                      final t = _c.value; // 0..1
                      final dx = rect.width * (2 * t - 1);

                      return LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Colors.transparent,
                          Colors.white.withOpacity(intensity * 0.35),
                          Colors.white.withOpacity(intensity),
                          Colors.white.withOpacity(intensity * 0.35),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.40, 0.50, 0.60, 1.0],
                      ).createShader(
                        Rect.fromLTWH(-rect.width + dx, 0, rect.width * 2, rect.height),
                      );
                    },
                    child: Container(color: Colors.white.withOpacity(intensity)),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}


/// ==============================
  /// Pantalla nueva: Historial
  /// ==============================
  class HistoryScreen extends StatefulWidget {
    const HistoryScreen({super.key});

    @override
    State<HistoryScreen> createState() => _HistoryScreenState();
  }

  class _HistoryScreenState extends State<HistoryScreen> {
    // Para evitar “flash” / pantalla en blanco: loader solo la 1ra vez
    bool _loadedOnce = false;

    // Buscadores separados
    final TextEditingController _peopleSearchC = TextEditingController();
    final TextEditingController _historySearchC = TextEditingController();

    // Ordenadores
    PeopleSortMode _peopleSort = PeopleSortMode.newest;
    HistorySortMode _historySort = HistorySortMode.newest;

    // Cache simple para evitar N lecturas repetidas de users/{uid}
    final Map<String, Future<Map<String, dynamic>>> _userCache = {};

    @override
    void dispose() {
      _peopleSearchC.dispose();
      _historySearchC.dispose();
      super.dispose();
    }

    Future<Map<String, dynamic>> _getUserData(String uid) {
      return _userCache.putIfAbsent(uid, () async {
        final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        return snap.data() ?? <String, dynamic>{};
      });
    }

    Future<bool> _confirmDialog({
      required String title,
      required String message,
      required String confirmText,
    }) async {
      final res = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(confirmText),
            ),
          ],
        ),
      );
      return res == true;
    }

    Future<void> _hideSessionForMe({
      required String sessionId,
      required String myUid,
    }) async {
      await FirebaseFirestore.instance.collection('sessions').doc(sessionId).set({
        'hiddenFor': {myUid: true},
        'hiddenAtBy': {myUid: FieldValue.serverTimestamp()},
      }, SetOptions(merge: true));
    }

    Future<void> _hidePersonForMe({
      required String myUid,
      required String otherUid,
    }) async {
      await FirebaseFirestore.instance.collection('users').doc(myUid).set({
        'hiddenPeople': FieldValue.arrayUnion([otherUid]),
        'hiddenPeopleUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    Future<void> _copyToClipboard(String text, {String toast = 'Copiado.'}) async {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(toast)));
    }

    String _fmtDate(Timestamp? ts) {
      if (ts == null) return '';
      final d = ts.toDate();
      String two(int n) => n.toString().padLeft(2, '0');
      final dd = two(d.day);
      final mm = two(d.month);
      final yyyy = d.year.toString();

      int hour = d.hour;
      final min = two(d.minute);
      final ampm = hour >= 12 ? 'pm' : 'am';
      hour = hour % 12;
      if (hour == 0) hour = 12;

      return '$dd/$mm/$yyyy · $hour:$min $ampm';
    }

    bool _isMySession(Map<String, dynamic> d, String uid) {
      final speakerId = (d['speakerId'] as String?) ?? '';
      final companionId = (d['companionId'] as String?) ?? '';
      final participants = (d['participants'] as List<dynamic>?)?.cast<String>() ?? const [];
      return speakerId == uid || companionId == uid || participants.contains(uid);
    }

    bool _isHiddenForMe(Map<String, dynamic> d, String uid) {
      final hf = d['hiddenFor'];
      if (hf is Map) return hf[uid] == true;
      return false;
    }

    String _safeStr(dynamic v, {String fallback = ''}) {
      final s = (v ?? '').toString();
      return s.isEmpty ? fallback : s;
    }

    String _norm(String s) => s.trim().toLowerCase();

    bool _matchesPeopleQuery({
      required String query,
      required String alias,
      required String companionCode,
      required String uid,
    }) {
      if (query.isEmpty) return true;
      final q = _norm(query);
      return _norm(alias).contains(q) || _norm(companionCode).contains(q) || _norm(uid).contains(q);
    }

    bool _matchesHistoryQuery({
      required String query,
      required String otherAlias,
      required String companionCode,
      required String statusLabel,
      required String sessionId,
    }) {
      if (query.isEmpty) return true;
      final q = _norm(query);
      return _norm(otherAlias).contains(q) ||
          _norm(companionCode).contains(q) ||
          _norm(statusLabel).contains(q) ||
          _norm(sessionId).contains(q);
    }

    @override
    Widget build(BuildContext context) {
      final theme = Theme.of(context);

      final bottomPad = MediaQuery.of(context).padding.bottom;
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        return Scaffold(
          body: Center(
            child: Text(
              'Debes iniciar sesión para ver tu historial.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        );
      }

      final uid = user.uid;

      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Historial'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('sessions').snapshots(),
          builder: (context, sessionsSnap) {
            if (sessionsSnap.hasError) {
              return Center(
                child: Text(
                  'Error leyendo sesiones: ${sessionsSnap.error}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white),
                ),
              );
            }

            if (sessionsSnap.connectionState == ConnectionState.waiting && !_loadedOnce) {
              return const Center(child: CircularProgressIndicator());
            }
            if (sessionsSnap.connectionState != ConnectionState.waiting) {
              _loadedOnce = true;
            }

            final rawDocs = sessionsSnap.data?.docs ?? const [];
            final myVisibleDocs = rawDocs
                .where((doc) => _isMySession(doc.data(), uid))
                .where((doc) => !_isHiddenForMe(doc.data(), uid))
                .toList();

            final historySessions = myVisibleDocs.where((doc) {
              final status = _safeStr(doc.data()['status']);
              return status == 'completed' || status == 'cancelled';
            }).toList();

            // ===== Personas: agregamos por otherUid (de TODAS mis sesiones visibles) =====
            final Map<String, _PersonAgg> peopleMap = {};
            for (final doc in myVisibleDocs) {
              final d = doc.data();
              final speakerId = _safeStr(d['speakerId']);
              final companionId = _safeStr(d['companionId']);
              final isSpeaker = speakerId == uid;

              final otherUid = isSpeaker ? companionId : speakerId;
              if (otherUid.isEmpty) continue;

              final speakerAlias = _safeStr(d['speakerAlias'], fallback: 'Hablante');
              final companionAlias = _safeStr(d['companionAlias'], fallback: 'Compañera');
              final otherAlias = isSpeaker ? companionAlias : speakerAlias;

              Timestamp? lastAt;
              final completedAt = d['completedAt'];
              final createdAt = d['createdAt'];
              final updatedAt = d['updatedAt'];

              if (updatedAt is Timestamp) lastAt = updatedAt;
              if (lastAt == null && completedAt is Timestamp) lastAt = completedAt;
              if (lastAt == null && createdAt is Timestamp) lastAt = createdAt;

              final current = peopleMap[otherUid];
              if (current == null) {
                peopleMap[otherUid] = _PersonAgg(
                  otherUid: otherUid,
                  alias: otherAlias,
                  lastAt: lastAt,
                  count: 1,
                );
              } else {
                current.count += 1;
                if (lastAt != null) {
                  final cur = current.lastAt;
                  if (cur == null || lastAt.compareTo(cur) > 0) current.lastAt = lastAt;
                }
                if (current.alias.trim().isEmpty) current.alias = otherAlias;
              }
            }

            // Leemos hiddenPeople del usuario (para filtrar lista Personas)
            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
              builder: (context, userSnap) {
                final userData = userSnap.data?.data() ?? const <String, dynamic>{};
                final hiddenPeople = (userData['hiddenPeople'] as List<dynamic>?)
                        ?.map((e) => e.toString())
                        .toSet() ??
                    <String>{};

                // PEOPLE
                final people = peopleMap.values.where((p) => !hiddenPeople.contains(p.otherUid)).toList();

                people.sort((a, b) {
                  final at = a.lastAt;
                  final bt = b.lastAt;
                  if (at == null && bt == null) return 0;
                  if (at == null) return 1;
                  if (bt == null) return -1;

                  return _peopleSort == PeopleSortMode.newest ? bt.compareTo(at) : at.compareTo(bt);
                });

                // HISTORY
                historySessions.sort((a, b) {
                  final ad = a.data()['completedAt'];
                  final bd = b.data()['completedAt'];
                  if (ad is! Timestamp || bd is! Timestamp) return 0;
                  return _historySort == HistorySortMode.newest ? bd.compareTo(ad) : ad.compareTo(bd);
                });

                return DefaultTabController(
                  length: 2,
                  child: Column(
                    children: [
                      // Tabs
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withOpacity(0.10)),
                        ),
                        child: TabBar(
                          indicatorSize: TabBarIndicatorSize.tab,
                          dividerColor: Colors.transparent,
                          labelColor: Colors.white,
                          unselectedLabelColor: Colors.white70,
                          indicator: BoxDecoration(
                            color: Colors.white.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withOpacity(0.12)),
                          ),
                          tabs: [
                            Tab(text: 'Perfiles (${people.length})'),
                            Tab(text: 'Conversaciones (${historySessions.length})'),
                          ],
                        ),
                      ),

                      Expanded(
                        child: TabBarView(
                          children: [
                            // =========================
                            // TAB: Personas
                            // =========================
                            ListView(
                              padding: EdgeInsets.fromLTRB(16, 6, 16, 16 + bottomPad),
                              children: [
                                _SearchAndSortBar(
                                  hintText: 'Buscar personas…',
                                  controller: _peopleSearchC,
                                  onChanged: (_) => setState(() {}),
                                  sortWidget: DropdownButton<PeopleSortMode>(
                                    value: _peopleSort,
                                    onChanged: (v) {
                                      if (v == null) return;
                                      setState(() => _peopleSort = v);
                                    },
                                    items: const [
                                      DropdownMenuItem(
                                        value: PeopleSortMode.newest,
                                        child: Text('Más reciente'),
                                      ),
                                      DropdownMenuItem(
                                        value: PeopleSortMode.oldest,
                                        child: Text('Más antiguo'),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),

                                if (people.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Text(
                                      'Aún no has interactuado con nadie.',
                                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                                    ),
                                  )
                                else
                                  for (final p in people)
                                    _PersonTile(
                                      person: p,
                                      myUid: uid,
                                      peopleQuery: _peopleSearchC.text,
                                      matchesPeopleQuery: _matchesPeopleQuery,
                                      fmtDate: _fmtDate,
                                      getUserData: _getUserData,
                                      confirmDialog: _confirmDialog,
                                      onHidePerson: _hidePersonForMe,
                                      onCopy: _copyToClipboard,
                                      onOpenProfile: (otherUid) {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => PublicProfileScreen(
                                              companionUid: otherUid,
                                              enableMakeOfferButton: false,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                              ],
                            ),

                            // =========================
                            // TAB: Historial
                            // =========================
                            ListView(
                              padding: EdgeInsets.fromLTRB(16, 6, 16, 16 + bottomPad),
                              children: [
                                _SearchAndSortBar(
                                  hintText: 'Buscar en historial…',
                                  controller: _historySearchC,
                                  onChanged: (_) => setState(() {}),
                                  sortWidget: DropdownButton<HistorySortMode>(
                                    value: _historySort,
                                    onChanged: (v) {
                                      if (v == null) return;
                                      setState(() => _historySort = v);
                                    },
                                    items: const [
                                      DropdownMenuItem(
                                        value: HistorySortMode.newest,
                                        child: Text('Más reciente'),
                                      ),
                                      DropdownMenuItem(
                                        value: HistorySortMode.oldest,
                                        child: Text('Más antiguo'),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),

                                if (historySessions.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Text(
                                      'No hay sesiones finalizadas todavía.',
                                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                                    ),
                                  )
                                else
                                  for (final doc in historySessions)
                                    _HistorySessionCard(
                                      doc: doc,
                                      myUid: uid,
                                      historyQuery: _historySearchC.text,
                                      matchesHistoryQuery: _matchesHistoryQuery,
                                      fmtDate: _fmtDate,
                                      getUserData: _getUserData,
                                      confirmDialog: _confirmDialog,
                                      onHideSession: _hideSessionForMe,
                                      onCopy: _copyToClipboard,
                                      onOpen: (sessionId) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => SessionConversationScreen(sessionId: sessionId),
                                          ),
                                        );
                                      },
                                    ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      );
    }
  }

  /// ==============================
  /// Bloque azul (ofertas)
  /// ==============================
  class _RoleInviteBanner extends StatelessWidget {
    final bool isSpeaker;
    final VoidCallback onGoToOffers;

    const _RoleInviteBanner({
      required this.isSpeaker,
      required this.onGoToOffers,
    });

    @override
    Widget build(BuildContext context) {
      final theme = Theme.of(context);
      final cs = theme.colorScheme;

      final title = isSpeaker ? '¡Empieza una conversación!' : '¡Encuentra una conversación!';
      final body = isSpeaker
          ? 'Crea una oferta para que una compañera la tome y puedan conversar.'
          : 'Explora y toma una oferta para empezar a conversar con un hablante.';
      final cta = isSpeaker ? 'Crear oferta' : 'Ver ofertas';

      return _ShimmerSweep(borderRadius: BorderRadius.circular(14), intensity: 0.07, child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.white.withOpacity(0.06),
          border: Border.all(color: cs.primary.withOpacity(0.25), width: 1),
          boxShadow: [
            BoxShadow(
              color: cs.primary.withOpacity(0.18),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.chat_bubble_outline, size: 22, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    body,
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            TextButton(
              onPressed: onGoToOffers,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: cs.primary,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(cta),
            ),
          ],
        ),
      ));

    }
  }

  /// ==============================
  /// Bloque amarillo (ahora SOLO navega)
  /// ==============================
  class _HistoryNavBanner extends StatelessWidget {
    final VoidCallback onTap;

    const _HistoryNavBanner({required this.onTap});

    @override
    Widget build(BuildContext context) {
      final theme = Theme.of(context);
      final cs = theme.colorScheme;

      final bg = const Color(0xFFFFF4C2).withOpacity(0.10);
      final border = const Color(0xFFFFE08A).withOpacity(0.55);
      final glow = const Color(0xFFFFD54F).withOpacity(0.20);

      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: _ShimmerSweep(borderRadius: BorderRadius.circular(14), intensity: 0.07, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: bg,
            border: Border.all(color: border, width: 1),
            boxShadow: [
              BoxShadow(
                color: glow,
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(Icons.forum_outlined, size: 22, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Historial',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Ver perfiles públicos y conversaciones pasadas.',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              TextButton(
                onPressed: onTap,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF0F172A),
                  backgroundColor: const Color(0xFFFBBF24),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Abrir'),
              ),
            ],
          ),
        )),
      );
    }
  }

  /// ==============================
  /// Widgets reutilizados del historial
  /// ==============================
  class _SearchAndSortBar extends StatelessWidget {
    final String hintText;
    final TextEditingController controller;
    final ValueChanged<String> onChanged;
    final Widget sortWidget;

    const _SearchAndSortBar({
      required this.hintText,
      required this.controller,
      required this.onChanged,
      required this.sortWidget,
    });

    @override
    Widget build(BuildContext context) {
      final theme = Theme.of(context);
      final cs = theme.colorScheme;
      final outline = cs.primary.withOpacity(0.30);
      final fieldFill = cs.surface.withOpacity(0.70);
      final hintColor = cs.onSurface.withOpacity(0.60);
      final textColor = cs.onSurface;

      return Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: theme.textTheme.bodySmall?.copyWith(
                color: textColor,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: theme.textTheme.bodySmall?.copyWith(
                  color: hintColor,
                  fontWeight: FontWeight.w600,
                ),
                prefixIcon: Icon(
                  Icons.search,
                  size: 18,
                  color: hintColor,
                ),
                isDense: true,
                filled: true,
                fillColor: fieldFill,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: outline, width: 1.6),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: cs.primary, width: 2),
                ),
                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpiar',
                        icon: Icon(Icons.close, size: 18, color: hintColor),
                        onPressed: () {
                          controller.clear();
                          onChanged('');
                        },
                      ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: outline, width: 1.6),
              color: fieldFill,
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 10,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Theme(
              data: theme.copyWith(canvasColor: cs.surface),
              child: DropdownButtonHideUnderline(
                child: DefaultTextStyle(
                  style: theme.textTheme.bodySmall!.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w800,
                  ),
                  child: IconTheme(
                    data: IconThemeData(color: textColor),
                    child: sortWidget,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
  }

  class _PersonAgg {
    final String otherUid;
    String alias;
    Timestamp? lastAt;
    int count;

    _PersonAgg({
      required this.otherUid,
      required this.alias,
      required this.lastAt,
      required this.count,
    });
  }

  class _PersonTile extends StatelessWidget {
    final _PersonAgg person;
    final String myUid;

    final String peopleQuery;
    final bool Function({
      required String query,
      required String alias,
      required String companionCode,
      required String uid,
    }) matchesPeopleQuery;

    final String Function(Timestamp?) fmtDate;
    final Future<Map<String, dynamic>> Function(String uid) getUserData;
    final Future<bool> Function({
      required String title,
      required String message,
      required String confirmText,
    }) confirmDialog;
    final Future<void> Function({required String myUid, required String otherUid}) onHidePerson;
    final Future<void> Function(String text, {String toast}) onCopy;
    final void Function(String otherUid) onOpenProfile;

    const _PersonTile({
      required this.person,
      required this.myUid,
      required this.peopleQuery,
      required this.matchesPeopleQuery,
      required this.fmtDate,
      required this.getUserData,
      required this.confirmDialog,
      required this.onHidePerson,
      required this.onCopy,
      required this.onOpenProfile,
    });

    @override
    Widget build(BuildContext context) {
      final theme = Theme.of(context);
      final cs = theme.colorScheme;
      final borderColor = cs.primary.withOpacity(0.30);

      return FutureBuilder<Map<String, dynamic>>(
        future: getUserData(person.otherUid),
        builder: (context, snap) {
          final userData = snap.data ?? const <String, dynamic>{};
          final companionCode = (userData['companionCode'] as String?)?.trim() ?? '';
          final aliasFromUsers = (userData['alias'] as String?)?.trim() ?? '';
          final showAlias = aliasFromUsers.isNotEmpty ? aliasFromUsers : person.alias;

          final lastStr = fmtDate(person.lastAt);

          final ok = matchesPeopleQuery(
            query: peopleQuery,
            alias: showAlias,
            companionCode: companionCode,
            uid: person.otherUid,
          );
          if (!ok) return const SizedBox.shrink();

          return Dismissible(
            key: ValueKey('person_${person.otherUid}'),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: cs.error.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.delete_outline, color: cs.error),
            ),
            confirmDismiss: (_) async {
              return confirmDialog(
                title: '¿Quitar de esta lista?',
                message:
                    'Esta persona dejará de aparecer en “explorar”, pero tus sesiones seguirán visibles en el historial.',
                confirmText: 'Quitar',
              );
            },
            onDismissed: (_) async {
              await onHidePerson(myUid: myUid, otherUid: person.otherUid);
            },
            child: Card(
              color: cs.surface.withOpacity(0.60),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: borderColor, width: 1.6),
              ),
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: ListTile(
                onTap: () => onOpenProfile(person.otherUid),
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: cs.primary,
                  foregroundColor: Colors.white,
                  child: Text(
                    showAlias.isNotEmpty ? showAlias[0].toUpperCase() : '?',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                title: Text(
                  showAlias,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (companionCode.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Código: $companionCode',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 18),
                            color: cs.onSurface.withOpacity(0.70),
                            onPressed: () => onCopy(companionCode, toast: 'Código copiado.'),
                          ),
                        ],
                      ),
                    ],
                    if (lastStr.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Última interacción: $lastStr',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurface.withOpacity(0.70),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                trailing: Icon(Icons.chevron_right, color: cs.onSurface.withOpacity(0.70)),
              ),
            ),
          );
        },
      );
    }
  }

  class _HistorySessionCard extends StatelessWidget {
    final QueryDocumentSnapshot<Map<String, dynamic>> doc;
    final String myUid;

    final String historyQuery;
    final bool Function({
      required String query,
      required String otherAlias,
      required String companionCode,
      required String statusLabel,
      required String sessionId,
    }) matchesHistoryQuery;

    final String Function(Timestamp?) fmtDate;
    final Future<Map<String, dynamic>> Function(String uid) getUserData;
    final Future<bool> Function({
      required String title,
      required String message,
      required String confirmText,
    }) confirmDialog;
    final Future<void> Function({required String sessionId, required String myUid}) onHideSession;
    final Future<void> Function(String text, {String toast}) onCopy;
    final void Function(String sessionId) onOpen;

    const _HistorySessionCard({
      required this.doc,
      required this.myUid,
      required this.historyQuery,
      required this.matchesHistoryQuery,
      required this.fmtDate,
      required this.getUserData,
      required this.confirmDialog,
      required this.onHideSession,
      required this.onCopy,
      required this.onOpen,
    });

    @override
    Widget build(BuildContext context) {
      final theme = Theme.of(context);
      final cs = theme.colorScheme;

      final borderColor = cs.primary.withOpacity(0.30);
      final d = doc.data();

      final speakerAlias = (d['speakerAlias'] ?? 'Hablante').toString();
      final companionAlias = (d['companionAlias'] ?? 'Compañera').toString();

      final real = d['realDurationMinutes'] ?? 0;
      final billed = d['billingMinutes'] ?? 0;

      final status = (d['status'] ?? 'completed').toString();
      final endedBy = d['endedBy'] as String?;

      final priceCents = (d['priceCents'] ?? 0) as num;
      final currency = (d['currency'] ?? 'usd').toString();
      final price = priceCents / 100.0;

      final isSpeaker = d['speakerId'] == myUid;
      final otherAlias = isSpeaker ? companionAlias : speakerAlias;

      final otherUid = isSpeaker ? (d['companionId'] as String? ?? '') : (d['speakerId'] as String? ?? '');

      String statusLabel = 'Finalizada';
      Color statusColor = cs.tertiary;
      if (status == 'cancelled') {
        statusLabel = 'Cancelada';
        statusColor = cs.error;
      } else if (endedBy == 'speaker') {
        statusLabel = 'Finalizada por hablante';
      } else if (endedBy == 'companion') {
        statusLabel = 'Finalizada por compañera';
      } else if (endedBy == 'timeout') {
        statusLabel = 'Finalizada por tiempo';
      }

      final completedAt = d['completedAt'];
      final completedStr = completedAt is Timestamp ? fmtDate(completedAt) : '';

      return FutureBuilder<Map<String, dynamic>>(
        future: otherUid.isEmpty ? Future.value(const <String, dynamic>{}) : getUserData(otherUid),
        builder: (context, snap) {
          final userData = snap.data ?? const <String, dynamic>{};
          final companionCode = (userData['companionCode'] as String?)?.trim() ?? '';

          final ok = matchesHistoryQuery(
            query: historyQuery,
            otherAlias: otherAlias,
            companionCode: companionCode,
            statusLabel: statusLabel,
            sessionId: doc.id,
          );
          if (!ok) return const SizedBox.shrink();

          return Dismissible(
            key: ValueKey('session_${doc.id}'),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: cs.error.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.delete_outline, color: cs.error),
            ),
            confirmDismiss: (_) async {
              return confirmDialog(
                title: '¿Borrar conversación?',
                message: 'Esta conversación desaparecerá de tu historial.\n\n'
                    'Podrás seguir accediendo a ella más adelante si lo necesitas.',
                confirmText: 'Borrar',
              );
            },
            onDismissed: (_) async {
              await onHideSession(sessionId: doc.id, myUid: myUid);
            },
            child: Card(
              color: cs.surface.withOpacity(0.60),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: borderColor, width: 1.6),
              ),
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onOpen(doc.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: cs.primary,
                        foregroundColor: Colors.white,
                        child: Text(
                          otherAlias.isNotEmpty ? otherAlias[0].toUpperCase() : '?',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              otherAlias,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: cs.onSurface,
                              ),
                            ),
                            if (companionCode.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Código: $companionCode',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: const Color(0xFFB91C1C),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.copy, size: 18),
                                    color: cs.onSurface.withOpacity(0.70),
                                    onPressed: () => onCopy(companionCode, toast: 'Código copiado.'),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 6),
                            Text(
                              'Real: $real min • Cobro: $billed min',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: const Color(0xFF334155),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (completedStr.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                completedStr,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: cs.onSurface.withOpacity(0.70),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: statusColor.withOpacity(0.14),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    statusLabel,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: statusColor,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '\$${price.toStringAsFixed(2)} ${currency.toUpperCase()}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    }
  }

  // ============================================================================
  // SOLO VISUAL (helpers de UI). No tocan lógica.
  // Copiados del estilo de OffersPage para mantener identidad.
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
