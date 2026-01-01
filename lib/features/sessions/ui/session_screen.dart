import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:zego_zim/zego_zim.dart'; // ZIMConversationType
import 'package:zego_zimkit/zego_zimkit.dart';

import '../../payments/payments_api.dart';
import '../../zego/zego_config.dart';

class SessionConversationScreen extends StatefulWidget {
  final String sessionId;

  const SessionConversationScreen({super.key, required this.sessionId});

  @override
  State<SessionConversationScreen> createState() =>
      _SessionConversationScreenState();
}

class _SessionConversationScreenState extends State<SessionConversationScreen> {
  late final DocumentReference<Map<String, dynamic>> _sessionRef;

  bool _finishing = false;
  bool _captureOk = false;

  bool _zegoConnecting = false;
  bool _zegoReady = false;
  String? _zegoError;

  // Mínimo a cobrar cuando la que corta es la compañera
  static const int kMinBillingMinutes = 10;

  bool _showBillingHint = true;
  bool _showSafetyHint = true;
  bool _autoTimeoutTriggered = false;

  Map<String, dynamic>? _sessionData;
  bool _sessionLoading = true;
  String? _sessionError;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sessionSub;

  // ✅ Para incrustar chat sin Scaffold extra:
  final ScrollController _listScrollController = ScrollController();
  final ZIMKitRecordStatus _recordStatus = ZIMKitRecordStatus();
  bool _sentReadReceipt = false;
  static const List<String> _reactionEmojis = [
    '\u{1F44D}', // 👍
    '\u{2764}\u{FE0F}', // ❤️
    '\u{1F602}', // 😂
    '\u{1F62E}', // 😮
    '\u{1F622}', // 😢
    '\u{1F621}', // 😡
  ];


