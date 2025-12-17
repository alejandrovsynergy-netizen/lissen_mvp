import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../features/sessions/ui/session_screen.dart';
import '../features/explorer/ui/public_profile_screen.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

enum PeopleSortMode { newest, oldest }
enum HistorySortMode { newest, oldest }

class _HomeTabState extends State<HomeTab> {
  bool _historyExpanded = false;
  bool _peopleExpanded = true;

  // Para evitar “flash” / pantalla en blanco: loader solo la 1ra vez
  bool _loadedOnce = false;

  // Buscadores separados
  final TextEditingController _peopleSearchC = TextEditingController();
  final TextEditingController _historySearchC = TextEditingController();

  // Ordenadores
  PeopleSortMode _peopleSort = PeopleSortMode.newest; // default: más reciente
  HistorySortMode _historySort = HistorySortMode.newest; // default: fecha desc

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
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
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
    final participants =
        (d['participants'] as List<dynamic>?)?.cast<String>() ?? const [];
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
    return _norm(alias).contains(q) ||
        _norm(companionCode).contains(q) ||
        _norm(uid).contains(q);
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

  void _goToOffers() {
    // Intento por ruta nombrada. Si tu app usa otra ruta, cámbiala aquí.
    try {
      Navigator.of(context).pushNamed('/offers');
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No encontré la ruta /offers. Ajusta _goToOffers().'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Center(
        child: Text('Debes iniciar sesión para ver tu inicio.'),
      );
    }

    final uid = user.uid;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('sessions').snapshots(),
      builder: (context, sessionsSnap) {
        if (sessionsSnap.hasError) {
          return Center(
            child: Text(
              'Error leyendo sesiones: ${sessionsSnap.error}',
              textAlign: TextAlign.center,
            ),
          );
        }

        // ✅ Loader SOLO la primera vez (evita parpadeo al ordenar/buscar)
        if (sessionsSnap.connectionState == ConnectionState.waiting &&
            !_loadedOnce) {
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
          final companionAlias =
              _safeStr(d['companionAlias'], fallback: 'Compañera');
          final otherAlias = isSpeaker ? companionAlias : speakerAlias;

          Timestamp? lastAt;
          final completedAt = d['completedAt'];
          final createdAt = d['createdAt'];
          final updatedAt = d['updatedAt'];

          // preferimos "última interacción" con algo razonable
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
              if (cur == null || lastAt.compareTo(cur) > 0) {
                current.lastAt = lastAt;
              }
            }
            if (current.alias.trim().isEmpty) current.alias = otherAlias;
          }
        }

        // Leemos hiddenPeople del usuario (para filtrar lista Personas)
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream:
              FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
          builder: (context, userSnap) {
            final userData = userSnap.data?.data() ?? const <String, dynamic>{};

            final hiddenPeople = (userData['hiddenPeople'] as List<dynamic>?)
                    ?.map((e) => e.toString())
                    .toSet() ??
                <String>{};

            // Rol (ajusta según tu schema si usas otro campo)
            final roleRaw = (userData['role'] ?? userData['userRole'] ?? '')
                .toString()
                .toLowerCase()
                .trim();

            final isSpeakerRole = roleRaw.contains('speaker') ||
                roleRaw.contains('hablante') ||
                roleRaw == 's';

            // ====== PEOPLE: filtro por hiddenPeople ======
            final people = peopleMap.values
                .where((p) => !hiddenPeople.contains(p.otherUid))
                .toList();

            // ====== PEOPLE: sort por modo (newest/oldest) ======
            people.sort((a, b) {
              final at = a.lastAt;
              final bt = b.lastAt;

              // si no hay fecha, se van al final
              if (at == null && bt == null) return 0;
              if (at == null) return 1;
              if (bt == null) return -1;

              if (_peopleSort == PeopleSortMode.newest) {
                return bt.compareTo(at);
              } else {
                return at.compareTo(bt);
              }
            });

            // ====== HISTORY: sort por modo (newest/oldest) ======
            historySessions.sort((a, b) {
              final ad = a.data()['completedAt'];
              final bd = b.data()['completedAt'];
              if (ad is! Timestamp || bd is! Timestamp) return 0;
              if (_historySort == HistorySortMode.newest) {
                return bd.compareTo(ad);
              } else {
                return ad.compareTo(bd);
              }
            });

            return ListView(
              // ✅ Más aire arriba (antes 22)
              padding: const EdgeInsets.fromLTRB(16, 36, 16, 110),
              children: [
                _RoleInviteBanner(
                  isSpeaker: isSpeakerRole,
                  onGoToOffers: _goToOffers,
                ),

                const SizedBox(height: 18),

                // =========================
                // Personas
                // =========================
                _CollapsibleHeader(
                  icon: Icons.people_alt_outlined,
                  iconColor: Colors.tealAccent,
                  title: 'historial de perfiles publicos',
                  countLabel: people.isEmpty
                      ? ''
                      : '${people.length} persona${people.length == 1 ? '' : 's'}',
                  expanded: _peopleExpanded,
                  onTap: () => setState(() => _peopleExpanded = !_peopleExpanded),
                ),
                const SizedBox(height: 6),

                // Barra de búsqueda + ordenar (Personas)
                if (_peopleExpanded) ...[
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
                  const SizedBox(height: 8),
                ],

                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 250),
                  crossFadeState: _peopleExpanded
                      ? CrossFadeState.showFirst
                      : CrossFadeState.showSecond,
                  firstChild: people.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(14),
                          child: Text(
                            'Aún no has interactuado con nadie.',
                            style: TextStyle(color: Colors.grey.shade400),
                          ),
                        )
                      : Column(
                          children: [
                            const SizedBox(height: 6),
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
                  secondChild: const SizedBox.shrink(),
                ),

                const SizedBox(height: 22),

                // =========================
                // Historial
                // =========================
                _CollapsibleHeader(
                  icon: Icons.history,
                  iconColor: Colors.lightBlueAccent,
                  title: 'Historial de conversaciones',
                  countLabel: historySessions.isEmpty
                      ? ''
                      : '${historySessions.length} sesión${historySessions.length == 1 ? '' : 'es'}',
                  expanded: _historyExpanded,
                  onTap: () => setState(() => _historyExpanded = !_historyExpanded),
                ),
                const SizedBox(height: 6),

                // Barra de búsqueda + ordenar (Historial)
                if (_historyExpanded) ...[
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
                  const SizedBox(height: 8),
                ],

                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 250),
                  crossFadeState: _historyExpanded
                      ? CrossFadeState.showFirst
                      : CrossFadeState.showSecond,
                  firstChild: historySessions.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(14),
                          child: Text(
                            'No hay sesiones finalizadas todavía.',
                            style: TextStyle(color: Colors.grey.shade400),
                          ),
                        )
                      : Column(
                          children: [
                            const SizedBox(height: 6),
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
                                      builder: (_) => SessionConversationScreen(
                                        sessionId: sessionId,
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                  secondChild: const SizedBox.shrink(),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _RoleInviteBanner extends StatelessWidget {
  final bool isSpeaker;
  final VoidCallback onGoToOffers;

  const _RoleInviteBanner({
    required this.isSpeaker,
    required this.onGoToOffers,
  });

  @override
  Widget build(BuildContext context) {
    final title = isSpeaker
        ? '¡Empieza una conversación!'
        : '¡Encuentra una conversación!';

    final body = isSpeaker
        ? 'Crea una oferta para que una compañera la tome y puedan conversar.'
        : 'Explora y toma una oferta para empezar a conversar con un hablante.';

    final cta = isSpeaker ? 'Crear oferta' : 'Ver ofertas';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white10,
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          const Icon(Icons.chat_bubble_outline, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style:
                      const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: onGoToOffers,
            child: Text(cta),
          ),
        ],
      ),
    );
  }
}

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
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: hintText,
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpiar',
                      icon: const Icon(Icons.close),
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
            border: Border.all(color: Colors.white24),
          ),
          child: sortWidget,
        ),
      ],
    );
  }
}

