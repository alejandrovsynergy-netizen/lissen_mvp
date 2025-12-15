import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

typedef RateChanged = Future<void> Function(int);

class CompanionRatesBlock extends StatefulWidget {
  const CompanionRatesBlock({Key? key}) : super(key: key);

  @override
  State<CompanionRatesBlock> createState() => _CompanionRatesBlockState();
}

class _CompanionRatesBlockState extends State<CompanionRatesBlock> {
  bool _loading = true;
  bool _isCompanion = false;

  // mínimos en centavos MXN
  static const int kChat15MinCents = 7000; // $70
  static const int kVoice15MinCents = 10500; // $105
  static const int kVideo15MinCents = 15500; // $155
  static const int kStepCents = 500; // $5 por clic

  int _rateChat15Cents = kChat15MinCents;
  int _rateVoice15Cents = kVoice15MinCents;
  int _rateVideo15Cents = kVideo15MinCents;

  @override
  void initState() {
    super.initState();
    _loadRates();
  }

  String _formatMoney(int cents) {
    final pesos = cents ~/ 100;
    final rest = cents % 100;
    if (rest == 0) return '\$$pesos MXN';
    return '\$$pesos.${rest.toString().padLeft(2, '0')} MXN';
  }

  /// Aplica piso y techo (4× piso) a la tarifa.
  int _clampRate(int valueCents, int minCents) {
    final int maxCents = minCents * 4;
    if (valueCents < minCents) return minCents;
    if (valueCents > maxCents) return maxCents;
    return valueCents;
  }

  Future<void> _loadRates() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _loading = false;
          _isCompanion = false;
        });
        return;
      }

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data() ?? {};
      final role = data['role'];

      if (role != 'companion') {
        setState(() {
          _loading = false;
          _isCompanion = false;
        });
        return;
      }

      // Cargar y CLAMP a [min, 4×min]
      _rateChat15Cents = _clampRate(
        (data['rateChat15Cents'] as int?) ?? kChat15MinCents,
        kChat15MinCents,
      );
      _rateVoice15Cents = _clampRate(
        (data['rateVoice15Cents'] as int?) ?? kVoice15MinCents,
        kVoice15MinCents,
      );
      _rateVideo15Cents = _clampRate(
        (data['rateVideo15Cents'] as int?) ?? kVideo15MinCents,
        kVideo15MinCents,
      );

      // si faltan campos o están fuera del rango, los escribimos normalizados
      final Map<String, Object?> toSet = {};
      if (!data.containsKey('rateChat15Cents') ||
          data['rateChat15Cents'] != _rateChat15Cents) {
        toSet['rateChat15Cents'] = _rateChat15Cents;
      }
      if (!data.containsKey('rateVoice15Cents') ||
          data['rateVoice15Cents'] != _rateVoice15Cents) {
        toSet['rateVoice15Cents'] = _rateVoice15Cents;
      }
      if (!data.containsKey('rateVideo15Cents') ||
          data['rateVideo15Cents'] != _rateVideo15Cents) {
        toSet['rateVideo15Cents'] = _rateVideo15Cents;
      }
      if (toSet.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update(toSet);
      }

      setState(() {
        _isCompanion = true;
        _loading = false;
      });
    } catch (e) {
      // Si hay error, no rompemos la app, solo ocultamos el bloque
      if (mounted) {
        setState(() {
          _loading = false;
          _isCompanion = false;
        });
      }
    }
  }

  Future<void> _saveRates() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
            'rateChat15Cents': _rateChat15Cents,
            'rateVoice15Cents': _rateVoice15Cents,
            'rateVideo15Cents': _rateVideo15Cents,
          });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al guardar tarifas: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || !_isCompanion) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tarifas (15 minutos)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildRateRow(
              label: 'Chat',
              currentCents: _rateChat15Cents,
              minCents: kChat15MinCents,
              onChanged: (value) async {
                setState(() => _rateChat15Cents = value);
                await _saveRates();
              },
            ),
            const SizedBox(height: 8),
            _buildRateRow(
              label: 'Llamada',
              currentCents: _rateVoice15Cents,
              minCents: kVoice15MinCents,
              onChanged: (value) async {
                setState(() => _rateVoice15Cents = value);
                await _saveRates();
              },
            ),
            const SizedBox(height: 8),
            _buildRateRow(
              label: 'Video',
              currentCents: _rateVideo15Cents,
              minCents: kVideo15MinCents,
              onChanged: (value) async {
                setState(() => _rateVideo15Cents = value);
                await _saveRates();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRateRow({
    required String label,
    required int currentCents,
    required int minCents,
    required RateChanged onChanged,
  }) {
    final int maxCents = minCents * 4;

    return Row(
      children: [
        Expanded(
          child: Text('$label (15 min)', style: const TextStyle(fontSize: 16)),
        ),
        IconButton(
          onPressed: currentCents > minCents
              ? () async {
                  final newValue = _clampRate(
                    currentCents - kStepCents,
                    minCents,
                  );
                  await onChanged(newValue);
                }
              : null,
          icon: const Icon(Icons.remove),
        ),
        Text(
          _formatMoney(currentCents),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        IconButton(
          onPressed: currentCents < maxCents
              ? () async {
                  final newValue = _clampRate(
                    currentCents + kStepCents,
                    minCents,
                  );
                  await onChanged(newValue);
                }
              : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}
