import 'package:flutter/material.dart';
import '../onboarding_ui.dart';

class RoleClarificationsStep extends StatelessWidget {
  final String? role;
  final bool accepted;
  final ValueChanged<bool> onAcceptedChanged;

  const RoleClarificationsStep({
    super.key,
    required this.role,
    required this.accepted,
    required this.onAcceptedChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isSpeaker = role == 'speaker';
    final isCompanion = role == 'companion';
    final screenHeight = MediaQuery.of(context).size.height;

    if (!isSpeaker && !isCompanion) {
      return SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: screenHeight * 0.7),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              OnboardingTitle(
                title: 'Antes de continuar',
                subtitle: 'Primero elige si eres hablante o compañera.',
              ),
              Text('Toca "Atrás", selecciona tu rol y luego vuelve a este paso.'),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: screenHeight * 0.7),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OnboardingTitle(
              title: 'Antes de continuar',
              subtitle: isSpeaker
                  ? 'Queremos que tengas claro qué tipo de servicio estás usando.'
                  : 'Queremos que tengas claro qué tipo de servicio estás ofreciendo.',
            ),
            ClarificationCard(
              icon: Icons.favorite_outline,
              title: isSpeaker
                  ? 'Respeto ante todo'
                  : 'Atención y empatía sin ser terapeuta',
              body: isSpeaker
                  ? 'Debes tratar a la otra persona con respeto. No se permiten insultos, acoso, humillaciones ni conductas agresivas.'
                  : 'Ofreces tu atención y conversación casual. Debes mostrar empatía y respeto, pero sin cruzar el límite de lo profesional: no das terapia, diagnósticos ni manejas crisis.',
            ),
            const SizedBox(height: 12),
            const ClarificationCard(
              icon: Icons.no_adult_content,
              title: 'No es un servicio de contenido para adultos',
              body:
                  'Lissen no es una plataforma para servicios sexuales, intercambio de contenido explícito ni citas físicas. Si decides enviar o responder mensajes de cualquier naturaleza, es bajo tu propia responsabilidad.',
            ),
            const SizedBox(height: 12),
            ClarificationCard(
              icon: Icons.shield_outlined,
              title: isSpeaker
                  ? 'Eres responsable de lo que envías'
                  : 'Eres responsable de lo que dices y aceptas',
              body: isSpeaker
                  ? 'Los mensajes, fotos o audios que envíes son totalmente tu responsabilidad. La otra persona puede decidir cómo responder o si termina la conversación.'
                  : 'Las respuestas, comentarios o contenido que compartas son tu responsabilidad. Puedes decidir hasta dónde participar y tienes derecho a terminar la conversación si algo te incomoda.',
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              value: accepted,
              onChanged: (v) => onAcceptedChanged(v ?? false),
              title: const Text(
                'Entiendo y acepto estas aclaraciones sobre mi rol en Lissen.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
