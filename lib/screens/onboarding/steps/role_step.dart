import 'package:flutter/material.dart';
import '../onboarding_ui.dart';

class RoleStep extends StatelessWidget {
  final String? role;
  final ValueChanged<String> onRoleSelected;
  final VoidCallback onRoleChangedResetClarifications;

  const RoleStep({
    super.key,
    required this.role,
    required this.onRoleSelected,
    required this.onRoleChangedResetClarifications,
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
              title: '¿Cuál es tu rol?',
              subtitle: 'Selecciona cómo quieres usar la app.',
            ),
            RoleCard(
              selected: role == 'speaker',
              title: 'Hablante',
              subtitle: 'Publicar ofertas y encontrar compañía.',
              icon: Icons.chat_bubble_outline,
              onTap: () {
                onRoleSelected('speaker');
                onRoleChangedResetClarifications();
              },
            ),
            const SizedBox(height: 12),
            RoleCard(
              selected: role == 'companion',
              title: 'Compañera',
              subtitle: 'Ver ofertas y ofrecer compañía.',
              icon: Icons.people_alt_outlined,
              onTap: () {
                onRoleSelected('companion');
                onRoleChangedResetClarifications();
              },
            ),
          ],
        ),
      ),
    );
  }
}
