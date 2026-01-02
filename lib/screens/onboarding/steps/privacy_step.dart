import 'package:flutter/material.dart';
import '../onboarding_ui.dart';
import '../../profile/legal_texts.dart';

class PrivacyStep extends StatelessWidget {
  final bool privacyAccepted;
  final ValueChanged<bool> onPrivacyChanged;

  const PrivacyStep({
    super.key,
    required this.privacyAccepted,
    required this.onPrivacyChanged,
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
              title: 'Aviso de privacidad',
              subtitle: 'Lee y acepta el aviso para continuar.',
            ),
            const Text(
              'Este aviso explica como usamos tus datos.',
            ),
            const SizedBox(height: 16),
            const _LegalSection(
              title: 'Aviso de privacidad',
              text: kPrivacyNoticeText,
            ),
            CheckboxListTile(
              value: privacyAccepted,
              onChanged: (v) => onPrivacyChanged(v ?? false),
              title: const Text(
                'Acepto el Aviso de Privacidad.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegalSection extends StatelessWidget {
  final String title;
  final String text;

  const _LegalSection({
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 200,
            child: SingleChildScrollView(
              child: SelectableText(
                text,
                style: const TextStyle(fontSize: 12, height: 1.35),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
