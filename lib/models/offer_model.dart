import 'package:cloud_firestore/cloud_firestore.dart';

class OfferModel {
  // 🔵 Estados oficiales de oferta
  static const String statusActive = 'active';
  static const String statusProcessingPayment = 'processing_payment';
  static const String statusPendingSpeaker = 'pending_speaker';
  static const String statusPendingCompanion = 'pending_companion';
  static const String statusUsed = 'used';

  static const List<String> validStatuses = [
    statusActive,
    statusProcessingPayment,
    statusPaymentRequired,
    statusPendingSpeaker,
    statusPendingCompanion,
    statusUsed,
  ];

  final String id;

  // 🔹 Info del hablante / creador
  final String speakerId;
  final String speakerAlias;
  final String speakerCountry;
  final String speakerCity;
  final String? speakerPhotoUrl;
  final String? speakerBio;

  // 🔹 Estado de ánimo
  final String? mood;

  // 🔹 Contenido de la oferta
  final String title;
  final String description;

  /// Precio total mínimo en centavos (lo que se muestra como “Monto” mínimo).
  final int totalMinAmountCents;

  /// Precio total legacy en centavos (compatibilidad con código viejo).
  final int priceCents;

  final String currency;

  /// Duración estimada en minutos (también usada como minMinutes).
  final int durationMinutes;

  /// A quién va dirigida la oferta: 'todos' | 'hombre' | 'mujer'
  final String targetGender;

  // 🔹 Nuevo sistema de precios
  /// Precio por minuto en centavos (ej. 150 = 1.50 USD)
  final int pricePerMinuteCents;

  /// Minutos mínimos a cobrar (ej. 10)
  final int minMinutes;

  // 🔹 Tipo de comunicación: chat | voice | video
  final String? communicationType;

  // 🔹 Geolocalización simplificada
  final String? locationMode; // nearby | city | country | global
  final int? radiusKm;

  // 🔹 Código de compañera (si aplica)
  final String? companionCode;

  // 🔹 Estado actual
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // 🔹 Datos cuando alguien la acepta (pendiente de hablante)
  final String? pendingSpeakerId;
  final String? pendingCompanionId;
  final String? pendingCompanionAlias;
  final DateTime? pendingSince;

  OfferModel({
    required this.id,
    required this.speakerId,
    required this.speakerAlias,
    required this.speakerCountry,
    required this.speakerCity,
    required this.title,
    required this.description,
    required this.totalMinAmountCents,
    required this.priceCents,
    required this.currency,
    required this.durationMinutes,
    required this.targetGender,
    required this.pricePerMinuteCents,
    required this.minMinutes,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.speakerPhotoUrl,
    this.speakerBio,
    this.mood,
    this.communicationType,
    this.locationMode,
    this.radiusKm,
    this.companionCode,
    this.pendingSpeakerId,
    this.pendingCompanionId,
    this.pendingCompanionAlias,
    this.pendingSince,
  });

  factory OfferModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};

    // Validamos el estado; si no existe, se asume 'active'
    final rawStatus = d['status'] as String? ?? statusActive;
    final safeStatus = validStatuses.contains(rawStatus)
        ? rawStatus
        : statusActive;

    // Precio por minuto y mínimos con fallback a los campos viejos
    final int rawPricePerMinuteCents =
        d['pricePerMinuteCents'] ?? d['priceCents'] ?? 0;

    final int rawMinMinutes = d['minMinutes'] ?? d['durationMinutes'] ?? 0;

    return OfferModel(
      id: doc.id,

      // 🔹 Hablante
      speakerId: d['speakerId'] ?? '',
      speakerAlias: d['speakerAlias'] ?? '',
      speakerCountry: d['speakerCountry'] ?? '',
      speakerCity: d['speakerCity'] ?? '',
      speakerPhotoUrl: d['speakerPhotoUrl'],
      speakerBio: d['speakerBio'],

      // 🔹 Estado de ánimo
      mood: d['mood'],

      // 🔹 Contenido
      title: d['title'] ?? '',
      description: d['description'] ?? '',

      totalMinAmountCents: d['totalMinAmountCents'] ?? d['priceCents'] ?? 0,
      priceCents: d['priceCents'] ?? 0,
      currency: d['currency'] ?? 'usd',
      durationMinutes: d['durationMinutes'] ?? 30,
      targetGender: d['targetGender'] ?? 'todos',

      // 🔹 Precios nuevos
      pricePerMinuteCents: rawPricePerMinuteCents,
      minMinutes: rawMinMinutes,

      // 🔹 Tipo de comunicación
      communicationType: d['communicationType'],

      // 🔹 Geo
      locationMode: d['locationMode'],
      radiusKm: d['radiusKm'],

      // 🔹 Código de compañera
      companionCode: d['companionCode'],

      // 🔹 Estado
      status: safeStatus,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),

      // 🔹 Pendiente cuando alguien la acepta
      pendingSpeakerId: d['pendingSpeakerId'],
      pendingCompanionId: d['pendingCompanionId'],
      pendingCompanionAlias: d['pendingCompanionAlias'],
      pendingSince: (d['pendingSince'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'speakerId': speakerId,
      'speakerAlias': speakerAlias,
      'speakerCountry': speakerCountry,
      'speakerCity': speakerCity,
      'speakerPhotoUrl': speakerPhotoUrl,
      'speakerBio': speakerBio,
      'mood': mood,
      'title': title,
      'description': description,
      'totalMinAmountCents': totalMinAmountCents,
      'priceCents': priceCents,
      'currency': currency,
      'durationMinutes': durationMinutes,
      'targetGender': targetGender,
      'pricePerMinuteCents': pricePerMinuteCents,
      'minMinutes': minMinutes,
      'communicationType': communicationType,
      'locationMode': locationMode,
      'radiusKm': radiusKm,
      'companionCode': companionCode,
      'status': status,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'pendingSpeakerId': pendingSpeakerId,
      'pendingCompanionId': pendingCompanionId,
      'pendingCompanionAlias': pendingCompanionAlias,
      'pendingSince': pendingSince != null
          ? Timestamp.fromDate(pendingSince!)
          : null,
    };
  }
}
