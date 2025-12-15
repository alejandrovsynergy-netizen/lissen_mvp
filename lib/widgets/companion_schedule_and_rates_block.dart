import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CompanionScheduleAndRatesBlock extends StatefulWidget {
  const CompanionScheduleAndRatesBlock({Key? key}) : super(key: key);

  @override
  State<CompanionScheduleAndRatesBlock> createState() =>
      _CompanionScheduleAndRatesBlockState();
}

class _CompanionScheduleAndRatesBlockState
    extends State<CompanionScheduleAndRatesBlock> {
  bool _loading = true;
  bool _isCompanion = false;

  // ====== HORARIO ======
  int _startDayIndex = 1; // 1 = Lunes
  int _endDayIndex = 5; // 5 = Viernes
  TimeOfDay _startTime = const TimeOfDay(hour: 18, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 23, minute: 0);

  final List<String> _days = const [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];

  @override
  void initState() {
    super.initState();
    _loadRoleAndData();
  }

  // ====== HELPERS ======

  String _dayNameFromIndex(int index) {
    if (index < 1 || index > 7) return 'Lunes';
    return _days[index - 1];
  }

  int _indexFromDayName(String name) {
    final idx = _days.indexOf(name);
    if (idx == -1) return 1;
    return idx + 1; // 1–7
  }

  String _formatTime(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  TimeOfDay _parseTime(String? value) {
    if (value == null || !value.contains(':')) {
      return const TimeOfDay(hour: 18, minute: 0);
    }
    final parts = value.split(':');
    final h = int.tryParse(parts[0]) ?? 18;
    final m = int.tryParse(parts[1]) ?? 0;
    return TimeOfDay(hour: h, minute: m);
  }

  // ====== CARGA INICIAL ======

  Future<void> _loadRoleAndData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _loading = false;
          _isCompanion = false;
        });
        return;
      }

      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);
      final doc = await docRef.get();
      final data = doc.data() ?? {};
      final role = data['role'];

      if (role != 'companion') {
        setState(() {
          _loading = false;
          _isCompanion = false;
        });
        return;
      }

      // HORARIO
      int startDay = (data['availabilityStartDay'] as int?) ?? 1;
      int endDay = (data['availabilityEndDay'] as int?) ?? 5;
      final String? startTimeStr = data['availabilityStartTime'] as String?;
      final String? endTimeStr = data['availabilityEndTime'] as String?;
      final TimeOfDay startTime = _parseTime(startTimeStr);
      final TimeOfDay endTime = _parseTime(endTimeStr);

      setState(() {
        _isCompanion = true;
        _startDayIndex = startDay;
        _endDayIndex = endDay;
        _startTime = startTime;
        _endTime = endTime;
        _loading = false;
      });

      // Escribir campos faltantes una sola vez (solo disponibilidad)
      final Map<String, Object?> toSet = {};
      if (!data.containsKey('availabilityStartDay')) {
        toSet['availabilityStartDay'] = startDay;
      }
      if (!data.containsKey('availabilityEndDay')) {
        toSet['availabilityEndDay'] = endDay;
      }
      if (!data.containsKey('availabilityStartTime')) {
        toSet['availabilityStartTime'] = _formatTime(startTime);
      }
      if (!data.containsKey('availabilityEndTime')) {
        toSet['availabilityEndTime'] = _formatTime(endTime);
      }
      if (toSet.isNotEmpty) {
        await docRef.update(toSet);
      }
    } catch (_) {
      setState(() {
        _loading = false;
        _isCompanion = false;
      });
    }
  }

  // ====== GUARDAR DISPONIBILIDAD ======

  Future<void> _saveAvailability() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'availabilityStartDay': _startDayIndex,
      'availabilityEndDay': _endDayIndex,
      'availabilityStartTime': _formatTime(_startTime),
      'availabilityEndTime': _formatTime(_endTime),
    });
  }

  // ====== PICKERS HORAS ======

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (picked != null) {
      setState(() => _startTime = picked);
      await _saveAvailability();
    }
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
    );
    if (picked != null) {
      setState(() => _endTime = picked);
      await _saveAvailability();
    }
  }

  // ====== BUILD ======

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
              'Disponibilidad',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // DÍAS
            Row(
              children: [
                const Text('De:'),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _dayNameFromIndex(_startDayIndex),
                  items: _days
                      .map(
                        (day) => DropdownMenuItem(value: day, child: Text(day)),
                      )
                      .toList(),
                  onChanged: (value) async {
                    if (value != null) {
                      setState(() => _startDayIndex = _indexFromDayName(value));
                      await _saveAvailability();
                    }
                  },
                ),
                const SizedBox(width: 24),
                const Text('A:'),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _dayNameFromIndex(_endDayIndex),
                  items: _days
                      .map(
                        (day) => DropdownMenuItem(value: day, child: Text(day)),
                      )
                      .toList(),
                  onChanged: (value) async {
                    if (value != null) {
                      setState(() => _endDayIndex = _indexFromDayName(value));
                      await _saveAvailability();
                    }
                  },
                ),
              ],
            ),

            const SizedBox(height: 16),

            // HORAS
            Row(
              children: [
                const Text('Hora inicio:'),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _pickStartTime,
                  child: Text(_startTime.format(context)),
                ),
                const SizedBox(width: 24),
                const Text('Hora fin:'),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _pickEndTime,
                  child: Text(_endTime.format(context)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
