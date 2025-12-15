import 'package:flutter/material.dart';
import '../onboarding_ui.dart';

class LocationStep extends StatelessWidget {
  final TextEditingController cityC;
  final TextEditingController countryC;

  final bool locLoading;
  final String? locError;
  final double? geoLat;
  final double? geoLng;

  final VoidCallback onUseLocation;

  const LocationStep({
    super.key,
    required this.cityC,
    required this.countryC,
    required this.locLoading,
    required this.locError,
    required this.geoLat,
    required this.geoLng,
    required this.onUseLocation,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: screenHeight * 0.7),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const OnboardingTitle(
              title: '¿Dónde vives?',
              subtitle: 'Usamos tu ciudad para mostrarte ofertas cercanas.',
            ),
            TextField(
              controller: cityC,
              decoration: const InputDecoration(
                labelText: 'Ciudad',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: countryC,
              decoration: const InputDecoration(
                labelText: 'País',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: locLoading ? null : onUseLocation,
              icon: const Icon(Icons.my_location),
              label: const Text('Usar mi ubicación actual'),
            ),
            const SizedBox(height: 12),
            if (locLoading)
              const Text(
                'Detectando tu ubicación aproximada...',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              )
            else if (locError != null)
              Text(
                locError!,
                style: const TextStyle(fontSize: 12, color: Colors.orangeAccent),
              )
            else if (geoLat != null && geoLng != null)
              const Text(
                'Ubicación aproximada detectada correctamente.',
                style: TextStyle(fontSize: 12, color: Colors.greenAccent),
              )
            else
              const Text(
                'Si das permiso de ubicación, guardaremos solo una posición aproximada '
                'para mejorar las coincidencias, nunca tu dirección exacta.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }
}
