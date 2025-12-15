import 'package:flutter/material.dart';
import '../onboarding_ui.dart';

class GenderPrefsStep extends StatelessWidget {
  final String? gender;
  final String? preferredGender;
  final ValueChanged<String> onGenderChanged;
  final ValueChanged<String> onPreferredGenderChanged;

  const GenderPrefsStep({
    super.key,
    required this.gender,
    required this.preferredGender,
    required this.onGenderChanged,
    required this.onPreferredGenderChanged,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    Widget genderOption(String value, String label) {
      final selected = gender == value;
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Radio<String>(
          value: value,
          groupValue: gender,
          onChanged: (v) => onGenderChanged(v!),
        ),
        title: Text(label),
        trailing: selected ? const Icon(Icons.check, color: Colors.tealAccent) : null,
        onTap: () => onGenderChanged(value),
      );
    }

    Widget prefOption(String value, String label) {
      final selected = preferredGender == value;
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Radio<String>(
          value: value,
          groupValue: preferredGender,
          onChanged: (v) => onPreferredGenderChanged(v!),
        ),
        title: Text(label),
        trailing: selected ? const Icon(Icons.check, color: Colors.tealAccent) : null,
        onTap: () => onPreferredGenderChanged(value),
      );
    }

    return SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: screenHeight * 0.7),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const OnboardingTitle(
              title: 'Tu género y tus preferencias',
              subtitle: 'Esto se usará para filtrar ofertas y mejorar las coincidencias.',
            ),
            const Text('Tu género', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            genderOption('hombre', 'Hombre'),
            genderOption('mujer', 'Mujer'),
            genderOption('otro', 'No binario / Otro'),
            genderOption('nsnc', 'Prefiero no decir'),
            const SizedBox(height: 20),
            const Text('¿Con qué género deseas interactuar?', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            prefOption('todos', 'Sin preferencia'),
            prefOption('hombres', 'Hombres'),
            prefOption('mujeres', 'Mujeres'),
            prefOption('nobinario', 'Personas no binarias'),
          ],
        ),
      ),
    );
  }
}