class _CollapsibleHeader extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String countLabel;
  final bool expanded;
  final VoidCallback onTap;

  const _CollapsibleHeader({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.countLabel,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          if (countLabel.isNotEmpty)
            Text(
              countLabel,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          const SizedBox(width: 4),
          Icon(
            expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
            size: 26,
          ),
        ],
      ),
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
  final Future<void> Function({required String myUid, required String otherUid})
      onHidePerson;
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
    return FutureBuilder<Map<String, dynamic>>(
      future: getUserData(person.otherUid),
      builder: (context, snap) {
        final userData = snap.data ?? const <String, dynamic>{};
        final companionCode =
            (userData['companionCode'] as String?)?.trim() ?? '';
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
              color: Colors.redAccent.withOpacity(0.25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.delete_outline, color: Colors.redAccent),
          ),
          confirmDismiss: (_) async {
            return confirmDialog(
              title: '¿Quitar de esta lista?',
              message:
                  'Esta persona dejará de aparecer en “Personas”, pero tus sesiones seguirán visibles en el historial.',
              confirmText: 'Quitar',
            );
          },
          onDismissed: (_) async {
            await onHidePerson(myUid: myUid, otherUid: person.otherUid);
          },
          child: Card(
            color: Colors.white10,
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              onTap: () => onOpenProfile(person.otherUid),
              leading: CircleAvatar(
                radius: 18,
                child: Text(
                  showAlias.isNotEmpty ? showAlias[0].toUpperCase() : '?',
                ),
              ),
              title: Text(
                showAlias,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (companionCode.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Código: $companionCode',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 18),
                          onPressed: () => onCopy(companionCode, toast: 'Código copiado.'),
                        ),
                      ],
                    ),
                  ],
                  if (lastStr.isNotEmpty)
                    Text(
                      'Última interacción: $lastStr',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                ],
              ),
              trailing: const Icon(Icons.chevron_right),
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
  final Future<void> Function({required String sessionId, required String myUid})
      onHideSession;
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

    final otherUid = isSpeaker
        ? (d['companionId'] as String? ?? '')
        : (d['speakerId'] as String? ?? '');

    // status label
    String statusLabel = 'Finalizada';
    Color statusColor = Colors.greenAccent;
    if (status == 'cancelled') {
      statusLabel = 'Cancelada';
      statusColor = Colors.redAccent;
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
      future: otherUid.isEmpty
          ? Future.value(const <String, dynamic>{})
          : getUserData(otherUid),
      builder: (context, snap) {
        final userData = snap.data ?? const <String, dynamic>{};
        final companionCode =
            (userData['companionCode'] as String?)?.trim() ?? '';

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
              color: Colors.redAccent.withOpacity(0.25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.delete_outline, color: Colors.redAccent),
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
            color: Colors.white10,
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onOpen(doc.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      child: Text(
                        otherAlias.isNotEmpty ? otherAlias[0].toUpperCase() : '?',
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
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (companionCode.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Código: $companionCode',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.copy, size: 18),
                                  onPressed: () => onCopy(
                                    companionCode,
                                    toast: 'Código copiado.',
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            'Real: $real min • Cobro: $billed min',
                            style: const TextStyle(fontSize: 11),
                          ),
                          if (completedStr.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              completedStr,
                              style: const TextStyle(fontSize: 10, color: Colors.grey),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  statusLabel,
                                  style: TextStyle(fontSize: 10, color: statusColor),
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
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
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