  @override
  void initState() {
    super.initState();

    _sessionRef =
        FirebaseFirestore.instance.collection('sessions').doc(widget.sessionId);

    _sessionLoading = true;
    _sessionSub = _sessionRef.snapshots().listen(
      (snap) {
        if (!mounted) return;

        if (!snap.exists) {
          setState(() {
            _sessionData = null;
            _sessionError = 'La sesión no existe o fue eliminada.';
            _sessionLoading = false;
          });
          return;
        }

        setState(() {
          _sessionData = snap.data();
          _sessionLoading = false;
          _sessionError = null;
          _sentReadReceipt = false;
        });

        _ensureZegoReady(); // ✅ intenta conectar ZIM cuando ya hay data
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _sessionError = 'Error en la sesión: $e';
          _sessionLoading = false;
        });
      },
    );
  }

  @override
  void dispose() {
    _sessionSub?.cancel();
    _listScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadSessionOnce() async {
    setState(() {
      _sessionLoading = true;
      _sessionError = null;
    });
    try {
      final snap = await _sessionRef.get();
      if (!snap.exists) {
        setState(() {
          _sessionData = null;
          _sessionError = 'La sesión no existe o fue eliminada.';
          _sessionLoading = false;
        });
        return;
      }
      setState(() {
        _sessionData = snap.data();
        _sessionLoading = false;
      });
      _ensureZegoReady();
    } catch (e) {
      setState(() {
        _sessionError = 'Error cargando sesión: $e';
        _sessionLoading = false;
      });
    }
  }

  String _resolveMyAlias(Map<String, dynamic> data, String myUid) {
    final speakerId = (data['speakerId'] ?? '').toString();
    if (speakerId == myUid) {
      return (data['speakerAlias'] ?? 'Hablante').toString();
    }
    return (data['companionAlias'] ?? 'Compañera').toString();
  }

  String _resolveOtherUserId(Map<String, dynamic> data, String myUid) {
    final speakerId = (data['speakerId'] ?? '').toString();
    final companionId = (data['companionId'] ?? '').toString();
    return speakerId == myUid ? companionId : speakerId;
  }

  String _resolveOtherAlias(Map<String, dynamic> data, String myUid) {
    final speakerId = (data['speakerId'] ?? '').toString();
    final speakerAlias = (data['speakerAlias'] ?? 'Hablante').toString();
    final companionAlias = (data['companionAlias'] ?? 'Compañera').toString();
    return speakerId == myUid ? companionAlias : speakerAlias;
  }

  bool _isZimLoggedInAs(String uid) {
    try {
      // Usamos dynamic para no romper con cambios de SDK.
      final dynamic u = (ZIMKit() as dynamic).currentUser();
      if (u == null) return false;

      final dynamic base = u.baseInfo;
      final dynamic idAny =
          (base?.userID ?? base?.userId ?? u.userID ?? u.userId ?? u.id);

      return idAny?.toString() == uid;
    } catch (_) {
      return false;
    }
  }

  Future<void> _disconnectZimSilently() async {
    try {
      await (ZIMKit() as dynamic).disconnectUser();
    } catch (_) {
      // silencioso
    }
  }

  /// ✅ Conecta ZIMKit para 1-a-1 (peer). SIN grupos.
  Future<void> _ensureZegoReady() async {
    if (_zegoConnecting || _sessionData == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Si AppSign está vacío, jamás conectará.
    if (kZegoAppSign.trim().isEmpty) {
      setState(() {
        _zegoReady = false;
        _zegoError = 'ZEGO AppSign vacío. Revisa zego_config.dart';
      });
      return;
    }

    // Si ya está listo y sigue logueado como este user, no hagas nada.
    if (_zegoReady && _isZimLoggedInAs(user.uid)) return;

    setState(() {
      _zegoConnecting = true;
      _zegoError = null;
    });

    Future<void> attemptOnce() async {
      final data = _sessionData!;
      final myAlias = _resolveMyAlias(data, user.uid);

      // Si ZIM está logueado como OTRO usuario, desconecta primero.
      if (!_isZimLoggedInAs(user.uid)) {
        await _disconnectZimSilently();
      }

      // ✅ En zego_zimkit, connectUser es Future<void>.
      await ZIMKit()
          .connectUser(id: user.uid, name: myAlias)
          .timeout(const Duration(seconds: 25));
    }

    try {
      // Reintento simple (2)
      for (int i = 0; i < 2; i++) {
        try {
          await attemptOnce();
          if (!mounted) return;
          setState(() {
            _zegoReady = true;
            _zegoError = null;
          });
          return;
        } catch (e) {
          if (i == 1) rethrow;
          await Future.delayed(const Duration(milliseconds: 800));
        }
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _zegoReady = false;
        _zegoError =
            'Zego tardó demasiado en conectar (red/lentitud del dispositivo). Reintenta.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _zegoReady = false;
        _zegoError = 'No se pudo conectar a Zego (chat): $e';
      });
    } finally {
      if (mounted) setState(() => _zegoConnecting = false);
    }
  }

  Future<void> _stopAnyOngoingCallOrInvitation({
    required String otherUserId,
    required String otherAlias,
  }) async {
    try {
      final service = ZegoUIKitPrebuiltCallInvitationService();
      if (!service.isInit) return;

      if (service.isInCall) {
        try {
          await service.controller.hangUp(context);
        } catch (_) {}
      }

      if (service.isInCalling) {
        try {
          await service.cancel(
            callees: [ZegoCallUser(otherUserId, otherAlias)],
          );
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _sendCallInvitation({
    required bool isVideo,
    required String otherUserId,
    required String otherAlias,
  }) async {
    final service = ZegoUIKitPrebuiltCallInvitationService();
    if (!service.isInit) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Llamadas no disponibles: CallInvitationService no está inicializado.',
          ),
        ),
      );
      return;
    }

    final ok = await service.send(
      invitees: [ZegoCallUser(otherUserId, otherAlias)],
      isVideoCall: isVideo,
      resourceID: kZegoCallInvitationResourceId,
      timeoutSeconds: 60,
    );

    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo enviar la invitación.')),
      );
    }
  }

  Future<void> _finishSession() async {
    if (_finishing) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    HapticFeedback.mediumImpact();
    setState(() => _finishing = true);

    try {
      final snap = await _sessionRef.get();
      final data = snap.data();

      if (data == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('La sesión ya no existe.')),
          );
        }
        await _loadSessionOnce();
        return;
      }

      final status = data['status'] as String? ?? 'active';
      if (status != 'active') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('La sesión ya estaba finalizada.')),
          );
        }
        await _loadSessionOnce();
        return;
      }

      final speakerId = (data['speakerId'] ?? '').toString();
      final endedBy = user.uid == speakerId ? 'speaker' : 'companion';

      final durationTotal = data['durationMinutes'] as int? ?? 30;

      int realMinutes = 0;
      final createdAtTs = data['createdAt'] as Timestamp?;
      if (createdAtTs != null) {
        final createdAt = createdAtTs.toDate();
        final now = DateTime.now();
        final diffMinutes = now.difference(createdAt).inMinutes;
        if (diffMinutes >= 0) realMinutes = diffMinutes;
      }

      if (realMinutes > durationTotal) realMinutes = durationTotal;

      int billingMinutes;
      bool minChargeApplied = false;

      if (endedBy == 'speaker') {
        billingMinutes = durationTotal;
      } else {
        if (realMinutes < kMinBillingMinutes) {
          billingMinutes = kMinBillingMinutes;
          minChargeApplied = true;
        } else {
          billingMinutes = realMinutes;
        }
      }

      final updateData = <String, dynamic>{
        'status': 'completed',
        'endedBy': endedBy,
        'completedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'realDurationMinutes': realMinutes,
        'billingMinutes': billingMinutes,
        'billingMinLimit': kMinBillingMinutes,
        'minChargeApplied': minChargeApplied,
      };

      await _sessionRef.update(updateData);

      final otherUserId = _resolveOtherUserId(data, user.uid);
      final otherAlias = _resolveOtherAlias(data, user.uid);
      await _stopAnyOngoingCallOrInvitation(
        otherUserId: otherUserId,
        otherAlias: otherAlias,
      );

      try {
        await PaymentsApi().captureSessionPayment(sessionId: widget.sessionId);
        _captureOk = true;
      } catch (_) {
        _captureOk = false;
      }

      final mergedData = {...data, ...updateData};

      if (mounted) {
        setState(() => _sessionData = mergedData);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _captureOk
                  ? 'Sesión finalizada ✅ (cobro capturado)'
                  : 'Sesión finalizada ✅ (cobro pendiente ⚠️)',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo finalizar la sesión: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  Future<void> _autoTimeoutSession() async {
    if (_autoTimeoutTriggered) return;
    _autoTimeoutTriggered = true;

    try {
      final user = FirebaseAuth.instance.currentUser;
      final snap = await _sessionRef.get();
      final data = snap.data();
      if (data == null) return;

      final status = data['status'] as String? ?? 'active';
      if (status != 'active') return;

      final durationTotal = data['durationMinutes'] as int? ?? 30;

      final updateData = <String, dynamic>{
        'status': 'completed',
        'endedBy': 'timeout',
        'completedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'realDurationMinutes': durationTotal,
        'billingMinutes': durationTotal,
        'billingMinLimit': kMinBillingMinutes,
        'minChargeApplied': false,
      };

      await _sessionRef.update(updateData);

      if (user != null) {
        final otherUserId = _resolveOtherUserId(data, user.uid);
        final otherAlias = _resolveOtherAlias(data, user.uid);
        await _stopAnyOngoingCallOrInvitation(
          otherUserId: otherUserId,
          otherAlias: otherAlias,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La sesión terminó automáticamente.')),
        );
      }
    } catch (_) {}
  }

  Future<void> _confirmFinishSession() async {
    if (_finishing) return;

    final shouldEnd =
        await showDialog<bool>(
              context: context,
              builder: (context) {
                return AlertDialog(
                  title: const Text('Finalizar sesión'),
                  content: const Text(
                    '¿Seguro que quieres finalizar la sesión? '
                    'Esta acción no se puede deshacer.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancelar'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Sí, finalizar'),
                    ),
                  ],
                );
              },
            ) ??
            false;

    if (!shouldEnd) return;
    await _finishSession();
  }


  Future<void> _showMessageMenu({
    required BuildContext context,
    required ZIMKitMessage message,
    required Offset globalPosition,
  }) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (context) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final emoji in _reactionEmojis)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: InkWell(
                              onTap: () =>
                                  Navigator.of(context).pop('react:$emoji'),
                              child: Text(
                                emoji,
                                style: const TextStyle(fontSize: 22),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (message.isMine)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop('delete'),
                    child: const Text('Eliminar para ambos'),
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null) return;


    if (selected == 'delete') {
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Eliminar mensaje'),
              content: const Text('Se eliminara para ambos.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancelar'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Eliminar'),
                ),
              ],
            ),
          ) ??
          false;

      if (!confirmed) return;
      try {
        await ZIMKit().recallMessage(message);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Mensaje eliminado para ambos.')),
          );
        }
      } catch (e) {
        try {
          await ZIMKit().deleteMessage([message]);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No se pudo eliminar para ambos. Se quitó para ti.'),
              ),
            );
          }
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('No se pudo eliminar: $e')),
            );
          }
        }
      }
      return;
    }

    final emoji = selected.replaceFirst('react:', '');
    final existing = message.reactions.value
        .where((r) => r.reactionType == emoji)
        .toList();
    final isSelfIncluded =
        existing.isNotEmpty ? existing.first.isSelfIncluded : false;

    try {
      if (isSelfIncluded) {
        await ZIMKit().deleteMessageReaction(message, emoji);
        _applyLocalReaction(message, emoji, add: false);
      } else {
        await ZIMKit().addMessageReaction(message, emoji);
        _applyLocalReaction(message, emoji, add: true);
      }
    } on PlatformException catch (e) {
      final msg = (e.message ?? '').toLowerCase();
      if (msg.contains('reaction key is existed')) {
        await ZIMKit().deleteMessageReaction(message, emoji);
        _applyLocalReaction(message, emoji, add: false);
      } else {
        rethrow;
      }
    }
  }

  void _applyLocalReaction(
    ZIMKitMessage message,
    String emoji, {
    required bool add,
  }) {
    final reactions = message.reactions.value;
    final index = reactions.indexWhere((r) => r.reactionType == emoji);

    if (add) {
      if (index == -1) {
        reactions.add(
          ZIMMessageReaction(
            reactionType: emoji,
            conversationID: message.info.conversationID,
            conversationType: message.info.conversationType,
            messageID: message.info.messageID,
            totalCount: 1,
            isSelfIncluded: true,
            userList: const [],
          ),
        );
      } else {
        final r = reactions[index];
        if (!r.isSelfIncluded) {
          r.totalCount = r.totalCount + 1;
          r.isSelfIncluded = true;
          reactions[index] = r;
        }
      }
    } else {
      if (index == -1) return;
      final r = reactions[index];
      if (r.isSelfIncluded) {
        r.totalCount = r.totalCount > 0 ? r.totalCount - 1 : 0;
        r.isSelfIncluded = false;
        if (r.totalCount == 0) {
          reactions.removeAt(index);
        } else {
          reactions[index] = r;
        }
      }
    }

    message.reactions.triggerNotify();
  }

  Widget _buildImageContent(ZIMKitMessage message) {
    final content = message.imageContent;
    if (content == null) return const SizedBox.shrink();

    final aspect = content.aspectRatio.isFinite && content.aspectRatio > 0
        ? content.aspectRatio
        : 1.0;

    ImageProvider? provider;
    if (content.fileLocalPath.isNotEmpty) {
      final file = File(content.fileLocalPath);
      if (file.existsSync()) {
        provider = FileImage(file);
      }
    }

    if (provider == null) {
      final url = message.isNetworkUrl
          ? content.fileDownloadUrl
          : (content.largeImageDownloadUrl.isNotEmpty
              ? content.largeImageDownloadUrl
              : content.thumbnailDownloadUrl);
      if (url.isNotEmpty) {
        provider = NetworkImage(url);
      }
    }

    return AspectRatio(
      aspectRatio: aspect,
      child: provider == null
          ? const Center(child: Icon(Icons.image_not_supported_outlined))
          : Image(
              image: provider,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.image_not_supported_outlined),
            ),
    );
  }

  Future<void> _openImageViewer({
    required BuildContext context,
    required ZIMKitMessage message,
  }) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) {
        return GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(16),
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: _buildImageContent(message),
            ),
          ),
        );
      },
    );
  }

  String _formatMessageTime(ZIMKitMessage message) {
    final ts = message.info.timestamp;
    if (ts <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Widget _buildBubble({
    required bool isMine,
    required Color bubbleColor,
    required Widget child,
    required String time,
    required Color timeColor,
    required Widget reactionsOverlay,
  }) {
    final radius = BorderRadius.circular(12);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: BoxDecoration(color: bubbleColor, borderRadius: radius),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              child,
              if (time.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 10,
                    color: timeColor.withOpacity(0.75),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        Positioned(
          bottom: 6,
          right: isMine ? -4 : null,
          left: isMine ? null : -4,
          child: CustomPaint(
            size: const Size(8, 8),
            painter: _BubbleTailPainter(color: bubbleColor, isMine: isMine),
          ),
        ),
        Positioned(
          bottom: -12,
          right: isMine ? 0 : null,
          left: isMine ? null : 0,
          child: reactionsOverlay,
        ),
      ],
    );
  }

  Widget _buildReactionsOverlay(ZIMKitMessage message) {
    return ValueListenableBuilder<List<ZIMMessageReaction>>(
      valueListenable: message.reactions,
      builder: (context, reactions, _) {
        final visible = reactions
            .where((r) =>
                _reactionEmojis.contains(r.reactionType) && r.totalCount > 0)
            .toList();
        if (visible.isEmpty) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withOpacity(0.85),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white24),
          ),
          child: Wrap(
            spacing: 6,
            children: [
              for (final reaction in visible)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(reaction.reactionType),
                    const SizedBox(width: 2),
                    Text(
                      reaction.totalCount.toString(),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
    required List<Color> colors,
  }) {
    final enabled = onPressed != null;
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: colors,
    );

    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: gradient,
          border: Border.all(color: Colors.white.withOpacity(0.18), width: 1),
          boxShadow: [
            BoxShadow(
              color: colors.last.withOpacity(0.45),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: colors.first.withOpacity(0.35),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: IconButton(
          tooltip: tooltip,
          icon: Icon(icon, size: 22, color: Colors.white),
          onPressed: onPressed,
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Debes iniciar sesión.')));
    }

    if (_sessionLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sesión')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_sessionError != null || _sessionData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sesión')),
        body: Center(
          child: Text(
            _sessionError ?? 'La sesión no existe o fue eliminada.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final data = _sessionData!;
    final status = (data['status'] ?? 'active').toString();
    final endedBy = data['endedBy'] as String?;
    final isActive = status == 'active';

    final speakerAlias = (data['speakerAlias'] ?? 'Hablante').toString();
    final companionAlias = (data['companionAlias'] ?? 'Compañera').toString();

    final price = (data['priceCents'] ?? 0) / 100.0;
    final duration = data['durationMinutes'] as int? ?? 30;
    final currency = (data['currency'] ?? 'usd').toString().toUpperCase();

    final realDuration = data['realDurationMinutes'] as int?;
    final billingMinutes = data['billingMinutes'] as int?;
    final minChargeApplied = data['minChargeApplied'] as bool? ?? false;
    final billingMinLimit =
        data['billingMinLimit'] as int? ?? kMinBillingMinutes;

    final isSpeakerInSession = (data['speakerId'] ?? '').toString() == user.uid;

    final otherUserId = _resolveOtherUserId(data, user.uid);
    final otherAlias = _resolveOtherAlias(data, user.uid);

    // ✅ 1 a 1 REAL:
    final peerConversationId = otherUserId;

    final createdAtTs = data['createdAt'] as Timestamp?;
    final createdAt = createdAtTs?.toDate();

    String statusLabel;
    if (status == 'active') {
      statusLabel = 'Activa';
    } else if (status == 'completed') {
      if (endedBy == 'speaker') {
        statusLabel = 'Finalizada por hablante';
      } else if (endedBy == 'companion') {
        statusLabel = 'Finalizada por compañera';
      } else if (endedBy == 'timeout') {
        statusLabel = 'Finalizada por tiempo';
      } else {
        statusLabel = 'Finalizada';
      }
    } else {
      statusLabel = status;
    }

    String durationText;
    if (!isActive && realDuration != null && billingMinutes != null) {
      if (minChargeApplied) {
        durationText =
            'Res: $duration min • Real: $realDuration • Cobro: $billingMinutes (min $billingMinLimit)';
      } else {
        durationText =
            'Res: $duration min • Real: $realDuration • Cobro: $billingMinutes';
      }
    } else if (realDuration != null && !isActive) {
      durationText = 'Res: $duration min • Real: $realDuration';
    } else {
      durationText = 'Reservada: $duration min';
    }

    final callService = ZegoUIKitPrebuiltCallInvitationService();

    return WillPopScope(
      onWillPop: () async {
        if (isActive) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No puedes salir de una sesión activa. '
                'Primero debes finalizarla.',
              ),
            ),
          );
          return false;
        }
        return true;
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: Text(isActive ? otherAlias : 'Sesión finalizada'),
          centerTitle: true,
          actions: [
            if (isActive && callService.isInit)
              _buildActionButton(
                tooltip: 'Llamada',
                icon: Icons.call,
                colors: const [Color(0xFF22D3EE), Color(0xFF2563EB)],
                onPressed: () => _sendCallInvitation(
                  isVideo: false,
                  otherUserId: otherUserId,
                  otherAlias: otherAlias,
                ),
              ),
            if (isActive && callService.isInit)
              _buildActionButton(
                tooltip: 'Videollamada',
                icon: Icons.videocam,
                colors: const [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                onPressed: () => _sendCallInvitation(
                  isVideo: true,
                  otherUserId: otherUserId,
                  otherAlias: otherAlias,
                ),
              ),
            if (isActive)
              _buildActionButton(
                tooltip: 'Finalizar sesión',
                icon: _finishing ? Icons.hourglass_top : Icons.call_end,
                colors: const [Color(0xFFF87171), Color(0xFFEF4444)],
                onPressed: _finishing ? null : _confirmFinishSession,
              ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    child: Text(
                      otherAlias.isNotEmpty ? otherAlias[0].toUpperCase() : '?',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'H: $speakerAlias • C: $companionAlias',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          durationText,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (isActive && createdAt != null)
                        StreamBuilder<int>(
                          stream: Stream.periodic(
                            const Duration(seconds: 1),
                            (_) {
                              final diff = DateTime.now()
                                  .difference(createdAt)
                                  .inSeconds;
                              return diff < 0 ? 0 : diff;
                            },
                          ),
                          builder: (context, snapshot) {
                            final totalSeconds = snapshot.data ?? 0;
                            final hours = totalSeconds ~/ 3600;
                            final minutes = (totalSeconds % 3600) ~/ 60;
                            final seconds = totalSeconds % 60;

                            String formatted;
                            if (hours > 0) {
                              formatted =
                                  '${hours.toString().padLeft(2, '0')}:'
                                  '${minutes.toString().padLeft(2, '0')}:'
                                  '${seconds.toString().padLeft(2, '0')}';
                            } else {
                              formatted =
                                  '${minutes.toString().padLeft(2, '0')}:'
                                  '${seconds.toString().padLeft(2, '0')}';
                            }

                            final sessionTotalSeconds = duration * 60;
                            if (isActive &&
                                !_autoTimeoutTriggered &&
                                sessionTotalSeconds > 0 &&
                                totalSeconds >= sessionTotalSeconds) {
                              _autoTimeoutSession();
                            }

                            return Text(
                              'Tiempo: $formatted',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            );
                          },
                        ),
                      const SizedBox(height: 2),
                      Text(
                        '\$${price.toStringAsFixed(2)} $currency',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color:
                              isActive ? Colors.greenAccent : Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            if (isActive && createdAt != null)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: StreamBuilder<int>(
                  stream: Stream.periodic(const Duration(seconds: 1), (_) {
                    final diff = DateTime.now().difference(createdAt).inSeconds;
                    return diff < 0 ? 0 : diff;
                  }),
                  builder: (context, snapshot) {
                    final totalSeconds = snapshot.data ?? 0;
                    final totalSessionSeconds = duration * 60;

                    double progress = 0;
                    if (totalSessionSeconds > 0) {
                      progress = totalSeconds / totalSessionSeconds;
                      if (progress.isNaN || progress.isInfinite) progress = 0;
                      if (progress < 0) progress = 0;
                      if (progress > 1) progress = 1;
                    }

                    final percent =
                        (progress * 100).clamp(0, 100).toStringAsFixed(0);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 6,
                            color: const Color(0xFF4F46E5),
                            backgroundColor: Colors.white12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Progreso de la sesión: $percent%',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

            if (isActive && !isSpeakerInSession && _showSafetyHint)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Stack(
                  children: [
                    _buildSafetyHintForCompanion(),
                    Positioned(
                      right: 4,
                      top: 4,
                      child: InkWell(
                        onTap: () => setState(() => _showSafetyHint = false),
                        child: const Icon(Icons.close, size: 16),
                      ),
                    ),
                  ],
                ),
              ),

            if (isActive && _showBillingHint)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Stack(
                  children: [
                    _buildBillingHint(isSpeakerInSession),
                    Positioned(
                      right: 4,
                      top: 4,
                      child: InkWell(
                        onTap: () => setState(() => _showBillingHint = false),
                        child: const Icon(Icons.close, size: 16),
                      ),
                    ),
                  ],
                ),
              ),

            Expanded(
              child: _buildZegoChat(
                isActive: isActive,
                peerConversationId: peerConversationId,
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildZegoChat({
    required bool isActive,
    required String peerConversationId,
  }) {
    final u = FirebaseAuth.instance.currentUser;
    final zimLogged = u != null && _isZimLoggedInAs(u.uid);
    final scheme = Theme.of(context).colorScheme;

    Widget wrapInput(Widget child) {
      return SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0B1220),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outline.withOpacity(0.7)),
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withOpacity(
                  scheme.brightness == Brightness.dark ? 0.30 : 0.20,
                ),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: child,
        ),
      );
    }

    if (_zegoError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _zegoError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _zegoConnecting ? null : _ensureZegoReady,
              child: Text(_zegoConnecting ? 'Conectando...' : 'Reintentar'),
            ),
          ],
        ),
      );
    }

    if (!_sentReadReceipt) {
      _sentReadReceipt = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          ZIM.getInstance()?.sendConversationMessageReceiptRead(
            peerConversationId,
            ZIMConversationType.peer,
          );
        } catch (_) {}
      });
    }

    if (!_zegoReady || _zegoConnecting || !zimLogged) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              zimLogged ? 'Cargando chat...' : 'Conectando chat...',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _zegoConnecting ? null : _ensureZegoReady,
              child: const Text('Reconectar'),
            ),
          ],
        ),
      );
    }

    final messageTheme = Theme.of(context).copyWith(
      primaryColor: const Color(0xFF2563EB),
    );

    final myBubbleColor = const Color(0xFF2563EB);
    final otherBubbleColor = const Color(0xFF1E293B);
    final otherTextColor = const Color(0xFFE2E8F0);

    final messages = ZIMKitMessageListView(
      conversationID: peerConversationId,
      conversationType: ZIMConversationType.peer,
      scrollController: _listScrollController,
      itemBuilder: (context, message, defaultWidget) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onLongPressStart: (details) {
            _showMessageMenu(
              context: context,
              message: message,
              globalPosition: details.globalPosition,
            );
          },
          child: defaultWidget,
        );
      },
      onLongPress: (context, details, message, _) {
        _showMessageMenu(
          context: context,
          message: message,
          globalPosition: details.globalPosition,
        );
      },
      theme: messageTheme,
      statusBuilder: (context, message, defaultWidget) {
        if (!message.isMine) return const SizedBox.shrink();

        final sentStatus = message.info.sentStatus;
        final receiptStatus = message.info.receiptStatus;

        IconData icon;
        Color color;

        if (sentStatus == ZIMMessageSentStatus.sending) {
          icon = Icons.access_time;
          color = Colors.white54;
        } else if (sentStatus == ZIMMessageSentStatus.failed) {
          icon = Icons.error_outline;
          color = Colors.redAccent;
        } else if (receiptStatus == ZIMMessageReceiptStatus.done) {
          icon = Icons.done_all;
          color = const Color(0xFF22D3EE);
        } else {
          icon = Icons.done;
          color = Colors.white70;
        }

        return Padding(
          padding: const EdgeInsets.only(left: 6, top: 2),
          child: Icon(icon, size: 14, color: color),
        );
      },
      messageContentBuilder: (context, message, defaultWidget) {
        if (message.type == ZIMMessageType.image &&
            message.imageContent != null) {
          final time = _formatMessageTime(message);
          return Flexible(
            child: GestureDetector(
              onTap: () => _openImageViewer(context: context, message: message),
              onLongPressStart: (details) {
                _showMessageMenu(
                  context: context,
                  message: message,
                  globalPosition: details.globalPosition,
                );
              },
              child: _buildBubble(
                isMine: message.isMine,
                bubbleColor:
                    message.isMine ? myBubbleColor : otherBubbleColor,
                time: time,
                timeColor: message.isMine ? Colors.white : otherTextColor,
                reactionsOverlay: _buildReactionsOverlay(message),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: _buildImageContent(message),
                  ),
                ),
              ),
            ),
          );
        }

        if (message.type != ZIMMessageType.text ||
            message.textContent?.text == null) {
          return defaultWidget;
        }

        final text = message.textContent!.text;
        final time = _formatMessageTime(message);
        return Flexible(
          child: GestureDetector(
            child: _buildBubble(
              isMine: message.isMine,
              bubbleColor: message.isMine ? myBubbleColor : otherBubbleColor,
              time: time,
              timeColor: message.isMine ? Colors.white : otherTextColor,
              reactionsOverlay: _buildReactionsOverlay(message),
              child: Text(
                text,
                textAlign: TextAlign.left,
                style: TextStyle(
                  color: message.isMine ? Colors.white : otherTextColor,
                ),
              ),
            ),
          ),
        );
      },
    );

    final input = ZIMKitMessageInput(
      conversationID: peerConversationId,
      conversationType: ZIMConversationType.peer,
      recordStatus: _recordStatus,
      listScrollController: _listScrollController,
      showMoreButton: false,
    );

    if (!isActive) {
      return Stack(
        children: [
          Column(
            children: [
              Expanded(child: AbsorbPointer(child: messages)),
              const SizedBox(height: 4),
              wrapInput(AbsorbPointer(child: input)),
            ],
          ),
          const Center(
            child: Text(
              'Sesion finalizada.',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Expanded(child: messages),
        const SizedBox(height: 4),
        wrapInput(input),
      ],
    );
  }

  Widget _buildBillingHint(bool isSpeaker) {
    final icon = isSpeaker ? Icons.warning_amber_rounded : Icons.info;
    final bgColor = isSpeaker
        ? Colors.red.withOpacity(0.12)
        : Colors.green.withOpacity(0.12);
    final borderColor = isSpeaker ? Colors.redAccent : Colors.greenAccent;

    final title = isSpeaker
        ? 'Importante para ti (hablante)'
        : 'Importante para ti (compañera)';

    final text = isSpeaker
        ? 'Si tú terminas la sesión antes de tiempo, se cobra el total de minutos reservados.'
        : 'Si tú terminas la sesión antes de tiempo, se te paga al menos $kMinBillingMinutes minutos, aunque haya durado menos.';

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor.withOpacity(0.7)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 22, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(text, style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyHintForCompanion() {
    const title = 'Antes de iniciar (para ti, compañera)';
    const text =
        'Te recomendamos establecer límites claros desde el principio (temas que no quieres tratar, tono, duración y reglas de respeto). '
        'Procura también cerrar las conversaciones que inicias: si algo queda pendiente, retómenlo de forma ordenada; si ya quedó resuelto, finalicen la sesión con claridad. '
        'Si en cualquier momento te sientes incómoda o se te falta al respeto, tienes total libertad de pausar o finalizar la sesión de inmediato.';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF4F46E5).withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF4F46E5).withOpacity(0.55),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 22, 8),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 2),
                Text(text, style: TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  final Color color;
  final bool isMine;

  _BubbleTailPainter({required this.color, required this.isMine});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();
    if (isMine) {
      path.moveTo(0, 0);
      path.lineTo(size.width, size.height / 2);
      path.lineTo(0, size.height);
    } else {
      path.moveTo(size.width, 0);
      path.lineTo(0, size.height / 2);
      path.lineTo(size.width, size.height);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
