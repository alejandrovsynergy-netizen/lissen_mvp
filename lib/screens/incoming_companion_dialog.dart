import 'package:flutter/material.dart';
import '../features/explorer/ui/public_profile_screen.dart';

/// Muestra el modal de decisión cuando una compañera quiere tomar la oferta.
/// Devuelve:
///   true  -> usuario tocó "Aceptar compañera"
///   false -> usuario tocó "Rechazar"
///   null  -> si el diálogo se cierra de otra forma (no debería pasar)
Future<bool?> showIncomingCompanionDialog({
  required BuildContext context,
  required String companionAlias,
  required int durationMinutes,
  required double amountUsd,
  required String currency,
  required String communicationType, // chat | voice | video
  // Datos opcionales para foto + perfil público
  String? companionPhotoUrl,
  String? companionUid,
}) {
  String _communicationLabel(String type) {
    switch (type) {
      case 'voice':
        return 'Llamada de voz';
      case 'video':
        return 'Videollamada';
      case 'chat':
      default:
        return 'Chat';
    }
  }

  return showDialog<bool>(
    context: context,
    barrierDismissible: false, // no cerrar tocando fuera
    builder: (dialogContext) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Una compañera quiere tomar tu oferta',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                GestureDetector(
                  onTap: () {
                    // Abrir perfil público SOLO si tenemos uid válido
                    if (companionUid != null && companionUid!.isNotEmpty) {
                      Navigator.of(dialogContext, rootNavigator: true).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              PublicProfileScreen(companionUid: companionUid!),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'No se pudo abrir el perfil, UID de compañera vacío.',
                          ),
                        ),
                      );
                    }
                  },
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundImage:
                            (companionPhotoUrl != null &&
                                companionPhotoUrl.isNotEmpty)
                            ? NetworkImage(companionPhotoUrl!)
                            : null,
                        child:
                            (companionPhotoUrl == null ||
                                companionPhotoUrl.isEmpty)
                            ? const Icon(Icons.person, size: 32)
                            : null,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Ver perfil público',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blueAccent,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    companionAlias,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _communicationLabel(communicationType),
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              'Duración: $durationMinutes min',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              'Monto: $currency ${amountUsd.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(false); // Rechazar
            },
            child: const Text(
              'Rechazar',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(true); // Aceptar
            },
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Aceptar compañera',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      );
    },
  );
}
