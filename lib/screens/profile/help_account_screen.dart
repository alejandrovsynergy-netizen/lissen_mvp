import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HelpAccountScreen extends StatelessWidget {
  const HelpAccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ayuda y cuenta')),
        body: const Center(
          child: Text(
            'Necesitas iniciar sesión para ver esta sección.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Ayuda y cuenta')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data?.data() ?? {};
          final List<String> blockedUsers =
              (data['blockedUsers'] as List<dynamic>?)
                      ?.map((e) => e.toString())
                      .toList() ??
                  [];

          return ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.block),
                title: const Text('Usuarios bloqueados'),
                subtitle: Text(
                  blockedUsers.isEmpty
                      ? 'No has bloqueado a nadie.'
                      : 'Has bloqueado ${blockedUsers.length} usuario(s).',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              if (blockedUsers.isNotEmpty) const Divider(height: 8),

              if (blockedUsers.isNotEmpty)
                ...blockedUsers.map(
                  (uid) => ListTile(
                    leading: const Icon(Icons.person_off_outlined, size: 20),
                    title: Text(uid, style: const TextStyle(fontSize: 13)),
                    subtitle: const Text(
                      'Bloqueado',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ),

              if (blockedUsers.isNotEmpty) const Divider(height: 8),

              const ListTile(
                leading: Icon(Icons.chat_bubble_outline),
                title: Text('Ayuda y sugerencias'),
                subtitle: Text(
                  'Cuéntanos si tienes problemas o ideas para mejorar Lissen.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const Divider(height: 8),
              const ListTile(
                leading: Icon(Icons.description_outlined),
                title: Text('Términos y condiciones'),
                subtitle: Text(
                  'Lee los términos bajo los cuales funciona Lissen.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const Divider(height: 8),
              const ListTile(
                leading: Icon(Icons.privacy_tip_outlined),
                title: Text('Política de privacidad'),
                subtitle: Text(
                  'Conoce cómo protegemos tu información.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const Divider(height: 8),
              const ListTile(
                leading: Icon(Icons.email_outlined),
                title: Text('Información de contacto'),
                subtitle: Text(
                  'Escríbenos si necesitas soporte más detallado.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const Divider(height: 8),
              const ListTile(
                leading: Icon(Icons.delete_forever_outlined),
                title: Text(
                  'Eliminar cuenta',
                  style: TextStyle(color: Colors.red),
                ),
                subtitle: Text(
                  'Esta opción estará disponible próximamente.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
