import 'dart:async'; // necesario para Stream.periodic

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 👈 para HapticFeedback
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:zego_zimkit/zego_zimkit.dart';
import '../../payments/payments_api.dart';
import '../../zego/zego_config.dart';
import '../../zego/zego_token_service.dart';

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
  final ZegoTokenService _zegoTokenService = ZegoTokenService();

  bool _zegoConnecting = false;
  bool _zegoReady = false;
  String? _zegoError;
  ZegoTokenResponse? _zegoToken;


  // Mínimo a cobrar cuando la que corta es la compañera
  static const int kMinBillingMinutes = 10;

  // Mostrar u ocultar el aviso de reglas
  bool _showBillingHint = true;

  // ✅ Mostrar u ocultar el aviso de límites (solo compañera)
  bool _showSafetyHint = true;

  // Para no disparar el timeout más de una vez
  bool _autoTimeoutTriggered = false;

  // 🔹 Estado local de la sesión
  Map<String, dynamic>? _sessionData;
  bool _sessionLoading = true;
  String? _sessionError;

  // 🔹 Listener en tiempo real de la sesión
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sessionSub;

  @override
  void initState() {
    super.initState();
    _sessionRef =
        FirebaseFirestore.instance.collection('sessions').doc(widget.sessionId);

    // Escuchar la sesión en tiempo real para actualizar la UI
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
        _ensureZegoReady();
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
    super.dispose();
  }

  // ============================================================
  // 🔧 Utilidades internas
  // ============================================================

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

  Future<void> _ensureZegoGroup({
    required String groupId,
    required String groupName,
    required List<String> userIds,
  }) async {
    try {
      await ZIMKit().createGroup(
        groupName: groupName,
        groupID: groupId,
        userIDs: userIds,
      );
    } catch (_) {
      try {
        await ZIMKit().joinGroup(groupId);
      } catch (_) {}
    }
  }

  Future<void> _ensureZegoReady() async {
    if (_zegoReady || _zegoConnecting || _sessionData == null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _zegoConnecting = true;
      _zegoError = null;
    });

    try {
      final data = _sessionData!;
      final myAlias = _resolveMyAlias(data, user.uid);
      final otherUserId = _resolveOtherUserId(data, user.uid);
      final token = await _zegoTokenService.fetchToken(
        userId: user.uid,
        userName: myAlias,
      );

      await ZIMKit().connectUser(
        id: user.uid,
        name: myAlias,
        token: token.token,
      );

      await _ensureZegoGroup(
        groupId: widget.sessionId,
        groupName: 'session-${widget.sessionId}',
        userIds: [user.uid, otherUserId],
      );

      if (!mounted) return;
      setState(() {
        _zegoToken = token;
        _zegoReady = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _zegoError = 'No se pudo conectar a Zego: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _zegoConnecting = false);
      }
    }
  }

  void _openCall({required bool video}) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (!_zegoReady || _zegoToken == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El chat aún se está conectando.'),
        ),
      );
      return;
    }

    final data = _sessionData;
    if (data == null) return;
    final myAlias = _resolveMyAlias(data, user.uid);
    final config = video
        ? ZegoUIKitPrebuiltCallConfig.oneOnOneVideoCall()
        : ZegoUIKitPrebuiltCallConfig.oneOnOneVoiceCall();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ZegoUIKitPrebuiltCall(
          appID: kZegoAppId,
          userID: user.uid,
          userName: myAlias,
          callID: widget.sessionId,
          token: _zegoToken!.token,
          config: config,
        ),
      ),
    );
  }

  // ============================================================
  // 🔵 FINALIZAR SESIÓN (lógica de cobros manual: botón)
  // ============================================================
  Future<void> _finishSession() async {
    if (_finishing) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Vibración media al finalizar sesión
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

      final speakerId = data['speakerId'] as String? ?? '';
      final endedBy = user.uid == speakerId ? 'speaker' : 'companion';

      // Duración total contratada (ej. 30 min)
      final durationTotal = data['durationMinutes'] as int? ?? 30;

      // Calcular minutos reales usados (desde createdAt hasta ahora)
      int realMinutes = 0;
      final createdAtTs = data['createdAt'] as Timestamp?;
      if (createdAtTs != null) {
        final createdAt = createdAtTs.toDate();
        final now = DateTime.now();
        final diffMinutes = now.difference(createdAt).inMinutes;
        if (diffMinutes >= 0) {
          realMinutes = diffMinutes;
        }
      }

      // 🔒 Candado: nunca más de lo reservado
      if (realMinutes > durationTotal) {
        realMinutes = durationTotal;
      }

      // Calcular minutos a cobrar según quién terminó
      int billingMinutes;
      bool minChargeApplied = false;

      if (endedBy == 'speaker') {
        // Si el hablante corta, paga TODO (duración contratada)
        billingMinutes = durationTotal;
      } else {
        // Si la compañera corta, mínimo 10 min
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

      try {
        await PaymentsApi().captureSessionPayment(sessionId: widget.sessionId);
        _captureOk = true;
      } catch (e) {
        _captureOk = false;
        debugPrint('Stripe capture fallo: $e');
      }


      // Mezclamos los datos antiguos con los nuevos para actualizar la UI
      final mergedData = {...data, ...updateData};

      if (mounted) {
        // Actualizamos _sessionData para que la UI refleje el cambio
        setState(() {
          _sessionData = mergedData;
        });

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
    }
 finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  // ============================================================
  // 🔵 AUTO-TIMEOUT (se llama solo desde el reloj cuando se cumple el tiempo)
  // ============================================================
  Future<void> _autoTimeoutSession() async {
    if (_autoTimeoutTriggered) return; // seguridad extra
    _autoTimeoutTriggered = true;

    try {
      final snap = await _sessionRef.get();
      final data = snap.data();
      if (data == null) return;

      final status = data['status'] as String? ?? 'active';
      if (status != 'active') return;

      final durationTotal = data['durationMinutes'] as int? ?? 30;

      // En timeout consideramos que se cumplió la duración contratada
      final realMinutes = durationTotal;
      final billingMinutes = durationTotal;

      final updateData = <String, dynamic>{
        'status': 'completed',
        'endedBy': 'timeout',
        'completedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'realDurationMinutes': realMinutes,
        'billingMinutes': billingMinutes,
        'billingMinLimit': kMinBillingMinutes,
        'minChargeApplied': false,
      };

      await _sessionRef.update(updateData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La sesión terminó automáticamente.')),
        );
      }
    } catch (_) {
      // Si falla, simplemente no hacemos nada más.
    }
  }

  // ============================================================
  // 🔵 CONFIRMAR FINALIZAR SESIÓN
  // ============================================================
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

  // ============================================================
  // 🔵 UI COMPLETA DE LA SESIÓN
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Debes iniciar sesión.')));
    }

    // ⏳ Carga inicial de la sesión
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
    final status = data['status'] as String? ?? 'active';
    final endedBy = data['endedBy'] as String?;
    final isActive = status == 'active';

    final speakerAlias = data['speakerAlias'] ?? 'Hablante';
    final companionAlias = data['companionAlias'] ?? 'Compañera';

    final price = (data['priceCents'] ?? 0) / 100.0;
    final duration = data['durationMinutes'] as int? ?? 30;
    final currency = (data['currency'] ?? 'usd').toUpperCase();

    final realDuration = data['realDurationMinutes'] as int?;
    final billingMinutes = data['billingMinutes'] as int?;
    final minChargeApplied = data['minChargeApplied'] as bool? ?? false;
    final billingMinLimit =
        data['billingMinLimit'] as int? ?? kMinBillingMinutes;

    final isSpeakerInSession = data['speakerId'] == user.uid;
    final otherAlias = isSpeakerInSession ? companionAlias : speakerAlias;

    // createdAt para el reloj
    final createdAtTs = data['createdAt'] as Timestamp?;
    final createdAt = createdAtTs?.toDate();

    // Label de estado amigable
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

    // Texto de duración compacto (cuando ya terminó)
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

    // ⛔ BLOQUEAR BACK mientras la sesión está activa
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
            // Placeholder llamada de voz
            IconButton(
              icon: const Icon(Icons.call),
              onPressed: isActive ? () => _openCall(video: false) : null,
            ),
            // Placeholder videollamada
            IconButton(
              icon: const Icon(Icons.videocam),
              onPressed: isActive ? () => _openCall(video: true) : null,
            ),
            // Botón pequeño para finalizar sesión (solo si está activa)
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
            // ======================================================
            // 🔸 HEADER PEQUEÑO DE SESIÓN
            // ======================================================
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
                      // ⏱️ Reloj visual + auto-timeout
                      if (isActive && createdAt != null)
                        StreamBuilder<int>(
                          stream: Stream.periodic(const Duration(seconds: 1), (
                            _,
                          ) {
                            final diff = DateTime.now()
                                .difference(createdAt)
                                .inSeconds;
                            return diff < 0 ? 0 : diff;
                          }),
                          builder: (context, snapshot) {
                            final totalSeconds = snapshot.data ?? 0;
                            final hours = totalSeconds ~/ 3600;
                            final minutes = (totalSeconds % 3600) ~/ 60;
                            final seconds = totalSeconds % 60;

                            String formatted;
                            if (hours > 0) {
                              formatted =
                                  '${hours.toString().padLeft(2, '0')}'
                                  ':${minutes.toString().padLeft(2, '0')}'
                                  ':${seconds.toString().padLeft(2, '0')}';
                            } else {
                              formatted =
                                  '${minutes.toString().padLeft(2, '0')}'
                                  ':${seconds.toString().padLeft(2, '0')}';
                            }

                            // 🔥 Auto-timeout: cuando se cumple la duración
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
                          color: isActive ? Colors.greenAccent : Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ======================================================
            // 🔸 BARRA DE PROGRESO DE LA SESIÓN (✅ FIX COLOR / TRACK)
            // ======================================================
            if (isActive && createdAt != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                            // ✅ en lugar del verde del theme
                            color: const Color(0xFF4F46E5),
                            // ✅ track neutro (evita que se vea “relleno” desde inicio)
                            backgroundColor: Colors.white12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Progreso de la sesión: $percent%',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    );
                  },
                ),
              ),

            // ======================================================
            // 🔸 AVISO LÍMITES (✅ SOLO COMPAÑERA, CERRABLE)
            // ======================================================
            if (isActive && !isSpeakerInSession && _showSafetyHint)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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

            // ======================================================
            // 🔸 AVISO DE REGLA DE COBRO (con botón de cerrar)
            // ======================================================
            if (isActive && _showBillingHint)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Stack(
                  children: [
                    _buildBillingHint(isSpeakerInSession),
                    Positioned(
                      right: 4,
                      top: 4,
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _showBillingHint = false;
                          });
                        },
                        child: const Icon(Icons.close, size: 16),
                      ),
                    ),
                  ],
                ),
              ),

            Expanded(child: _buildZegoChat(isActive: isActive)),
          ],
        ),
      ),
    );
  }

  Widget _buildZegoChat({required bool isActive}) {
    if (_zegoError != null) {
      return Center(
        child: Text(
          _zegoError!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.redAccent),
        ),
      );
    }

    if (!_zegoReady) {
      return const Center(child: CircularProgressIndicator());
    }

    Widget chatBody = ZIMKitMessageListPage(
      conversationID: widget.sessionId,
      conversationType: ZIMConversationType.group,
    );

    if (!isActive) {
      chatBody = Stack(
        children: [
          AbsorbPointer(child: chatBody),
          const Center(
            child: Text(
              'Sesión finalizada.',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ],
      );
    }

    return chatBody;
  }

  // ============================================================
  // 🔵 Mensaje visual con reglas de cobro según rol
  // ============================================================
  Widget _buildBillingHint(bool isSpeaker) {
    final icon = isSpeaker ? Icons.warning_amber_rounded : Icons.info;
    final bgColor =
        isSpeaker ? Colors.red.withOpacity(0.12) : Colors.green.withOpacity(0.12);
    final borderColor = isSpeaker ? Colors.redAccent : Colors.greenAccent;

    final title =
        isSpeaker ? 'Importante para ti (hablante)' : 'Importante para ti (compañera)';

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
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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

  // ============================================================
  // ✅ Aviso para la compañera: límites y cierre de conversación
  // ============================================================
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
        border: Border.all(color: const Color(0xFF4F46E5).withOpacity(0.55)),
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
