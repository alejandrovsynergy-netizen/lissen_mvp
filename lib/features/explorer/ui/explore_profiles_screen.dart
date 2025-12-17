import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'public_profile_screen.dart'; // PublicProfileBody

class ExploreProfilesScreen extends StatelessWidget {
  const ExploreProfilesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const Scaffold(
        body: SafeArea(
          child: Center(child: Text('Debes iniciar sesión.')),
        ),
      );
    }

    final myUid = currentUser.uid;

    final myUserDocStream =
        FirebaseFirestore.instance.collection('users').doc(myUid).snapshots();

    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: myUserDocStream,
          builder: (context, meSnap) {
            if (meSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (meSnap.hasError || !meSnap.hasData || !meSnap.data!.exists) {
              return const Center(child: Text('Error cargando tu perfil.'));
            }

            final me = meSnap.data!.data() ?? {};
            final myRole = (me['role'] as String?) ?? 'speaker';
            final targetRole = (myRole == 'speaker') ? 'companion' : 'speaker';

            final double? myLat = _asDouble(me['geoLat']);
            final double? myLng = _asDouble(me['geoLng']);
            final bool hasMyGeo = myLat != null && myLng != null;

            final usersStream = FirebaseFirestore.instance
                .collection('users')
                .where('onboardingCompleted', isEqualTo: true)
                .where('role', isEqualTo: targetRole)
                .snapshots();

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: usersStream,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs =
                    snapshot.data!.docs.where((d) => d.id != myUid).toList();

                List<QueryDocumentSnapshot<Map<String, dynamic>>> orderedDocs;

                if (hasMyGeo) {
                  final withGeo = <_DocWithDist>[];
                  final withoutGeo = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

                  for (final d in docs) {
                    final data = d.data();
                    final lat = _asDouble(data['geoLat']);
                    final lng = _asDouble(data['geoLng']);

                    if (lat == null || lng == null) {
                      withoutGeo.add(d);
                      continue;
                    }

                    final distKm = _haversineKm(myLat!, myLng!, lat, lng);
                    withGeo.add(_DocWithDist(doc: d, distKm: distKm));
                  }

                  withGeo.sort((a, b) => a.distKm.compareTo(b.distKm));
                  orderedDocs = [
                    ...withGeo.map((e) => e.doc),
                    ...withoutGeo,
                  ];
                } else {
                  orderedDocs = docs;
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                      child: Text(
                        'Perfiles',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),

                    if (!hasMyGeo)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Activa ubicación para ordenar perfiles por cercanía.',
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.location_on_outlined),
                              onPressed: () async {
                                final ok = await _requestAndSaveLocation(myUid);
                                if (!ok && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Permiso de ubicación no concedido.',
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ),

                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        itemCount: orderedDocs.length,
                        itemBuilder: (context, index) {
                          final doc = orderedDocs[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: PublicProfileBody(
                              userId: doc.id,
                              data: doc.data(),
                              showCloseButton: false,
                              onClose: null,
                              onMakeOffer: null,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  static Future<bool> _requestAndSaveLocation(String uid) async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return false;
    }

    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.low,
    );

    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'geoLat': pos.latitude,
      'geoLng': pos.longitude,
    }, SetOptions(merge: true));

    return true;
  }

  static double? _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return null;
  }

  static double _haversineKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const r = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  static double _deg2rad(double deg) => deg * (math.pi / 180.0);
}

class _DocWithDist {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final double distKm;

  _DocWithDist({required this.doc, required this.distKm});
}
