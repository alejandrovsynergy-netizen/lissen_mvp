import 'package:flutter/material.dart';

/// Muestra un modal de resumen + rating.
/// NO toca Firestore, solo devuelve el rating seleccionado (o null si cierra).
Future<int?> showSessionSummaryDialog({
  required BuildContext context,
  required String myRoleLabel, // "Hablante" o "Compañera"
  required String speakerAlias, // alias del hablante
  required String companionAlias, // alias de la compañera
  required int reservedMinutes, // minutos reservados
  required int realMinutes, // minutos reales
  required int billingMinutes, // minutos cobrados
  required String endedByLabel, // "Hablante", "Compañera", "Por tiempo"
  required double price, // monto total
  required String currency, // "USD", "MXN", etc.
}) async {
  int selectedRating = 0;

  return showDialog<int>(
    context: context,
    barrierDismissible: false, // 👈 NO se cierra tocando afuera
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text('Resumen de la sesión'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tú participaste como: $myRoleLabel',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Text('Hablante: $speakerAlias'),
                  Text('Compañera: $companionAlias'),
                  const SizedBox(height: 8),
                  Text('Reservaste: $reservedMinutes min'),
                  Text('Duración real: $realMinutes min'),
                  Text('Minutos cobrados: $billingMinutes min'),
                  Text('Terminó: $endedByLabel'),
                  const SizedBox(height: 8),
                  Text(
                    'Monto total: \$${price.toStringAsFixed(2)} $currency',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Califica tu experiencia',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      final starValue = index + 1;
                      final filled = starValue <= selectedRating;
                      return IconButton(
                        icon: Icon(
                          filled ? Icons.star : Icons.star_border,
                          color: filled ? Colors.amber : Colors.grey,
                        ),
                        onPressed: () {
                          setStateDialog(() {
                            selectedRating = starValue;
                          });
                        },
                      );
                    }),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop(null);
                },
                child: const Text('Ahora no'),
              ),
              ElevatedButton(
                onPressed: selectedRating == 0
                    ? null
                    : () {
                        Navigator.of(dialogContext).pop(selectedRating);
                      },
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      );
    },
  );
}
