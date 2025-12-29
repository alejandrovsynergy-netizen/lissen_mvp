import 'dart:async';

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
              IconButton(
                tooltip: 'Llamada',
                icon: const Icon(Icons.call),
                onPressed: () => _sendCallInvitation(
                  isVideo: false,
                  otherUserId: otherUserId,
                  otherAlias: otherAlias,
                ),
              ),
            if (isActive && callService.isInit)
              IconButton(
                tooltip: 'Videollamada',
                icon: const Icon(Icons.videocam),
                onPressed: () => _sendCallInvitation(
                  isVideo: true,
                  otherUserId: otherUserId,
                  otherAlias: otherAlias,
                ),
              ),
            if (isActive)
              IconButton(
                icon: _finishing
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.call_end),
                tooltip: 'Finalizar sesión',
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

    if (!_zegoReady || _zegoConnecting || !zimLogged) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              zimLogged ? 'Cargando chat…' : 'Conectando chat…',
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

    final messages = ZIMKitMessageListView(
      conversationID: peerConversationId,
      conversationType: ZIMConversationType.peer,
      scrollController: _listScrollController,
    );

    final input = ZIMKitMessageInput(
      conversationID: peerConversationId,
      conversationType: ZIMConversationType.peer,
      recordStatus: _recordStatus,
      listScrollController: _listScrollController,
    );

    if (!isActive) {
      return Stack(
        children: [
          Column(
            children: [
              Expanded(child: AbsorbPointer(child: messages)),
              AbsorbPointer(child: input),
            ],
          ),
          const Center(
            child: Text(
              'Sesión finalizada.',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Expanded(child: messages),
        input,
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
