import 'package:cloud_firestore/cloud_firestore.dart';

class SessionModel {
  final String id;
  final String speakerId;
  final String speakerAlias;
  final String companionId;
  final String companionAlias;
  final String offerId;
  final String status;
  final int durationMinutes;
  final int priceCents;
  final String currency;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? completedAt;

  // 🔹 Campos nuevos (fin de sesión y cobro)
  final String? endedBy; // 'speaker', 'companion', 'timeout', etc.
  final int? realDurationMinutes; // minutos reales que duró la sesión
  final int? billingMinutes; // minutos sobre los que se cobra
  final int? billingMinLimit; // normalmente 10
  final bool? minChargeApplied; // true si se aplicó el mínimo

  SessionModel({
    required this.id,
    required this.speakerId,
    required this.speakerAlias,
    required this.companionId,
    required this.companionAlias,
    required this.offerId,
    required this.status,
    required this.durationMinutes,
    required this.priceCents,
    required this.currency,
    required this.createdAt,
    required this.updatedAt,
    required this.completedAt,
    this.endedBy,
    this.realDurationMinutes,
    this.billingMinutes,
    this.billingMinLimit,
    this.minChargeApplied,
  });

  factory SessionModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return SessionModel(
      id: doc.id,
      speakerId: d['speakerId'] ?? '',
      speakerAlias: d['speakerAlias'] ?? '',
      companionId: d['companionId'] ?? '',
      companionAlias: d['companionAlias'] ?? '',
      offerId: d['offerId'] ?? '',
      status: d['status'] ?? 'active',
      durationMinutes: d['durationMinutes'] ?? 30,
      priceCents: d['priceCents'] ?? 0,
      currency: d['currency'] ?? 'usd',

      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
      completedAt: (d['completedAt'] as Timestamp?)?.toDate(),

      // 🔹 Campos nuevos (opcionales por compatibilidad)
      endedBy: d['endedBy'] as String?,
      realDurationMinutes: d['realDurationMinutes'] is int
          ? d['realDurationMinutes'] as int
          : null,
      billingMinutes: d['billingMinutes'] is int
          ? d['billingMinutes'] as int
          : null,
      billingMinLimit: d['billingMinLimit'] is int
          ? d['billingMinLimit'] as int
          : null,
      minChargeApplied: d['minChargeApplied'] is bool
          ? d['minChargeApplied'] as bool
          : null,
    );
  }
}
