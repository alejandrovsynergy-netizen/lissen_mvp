// lib/features/zego/zego_config.dart
//
// ZEGOCLOUD config
//
// ✅ Para que chat y llamadas funcionen, necesitas AppID y AppSign del MISMO proyecto en ZEGOCLOUD.
// ✅ Puedes pasar AppSign por --dart-define para no hardcodearlo.
//
// Ejemplo:
// flutter run --dart-define=ZEGO_APP_SIGN=TU_APPSIGN
// flutter run --dart-define=ZEGO_APP_SIGN=TU_APPSIGN --dart-define=ZEGO_CALL_RESOURCE_ID=lissen_call

// 🔵 AppID (SIEMPRE es número). Pon aquí tu AppID real.
const int kZegoAppId = 346791689;

// 🔵 AppSign (preferido: por environment). Si no lo pasas, usa el fallback hardcoded.
const String _kZegoAppSignEnv =
    String.fromEnvironment('ZEGO_APP_SIGN', defaultValue: '');

// ✅ Fallback hardcoded (solo para que funcione aunque no uses dart-define).
const String _kZegoAppSignHardcoded =
    '34d7fee515e5d505b0eefc28016c98cb50b66afc3d800796e2e4f1a109d38bb2';

// ✅ Esta es la única constante pública que usará la app.
const String kZegoAppSign =
    (_kZegoAppSignEnv == '') ? _kZegoAppSignHardcoded : _kZegoAppSignEnv;

// Si usas Cloud Function para tokens (opcional por ahora)
const int kZegoTokenExpireSeconds = 60 * 60 * 2;
const String kZegoTokenFunctionName = 'zego_generateToken';

// Para Call Invitation (notificaciones de llamada).
const String kZegoCallInvitationResourceId =
    String.fromEnvironment('ZEGO_CALL_RESOURCE_ID', defaultValue: 'lissen_call');
