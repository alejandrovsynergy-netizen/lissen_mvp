import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../features/payments/speaker_payment_method.dart';

Future<String?> showCreateOfferDialog({
  required BuildContext context,
  required String userId,
  required String alias,
  required String country,
  required String city,
  String? photoUrl,
  String? bio,
  String? offerId, // si viene -> edición
  Map<String, dynamic>? initialData,
  String? prefillCompanionCode,
  bool createdFromExplore = false,
  String? targetCompanionId,
}) async {
  return showDialog<String?>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withOpacity(0.25),
    builder: (_) => _CreateOfferDialog(
      userId: userId,
      alias: alias,
      country: country,
      city: city,
      photoUrl: photoUrl ?? '',
      bio: bio ?? '',
      offerId: offerId,
      initialData: initialData,
      prefillCompanionCode: prefillCompanionCode,
      createdFromExplore: createdFromExplore,
      targetCompanionId: targetCompanionId,
    ),
  );
}

class _CreateOfferDialog extends StatefulWidget {
  final String userId;
  final String alias;
  final String country;
  final String city;
  final String photoUrl;
  final String bio;

  final String? offerId;
  final Map<String, dynamic>? initialData;
  final String? prefillCompanionCode;
  final bool createdFromExplore;
  final String? targetCompanionId;

  const _CreateOfferDialog({
    required this.userId,
    required this.alias,
    required this.country,
    required this.city,
    required this.photoUrl,
    required this.bio,
    this.offerId,
    this.initialData,
    this.prefillCompanionCode,
    this.createdFromExplore = false,
    this.targetCompanionId,
  });

  @override
  State<_CreateOfferDialog> createState() => _CreateOfferDialogState();
}

class _CreateOfferDialogState extends State<_CreateOfferDialog> {
  // ============================
  // CONTROLADORES
  // ============================
  final TextEditingController _descC = TextEditingController();
  final TextEditingController _amountC = TextEditingController();
  final TextEditingController _companionCodeC = TextEditingController();

  // ============================
  // ESTADO
  // ============================
  String _category = 'vida_diaria'; // Tema de conversación
  String _tone = 'relajada_cercana'; // Estilo de conversación

  int _durationMinutes = 30;
  String _type = 'chat'; // chat | voice | video (OffersPage usa voice/video)

  bool _saving = false;

  // Hint auto-monto
  bool _showAutoAmountHint = false;
  Timer? _hintTimer;
  bool _settingAmountProgrammatically = false;
  Timer? _codeDebounce;
  final Map<String, Map<String, int>> _companionRatesCache = {};

  // ============================
  // ERRORES VISIBLES
  // ============================
  String? _categoryError;
  String? _toneError;
  String? _durationError;
  String? _amountError;
  String? _descError;
  String? _companionCodeError;

  static const int _minDesc = 20;
  static const int _maxDesc = 200;
  final List<String> _descriptionSuggestions = [
    'Quiero una conversación tranquila para ordenar ideas y pensar con claridad.',
    'Busco hablar sobre una decisión importante que estoy por tomar.',
    'Me gustaría una charla ligera para despejarme y pasar un buen rato.',
    'Quiero compartir una situación personal y escuchar otro punto de vista.',
    'Busco una conversación directa y honesta sobre un tema específico.',
    'Necesito una charla motivadora para recuperar enfoque y energía.',
  ];

  int _suggestionIndex = 0;

