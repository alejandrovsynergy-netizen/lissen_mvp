import 'package:cloud_firestore/cloud_firestore.dart';

class CompanionCodeService {
  static Future<void> ensureCompanionCode({
    required String uid,
    required Map<String, dynamic> userData,
  }) async {
    final existing = (userData['companionCode'] as String?)?.trim();
    if (existing != null && existing.isNotEmpty) return;

    final String newCode = 'LIS-${uid.substring(0, 6).toUpperCase()}';

    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'companionCode': newCode,
    }, SetOptions(merge: true));
  }
}
