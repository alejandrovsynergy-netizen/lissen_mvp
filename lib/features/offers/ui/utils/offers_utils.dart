import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

double distanceKm(double lat1, double lon1, double lat2, double lon2) {
  const double R = 6371.0;
  final dLat = (lat2 - lat1) * (3.1415926535897932 / 180.0);
  final dLon = (lon2 - lon1) * (3.1415926535897932 / 180.0);

  final a =
      (sin(dLat / 2) * sin(dLat / 2)) +
      cos(lat1 * (3.1415926535897932 / 180.0)) *
          cos(lat2 * (3.1415926535897932 / 180.0)) *
          (sin(dLon / 2) * sin(dLon / 2));

  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return R * c;
}

int createdAtMs(Map<String, dynamic> data) {
  final createdAt = data['createdAt'];
  if (createdAt is Timestamp) return createdAt.millisecondsSinceEpoch;

  final updatedAt = data['updatedAt'];
  if (updatedAt is Timestamp) return updatedAt.millisecondsSinceEpoch;

  return 0;
}

int priceCents(Map<String, dynamic> data) {
  final v = data['priceCents'] ?? data['totalMinAmountCents'] ?? 0;
  if (v is num) return v.toInt();
  return 0;
}