  @override
  void initState() {
    super.initState();

    // Precarga (edición) con compatibilidad (campos nuevos + legacy)
    final d = widget.initialData;
    if (d != null) {
      // Tema / estilo (pueden venir como category/tone o topic/style)
      final cat = (d['category'] ?? d['topic'])?.toString().trim();
      if (cat != null && cat.isNotEmpty) _category = cat;

      final tone = (d['tone'] ?? d['style'])?.toString().trim();
      if (tone != null && tone.isNotEmpty) _tone = tone;

      // Duración
      final dm = d['durationMinutes'] ?? d['minMinutes'];
      if (dm is int) _durationMinutes = dm;

      // Tipo (nuevo: communicationType, legacy: type)
      final t = (d['communicationType'] ?? d['type'])?.toString();
      if (t != null && t.isNotEmpty) _type = t;

      // Monto (nuevo: priceCents, fallback: totalMinAmountCents)
      final cents = d['priceCents'] ?? d['totalMinAmountCents'];
      if (cents is num) {
        _amountC.text = (cents / 100).round().toString();
      }

      _descC.text = (d['description'] ?? '').toString();
      _companionCodeC.text = (d['companionCode'] ?? '').toString();
    }

    final prefill = widget.prefillCompanionCode?.trim() ?? '';
    if (_companionCodeC.text.trim().isEmpty && prefill.isNotEmpty) {
      _companionCodeC.text = prefill;
    }

    _companionCodeC.addListener(_onCompanionCodeChanged);
    _recalculateAmount(showHint: false);
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _codeDebounce?.cancel();
    _companionCodeC.removeListener(_onCompanionCodeChanged);
    _descC.dispose();
    _amountC.dispose();
    _companionCodeC.dispose();
    super.dispose();
  }

  // ============================
  // CÁLCULO DE MONTO (MXN)
  // ============================
  int _computeSuggestedAmount() {
    switch (_type) {
      case 'voice':
        return {15: 105, 30: 150, 45: 200, 60: 245}[_durationMinutes] ?? 150;
      case 'video':
        return {15: 155, 30: 220, 45: 300, 60: 365}[_durationMinutes] ?? 220;
      default:
        return {15: 70, 30: 100, 45: 135, 60: 165}[_durationMinutes] ?? 100;
    }
  }

