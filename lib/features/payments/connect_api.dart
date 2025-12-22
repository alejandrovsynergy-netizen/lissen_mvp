import 'package:cloud_functions/cloud_functions.dart';

class ConnectApi {
  ConnectApi({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  final FirebaseFunctions _functions;

  Future<String> createOnboardingLink({
    required String returnUrl,
    required String refreshUrl,
  }) async {
    final callable = _functions.httpsCallable('connect_createOnboardingLink');
    final res = await callable.call(<String, dynamic>{
      'returnUrl': returnUrl,
      'refreshUrl': refreshUrl,
    });

    final data = res.data;
    if (data is Map) {
      final m = Map<String, dynamic>.from(data);
      final url = (m['url'] ?? '').toString();
      if (url.isEmpty) throw StateError('No llegó url');
      return url;
    }
    throw StateError('connect_createOnboardingLink devolvió tipo inesperado: ${data.runtimeType}');
  }

  Future<Map<String, dynamic>> getAccountStatus() async {
    final callable = _functions.httpsCallable('connect_getAccountStatus');
    final res = await callable.call(<String, dynamic>{});

    final data = res.data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw StateError('connect_getAccountStatus devolvió tipo inesperado: ${data.runtimeType}');
  }

  Future<String> createExpressLoginLink() async {
    final callable = _functions.httpsCallable('connect_createLoginLink');
    final res = await callable.call(<String, dynamic>{});

    final data = res.data;
    if (data is Map) {
      final m = Map<String, dynamic>.from(data);
      final url = (m['url'] ?? '').toString();
      if (url.isEmpty) throw StateError('No llegó url');
      return url;
    }
    throw StateError('connect_createLoginLink devolvió tipo inesperado: ${data.runtimeType}');
  }
}
