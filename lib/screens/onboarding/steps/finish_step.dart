import 'package:flutter/material.dart';

class FinishStep extends StatelessWidget {
  final String alias;

  const FinishStep({
    super.key,
    required this.alias,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, size: 64, color: Colors.tealAccent),
          const SizedBox(height: 16),
          const Text(
            'Perfil listo',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            alias.isNotEmpty
                ? 'Bienvenid@, $alias.\nTu onboarding está completo.'
                : 'Tu onboarding está completo.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Al guardar, podrás empezar a usar Lissen para crear ofertas o encontrar compañía.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