  void _setAmount(int amount, {bool showHint = true}) {
    _settingAmountProgrammatically = true;
    _amountC.text = amount.toString();
    _settingAmountProgrammatically = false;

    if (showHint) {
      _hintTimer?.cancel();
      if (mounted) setState(() => _showAutoAmountHint = true);
      _hintTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _showAutoAmountHint = false);
      });
    }
  }

  void _recalculateAmount({bool showHint = true}) {
    _applyCompanionRateIfAny(showHint: showHint);
  }

  void _onCompanionCodeChanged() {
    if (_settingAmountProgrammatically) return;
    _codeDebounce?.cancel();
    _codeDebounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      _applyCompanionRateIfAny(showHint: true);
    });
  }

  Future<Map<String, int>?> _getCompanionRatesForCode(String code) async {
    if (_companionRatesCache.containsKey(code)) {
      return _companionRatesCache[code];
    }

    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('companionCode', isEqualTo: code)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return null;

    final data = snap.docs.first.data();
    final role = (data['role'] as String?)?.toLowerCase();
    if (role != 'companion') return null;

    final confirmedAt = data['ratesLastConfirmedAt'];
    if (confirmedAt == null) return null;

    final map = <String, int>{};
    if (data['rateChat15Cents'] is int) {
      map['chat'] = data['rateChat15Cents'] as int;
    }
    if (data['rateVoice15Cents'] is int) {
      map['voice'] = data['rateVoice15Cents'] as int;
    }
    if (data['rateVideo15Cents'] is int) {
      map['video'] = data['rateVideo15Cents'] as int;
    }

    if (map.isEmpty) return null;
    _companionRatesCache[code] = map;
    return map;
  }

  Future<void> _applyCompanionRateIfAny({bool showHint = true}) async {
    final suggested = _computeSuggestedAmount();
    int amount = suggested;

    final code = _companionCodeC.text.trim();
    if (code.isNotEmpty && _durationMinutes % 15 == 0) {
      final rates = await _getCompanionRatesForCode(code);
      if (rates != null) {
        final rate15 = rates[_type];
        if (rate15 != null && rate15 > 0) {
          final totalCents = rate15 * (_durationMinutes ~/ 15);
          final computed = totalCents ~/ 100;
          if (computed > 0) amount = computed;
        }
      }
    }

    _setAmount(amount, showHint: showHint);
  }

  Future<int> _resolveAmountForSave() async {
    int amountPesos = int.parse(_amountC.text.trim());
    final code = _companionCodeC.text.trim();
    if (code.isNotEmpty && _durationMinutes % 15 == 0) {
      final rates = await _getCompanionRatesForCode(code);
      if (rates != null) {
        final rate15 = rates[_type];
        if (rate15 != null && rate15 > 0) {
          final totalCents = rate15 * (_durationMinutes ~/ 15);
          final computed = totalCents ~/ 100;
          if (computed > 0 && computed != amountPesos) {
            amountPesos = computed;
            _setAmount(amountPesos, showHint: false);
          }
        }
      }
    }
    return amountPesos;
  }

  // ============================
  // VALIDACIÓN CÓDIGO COMPAÑERA
  // ============================
  Future<String?> _validateCompanionCode(String code) async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('companionCode', isEqualTo: code)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return 'Codigo de companera no valido';

    final doc = snap.docs.first;
    final data = doc.data();
    final role = (data['role'] as String?)?.toLowerCase();
    if (role != null && role.isNotEmpty && role != 'companion') {
      return 'Codigo de companera no valido';
    }

    final blockedByCompanion = (data['blockedUsers'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .contains(widget.userId) ==
        true;
    if (blockedByCompanion) {
      return 'Esta companera te bloqueo.';
    }

    final meSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .get();
    final meData = meSnap.data() ?? {};
    final blockedByMe = (meData['blockedUsers'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .contains(doc.id) ==
        true;
    if (blockedByMe) {
      return 'Has bloqueado a esta companera.';
    }

    return null;
  }

  // ============================
  // VALIDACIÓN GENERAL
  // ============================
  Future<bool> _validateAll() async {
    bool ok = true;

    setState(() {
      _categoryError = null;
      _toneError = null;
      _durationError = null;
      _amountError = null;
      _descError = null;
      _companionCodeError = null;
    });

    if (_category.trim().isEmpty) {
      _categoryError = 'Selecciona un tema de conversación';
      ok = false;
    }

    if (_tone.trim().isEmpty) {
      _toneError = 'Selecciona un estilo de conversación';
      ok = false;
    }

    if (!const [15, 30, 45, 60].contains(_durationMinutes)) {
      _durationError = 'Selecciona una duración válida';
      ok = false;
    }

    final desc = _descC.text.trim();
    if (desc.length < _minDesc) {
      _descError = 'Describe un poco más (mínimo $_minDesc caracteres)';
      ok = false;
    }

    final amount = int.tryParse(_amountC.text.trim()) ?? 0;
    final min = _computeSuggestedAmount();
    if (amount < min) {
      _amountError = 'Monto mínimo para esta opción: $min';
      ok = false;
    }

    final code = _companionCodeC.text.trim();
    if (code.isNotEmpty) {
      final error = await _validateCompanionCode(code);
      if (error != null) {
        _companionCodeError = error;
        ok = false;
      }
    }

    if (mounted) setState(() {});
    return ok;
  }

  // ============================
  // GUARDAR
  // ============================
  Future<void> _save() async {
    if (_saving) return;

    final valid = await _validateAll();
    if (!valid) return;

    setState(() => _saving = true);

    try {
      final amountPesos = await _resolveAmountForSave();

      final existingStatus = (widget.initialData?['status'] ?? '').toString();
      final bool shouldGatePayment =
          widget.offerId == null || existingStatus == 'payment_required';

      String publishStatus = existingStatus.isNotEmpty ? existingStatus : 'active';
      if (shouldGatePayment) {
        final payments = SpeakerPaymentMethod();
        final hasCard = await payments.ensureHasPaymentMethod(
          context: context,
          uid: widget.userId,
        );
        publishStatus = hasCard ? 'active' : 'payment_required';
      }


      // Guardar lo que OffersPage espera + conservar lo tuyo
      final data = <String, dynamic>{
        // ===== CONTRATO OffersPage =====
        'speakerId': widget.userId,
        'speakerAlias': widget.alias,
        'speakerCountry': widget.country,
        'speakerCity': widget.city,

        'communicationType': _type, // chat | voice | video
        'durationMinutes': _durationMinutes,

        'priceCents': amountPesos * 100,
        'totalMinAmountCents': amountPesos * 100, // respaldo por compat

        'description': _descC.text.trim(),
        'companionCode': _companionCodeC.text.trim(),

        // ===== Campos del modal que ya existían =====
        'category': _category, // Tema de conversación
        'tone': _tone, // Estilo de conversación
        // extras (no afectan)
        'photoUrl': widget.photoUrl,
        'bio': widget.bio,

        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (widget.offerId == null) {
        if (widget.createdFromExplore) {
          data['createdFrom'] = 'explore';
          final target = widget.targetCompanionId?.trim() ?? '';
          if (target.isNotEmpty) {
            data['targetCompanionId'] = target;
          }
        }
        data['createdAt'] = FieldValue.serverTimestamp();
        data['status'] = publishStatus; // active o payment_required
        final docRef =
            await FirebaseFirestore.instance.collection('offers').add(data);

        if (!mounted) return;
        Navigator.pop(context, docRef.id);
      } else {
        await FirebaseFirestore.instance
            .collection('offers')
            .doc(widget.offerId)
            .update(data);
        if (!mounted) return;
        Navigator.pop(context, widget.offerId);
      }

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al guardar la oferta: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ============================
  // UI
  // ============================

  // ====== HEADER (sin líneas separadoras) ======
  Widget _buildHeader() {
    final isEditing = widget.offerId != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          isEditing ? 'EDITAR OFERTA' : 'Crear nueva oferta',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Define el tipo de conversación antes de publicarla',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.white70),
        ),
        const SizedBox(height: 12),
        // Divider eliminado (línea separadora)
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxH = media.size.height * 0.85;
    final maxW = media.size.width * 0.92;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH, maxWidth: maxW),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.16),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white24),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 16,
                  offset: Offset(0, 8),
                  color: Colors.black26,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(),
                const SizedBox(height: 10),

                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildTypeRow(),
                        const SizedBox(height: 10),

                        _buildTopicStyleRow(),
                        const SizedBox(height: 10),

                        _buildDurationAmountRow(),
                        if (_showAutoAmountHint) ...[
                          const SizedBox(height: 6),
                          const Text(
                            'Monto ajustado automáticamente',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),

                        _buildDescription(),
                        const SizedBox(height: 10),

                        _buildCompanionCode(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _buildActions(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Tipo de comunicación (horizontal)
  Widget _buildTypeRow() {
    Widget item(String v, IconData icon, String label) {
      final selected = _type == v;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _saving
              ? null
              : () {
                  setState(() {
                    _type = v;
                    _recalculateAmount(showHint: true);
                  });
                },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? Colors.white24 : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(icon, color: Colors.white),
                const SizedBox(height: 4),
                Text(label, style: const TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        item('chat', Icons.chat_bubble_outline, 'Chat'),
        const SizedBox(width: 8),
        item('voice', Icons.call_outlined, 'Llamada'),
        const SizedBox(width: 8),
        item('video', Icons.videocam_outlined, 'Video'),
      ],
    );
  }

  // Tema + estilo (dropdowns existentes)
  Widget _buildTopicStyleRow() {
    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 420;

        final categoryField = DropdownButtonFormField<String>(
          value: _category,
          isExpanded: true,
          items: const [
            DropdownMenuItem(
              value: 'vida_diaria',
              child: Text('Vida diaria 🏠'),
            ),
            DropdownMenuItem(
              value: 'relaciones_familia',
              child: Text('Relaciones y familia ❤️'),
            ),
            DropdownMenuItem(
              value: 'trabajo_dinero',
              child: Text('Trabajo y dinero 💼'),
            ),
            DropdownMenuItem(
              value: 'estudios_futuro',
              child: Text('Estudios y futuro 📚'),
            ),
            DropdownMenuItem(
              value: 'metas_proyectos',
              child: Text('Metas y proyectos 🎯'),
            ),
            DropdownMenuItem(
              value: 'hobbies_entretenimiento',
              child: Text('Hobbies y entretenimiento 🎮'),
            ),
          ],
          onChanged: _saving
              ? null
              : (v) => setState(() => _category = v ?? _category),
          decoration: InputDecoration(
            labelText: 'Tema de conversación',
            isDense: true,
            errorText: _categoryError,
          ),
        );

        final toneField = DropdownButtonFormField<String>(
          value: _tone,
          isExpanded: true,
          items: const [
            DropdownMenuItem(
              value: 'relajada_cercana',
              child: Text('Relajada y cercana 😌'),
            ),
            DropdownMenuItem(
              value: 'directa',
              child: Text('Directa y sin rodeos ⚡'),
            ),
            DropdownMenuItem(
              value: 'motivadora',
              child: Text('Motivadora / impulsora 🚀'),
            ),
            DropdownMenuItem(
              value: 'escucha_tranquila',
              child: Text('Escucha tranquila 👂'),
            ),
            DropdownMenuItem(
              value: 'analitica',
              child: Text('Analítica / estructurada 🧠'),
            ),
            DropdownMenuItem(
              value: 'humor_ligero',
              child: Text('Con humor ligero 😄'),
            ),
          ],
          onChanged: _saving ? null : (v) => setState(() => _tone = v ?? _tone),
          decoration: InputDecoration(
            labelText: 'Estilo de conversación',
            isDense: true,
            errorText: _toneError,
          ),
        );

        if (narrow) {
          return Column(
            children: [categoryField, const SizedBox(height: 10), toneField],
          );
        }

        return Row(
          children: [
            Expanded(child: categoryField),
            const SizedBox(width: 10),
            Expanded(child: toneField),
          ],
        );
      },
    );
  }

  // Duración + monto
  Widget _buildDurationAmountRow() {
    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 420;

        final durationField = DropdownButtonFormField<int>(
          value: _durationMinutes,
          isExpanded: true,
          items: const [
            DropdownMenuItem(value: 15, child: Text('15 minutos')),
            DropdownMenuItem(value: 30, child: Text('30 minutos')),
            DropdownMenuItem(value: 45, child: Text('45 minutos')),
            DropdownMenuItem(value: 60, child: Text('60 minutos')),
          ],
          onChanged: _saving
              ? null
              : (v) {
                  if (v == null) return;
                  setState(() {
                    _durationMinutes = v;
                    _recalculateAmount(showHint: true);
                  });
                },
          decoration: InputDecoration(
            labelText: 'Duración',
            isDense: true,
            errorText: _durationError,
          ),
        );

        final amountField = TextField(
          controller: _amountC,
          keyboardType: const TextInputType.numberWithOptions(decimal: false),
          enabled: !_saving,
          onChanged: (_) {
            if (_settingAmountProgrammatically) return;
            if (_showAutoAmountHint) {
              setState(() => _showAutoAmountHint = false);
              _hintTimer?.cancel();
            }
          },
          decoration: InputDecoration(
            labelText: 'Monto (MXN)',
            isDense: true,
            errorText: _amountError,
          ),
        );

        if (narrow) {
          return Column(
            children: [durationField, const SizedBox(height: 10), amountField],
          );
        }

        return Row(
          children: [
            Expanded(child: durationField),
            const SizedBox(width: 10),
            Expanded(child: amountField),
          ],
        );
      },
    );
  }

  // Descripción
  Widget _buildDescription() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        TextField(
          controller: _descC,
          minLines: 2,
          maxLines: 4,
          maxLength: _maxDesc,
          enabled: !_saving,
          decoration: InputDecoration(
            labelText: '¿Qué te gustaría conversar?',
            hintText:
                'Describe brevemente el tema o el tipo de charla que buscas',
            isDense: true,
            errorText: _descError,
          ),
        ),
        TextButton.icon(
          onPressed: _saving
              ? null
              : () {
                  setState(() {
                    _descC.text = _descriptionSuggestions[_suggestionIndex];
                    _suggestionIndex =
                        (_suggestionIndex + 1) % _descriptionSuggestions.length;
                  });
                },
          icon: const Icon(Icons.auto_fix_high, size: 18),
          label: const Text('Sugerencias'),
        ),
      ],
    );
  }

  // Código compañera (tooltip + validación)
  Widget _buildCompanionCode() {
    return TextField(
      controller: _companionCodeC,
      enabled: !_saving,
      decoration: InputDecoration(
        labelText: 'Código de compañera (opcional)',
        isDense: true,
        errorText: _companionCodeError,
        suffixIcon: const Tooltip(
          message:
              'Si usas un código, la oferta será visible solo para esa compañera.',
          child: Icon(Icons.info_outline),
        ),
      ),
    );
  }

  // Acciones: Cancelar / Publicar-Guardar con loader y anti doble tap
  Widget _buildActions() {
    final isEditing = widget.offerId != null;

    return Row(
      children: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, null),
          child: const Text('Cancelar'),
        ),
        const Spacer(),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isEditing ? 'Guardar cambios' : 'Publicar'),
        ),
      ],
    );
  }
}
