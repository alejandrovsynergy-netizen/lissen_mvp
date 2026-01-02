import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../onboarding_ui.dart';

class BasicInfoStep extends StatefulWidget {
  final TextEditingController aliasC;
  final TextEditingController ageC;
  final TextEditingController phoneC;
  final TextEditingController bioC;

  final String? role;
  final String? photoUrl;
  final Uint8List? photoBytes;
  final bool uploadingPhoto;
  final VoidCallback onPickPhoto;

  const BasicInfoStep({
    super.key,
    required this.aliasC,
    required this.ageC,
    required this.phoneC,
    required this.bioC,
    required this.role,
    required this.photoUrl,
    required this.photoBytes,
    required this.uploadingPhoto,
    required this.onPickPhoto,
  });

  @override
  State<BasicInfoStep> createState() => _BasicInfoStepState();
}

class _BasicInfoStepState extends State<BasicInfoStep> {
  final List<String> _speakerBioSuggestions = [
    'Busco conversaciones directas y con contenido; me interesa aprender de otras perspectivas.',
    'Me gusta hablar con calma y claridad; prefiero conversaciones sin drama.',
    'Puedo hablar de decisiones, trabajo o relaciones; lo importante es que tenga sentido.',
    'Valoro la honestidad y el respeto; si quieres hablar claro, aqui estoy.',
    'Quiero ordenar ideas y escuchar un punto de vista diferente.',
    'Me interesa la gente real y la charla util, no las apariencias.',
  ];

  final List<String> _companionBioSuggestions = [
    'Ofrezco un espacio tranquilo para conversar sin juicios.',
    'Escucho con atencion y hablo claro; cuido el respeto y los limites.',
    'Me adapto al tono: seria, relajada o ligera segun lo que necesites.',
    'Podemos hablar de metas, relaciones o lo que traigas en mente.',
    'Si necesitas desahogarte o aclarar ideas, aqui tienes un lugar seguro.',
    'Me gusta que la charla sea sincera y deje algo bueno.',
  ];

  int _bioSuggestionIndex = -1;

  List<String> get _activeSuggestions {
    return widget.role == 'companion'
        ? _companionBioSuggestions
        : _speakerBioSuggestions;
  }

  @override
  void didUpdateWidget(covariant BasicInfoStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.role != widget.role) {
      _bioSuggestionIndex = -1;
    }
  }

  void _applyNextBioSuggestion() {
    final list = _activeSuggestions;
    if (list.isEmpty) return;

    setState(() {
      _bioSuggestionIndex = (_bioSuggestionIndex + 1) % list.length;
      final suggestion = list[_bioSuggestionIndex];

      widget.bioC.text = suggestion;
      widget.bioC.selection = TextSelection.fromPosition(
        TextPosition(offset: widget.bioC.text.length),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    ImageProvider? img;
    if (widget.photoBytes != null) {
      img = MemoryImage(widget.photoBytes!);
    }
    if (img == null && widget.photoUrl != null && widget.photoUrl!.isNotEmpty) {
      img = NetworkImage(widget.photoUrl!);
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
              subtitle: 'Foto, alias y algunos datos basicos.',
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
                      if (widget.uploadingPhoto)
                        const SizedBox(
                          height: 120,
                          width: 120,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Agrega una foto clara y agradable. Es obligatorio para generar confianza.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed:
                        widget.uploadingPhoto ? null : widget.onPickPhoto,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Elegir foto de perfil'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: widget.aliasC,
              decoration: const InputDecoration(
                labelText: 'Alias o apodo',
                helperText: 'Elige un nombre unico y facil de recordar.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: widget.ageC,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Edad',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: widget.phoneC,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Numero de telefono',
                helperText: 'Se usa para seguridad y recuperacion de cuenta.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: widget.bioC,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Biografia',
                helperText: 'Cuentale en pocas palabras a la otra persona quien eres.',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _applyNextBioSuggestion,
                icon: const Icon(Icons.auto_fix_high, size: 18),
                label: const Text('Sugerencias'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
