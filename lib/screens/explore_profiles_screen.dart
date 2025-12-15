import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'public_profile_screen.dart'; // PublicProfileBody

class ExploreProfilesScreen extends StatelessWidget {
  const ExploreProfilesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Explorar'), centerTitle: true),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snapshot) {
          // Error
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error cargando usuarios: ${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            );
          }

          // Cargando
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // Sin datos
          if (!snapshot.hasData) {
            return const Center(
              child: Text('No hay datos en la colección users.'),
            );
          }

          final docs = snapshot.data!.docs;

          // Sin documentos
          if (docs.isEmpty) {
            return const Center(
              child: Text('No hay ningún usuario para mostrar.'),
            );
          }

          // FEED CONTINUO: un solo ListView, cada item es un PublicProfileBody
          return ListView.builder(
            padding: const EdgeInsets.only(top: 8, bottom: 16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data();

              return Padding(
                padding: const EdgeInsets.only(left: 8, right: 8, bottom: 12),
                child: PublicProfileBody(
                  data: data,
                  showCloseButton: false,
                  onClose: null,
                  onMakeOffer: null,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
