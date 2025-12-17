import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Clipboard
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../widgets/companion_rates_block.dart';

class CompanionConfigScreen extends StatefulWidget {
  final String uid;
  final bool isCompanion;

  const CompanionConfigScreen({
    super.key,
    required this.uid,
    required this.isCompanion,
  });

  @override
  State<CompanionConfigScreen> createState() => _CompanionConfigScreenState();
}

class _CompanionConfigScreenState extends State<CompanionConfigScreen> {
  List<int> _selectedDays = [];
  int _startHour = 18;
  int _endHour = 22;
  bool _availabilityInitialized = false;
  bool _savingAvailability = false;

  bool _savingRates = false;

  Future<void> _saveAvailability() async {
    setState(() {
      _savingAvailability = true;
    });

    try {
      await FirebaseFirestore.instance.collection('users').doc(widget.uid).set({
        'availabilityDays': _selectedDays,
        'availabilityStartHour': _startHour,
        'availabilityEndHour': _endHour,
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Disponibilidad actualizada.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error guardando disponibilidad: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _savingAvailability = false;
      });
    }
  }

  /// Marca las tarifas como confirmadas por la compañera.
  Future<void> _saveRates() async {
    setState(() {
      _savingRates = true;
    });

    try {
      await FirebaseFirestore.instance.collection('users').doc(widget.uid).set({
        'ratesLastConfirmedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tarifas guardadas y confirmadas.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error guardando tarifas: $e')));
    } finally {
      if (!mounted) return;
      setState(() {
        _savingRates = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isCompanion) {
      return Scaffold(
        appBar: AppBar(title: const Text('Configuración')),
        body: const Center(
          child: Text(
            'Configuración avanzada disponible solo para cuentas de compañera.',
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(widget.uid)
            .snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snap.data!.data() ?? {};
          final companionCode = (data['companionCode'] as String?)?.trim() ?? '';

          if (!_availabilityInitialized) {
            final days = (data['availabilityDays'] as List<dynamic>?) ?? [];
            _selectedDays = days.map((e) => e as int).toList();
            _startHour = data['availabilityStartHour'] ?? 18;
            _endHour = data['availabilityEndHour'] ?? 22;
            _availabilityInitialized = true;
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // CÓDIGO DE COMPAÑERA
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Código de compañera',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Comparte este código con hablantes para que sus ofertas '
                          'sean dirigidas solo a ti.',
                          style: TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  color: Colors.grey.shade900,
                                ),
                                child: Text(
                                  companionCode.isEmpty
                                      ? 'Generando código...'
                                      : companionCode,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    letterSpacing: 1.2,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: companionCode.isEmpty
                                  ? null
                                  : () async {
                                      await Clipboard.setData(
                                        ClipboardData(text: companionCode),
                                      );
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Código copiado.'),
                                        ),
                                      );
                                    },
                              icon: const Icon(Icons.copy),
                              tooltip: 'Copiar código',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // DISPONIBILIDAD
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Disponibilidad típica',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Selecciona los días y el rango de horas en que sueles estar disponible.',
                          style: TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: List.generate(7, (index) {
                            final dayNumber = index + 1;
                            final labels = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
                            final isSelected = _selectedDays.contains(dayNumber);

                            return ChoiceChip(
                              label: Text(labels[index]),
                              selected: isSelected,
                              onSelected: (val) {
                                setState(() {
                                  if (val) {
                                    _selectedDays.add(dayNumber);
                                  } else {
                                    _selectedDays.remove(dayNumber);
                                  }
                                });
                              },
                            );
                          }),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Text('Desde'),
                            const SizedBox(width: 8),
                            DropdownButton<int>(
                              value: _startHour,
                              items: List.generate(24, (i) {
                                return DropdownMenuItem(
                                  value: i,
                                  child: Text('$i:00'),
                                );
                              }),
                              onChanged: (val) {
                                if (val == null) return;
                                setState(() {
                                  _startHour = val;
                                });
                              },
                            ),
                            const SizedBox(width: 16),
                            const Text('Hasta'),
                            const SizedBox(width: 8),
                            DropdownButton<int>(
                              value: _endHour,
                              items: List.generate(24, (i) {
                                return DropdownMenuItem(
                                  value: i,
                                  child: Text('$i:00'),
                                );
                              }),
                              onChanged: (val) {
                                if (val == null) return;
                                setState(() {
                                  _endHour = val;
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton.icon(
                            onPressed:
                                _savingAvailability ? null : _saveAvailability,
                            icon: _savingAvailability
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save, size: 16),
                            label: Text(
                              _savingAvailability
                                  ? 'Guardando...'
                                  : 'Guardar disponibilidad',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // TARIFAS BASE + BOTÓN GUARDAR
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tarifas base',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Ajusta tus tarifas y presiona "Guardar tarifas" para que los cambios cuenten.',
                          style: TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        const CompanionRatesBlock(),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton.icon(
                            onPressed: _savingRates ? null : _saveRates,
                            icon: _savingRates
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save, size: 16),
                            label: Text(
                              _savingRates ? 'Guardando...' : 'Guardar tarifas',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
