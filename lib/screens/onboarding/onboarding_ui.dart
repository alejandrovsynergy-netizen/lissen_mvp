import 'package:flutter/material.dart';

class OnboardingStepIndicator extends StatelessWidget {
  final int current;
  final int total;

  const OnboardingStepIndicator({
    super.key,
    required this.current,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final selected = i == current;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: selected ? 16 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: selected ? Colors.tealAccent : Colors.grey[700],
            borderRadius: BorderRadius.circular(20),
          ),
        );
      }),
    );
  }
}

class OnboardingTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const OnboardingTitle({
    super.key,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Text(
          title,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.grey[400])),
        const SizedBox(height: 24),
      ],
    );
  }
}

class ClarificationCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const ClarificationCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 26),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}

class RoleCard extends StatelessWidget {
  final bool selected;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const RoleCard({
    super.key,
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? Colors.white10 : Colors.black26,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? Colors.tealAccent : Colors.white10,
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 32, color: Colors.tealAccent),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, color: Colors.tealAccent),
          ],
        ),
      ),
    );
  }
}
