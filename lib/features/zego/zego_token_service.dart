import 'package:cloud_functions/cloud_functions.dart';

import 'zego_config.dart';

class ZegoTokenResponse {
  final String token;
  final int expireAtMs;

  const ZegoTokenResponse({required this.token, required this.expireAtMs});
}

class ZegoTokenService {
  Future<ZegoTokenResponse> fetchToken({
    required String userId,
    required String userName,
  }) async {
    final callable =
        FirebaseFunctions.instance.httpsCallable(kZegoTokenFunctionName);
    final response = await callable.call(<String, dynamic>{
      'userId': userId,
      'userName': userName,
    });

    final data = Map<String, dynamic>.from(response.data as Map);
    final token = (data['token'] ?? '').toString();
    final expireAtMs = (data['expireAtMs'] ?? 0) as int;

    if (token.isEmpty) {
      throw StateError('El token de Zego está vacío.');
    }

    return ZegoTokenResponse(token: token, expireAtMs: expireAtMs);
  }
}
