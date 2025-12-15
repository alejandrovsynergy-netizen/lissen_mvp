import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../onboarding_ui.dart';

class BasicInfoStep extends StatelessWidget {
  final TextEditingController aliasC;
  final TextEditingController ageC;
  final TextEditingController bioC;

  final String? photoUrl;
  final Uint8List? photoBytes;
  final bool uploadingPhoto;
  final VoidCallback onPickPhoto;

  const BasicInfoStep({
    super.key,
    required this.aliasC,
    required this.ageC,
    required this.bioC,
    required this.photoUrl,
    required this.photoBytes,
    required this.uploadingPhoto,
    required this.onPickPhoto,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    ImageProvider? img;
    if (photoBytes != null) img = MemoryImage(photoBytes!);
    if (img == null && photoUrl != null && photoUrl!.isNotEmpty) {
      img = NetworkImage(photoUrl!);
    }

    return SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: screenHeight * 0.7),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const OnboardingTitle(
              title: 'Tu perfil',
              subtitle: 'Foto, alias y algunos datos básicos.',
            ),
            Center(
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      CircleAvatar(
                        radius: 60,
                        backgroundImage: img,
                        child: (img == null)
                            ? const Icon(Icons.person, size: 52)
                            : null,
                      ),
                      if (uploadingPhoto)
                        const SizedBox(
                          height: 120,
                          width: 120,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Añade una foto clara y agradable. Es obligatorio para generar confianza.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: uploadingPhoto ? null : onPickPhoto,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Elegir foto de perfil'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: aliasC,
              decoration: const InputDecoration(
                labelText: 'Alias o apodo',
                helperText: 'Elige un nombre único y fácil de recordar.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ageC,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Edad',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: bioC,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Biografía (opcional)',
                helperText: 'Cuéntale en pocas palabras a la otra persona quién eres.',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
