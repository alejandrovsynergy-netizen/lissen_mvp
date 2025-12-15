import 'package:flutter/material.dart';
import '../onboarding_ui.dart';

class TermsStep extends StatelessWidget {
  final bool termsAccepted;
  final ValueChanged<bool> onTermsChanged;

  const TermsStep({
    super.key,
    required this.termsAccepted,
    required this.onTermsChanged,
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
              title: 'Términos y privacidad',
              subtitle: 'Necesitamos tu consentimiento para continuar.',
            ),
            const Text(
              'Al usar Lissen aceptas mantener el respeto en las sesiones y '
              'cumplir con nuestras políticas de uso.',
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              value: termsAccepted,
              onChanged: (v) => onTermsChanged(v ?? false),
              title: const Text(
                'Acepto los términos de servicio y la política de privacidad.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
