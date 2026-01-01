import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ZIMKit (chat)
import 'package:zego_zimkit/zego_zimkit.dart';

// Call Invitation
import 'package:zego_uikit/zego_uikit.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:zego_uikit_signaling_plugin/zego_uikit_signaling_plugin.dart';

import 'firebase_options.dart';
import 'screens/auth_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/lissen_home.dart';
import 'features/sessions/ui/session_screen.dart';
import 'screens/global_session_rating_listener.dart';
import 'features/zego/zego_config.dart';
import 'theme/chat_theme.dart';

final GlobalKey<NavigatorState> _zegoNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // ✅ Requerido por Zego Call Invitation (para navegar al aceptar)
  ZegoUIKitPrebuiltCallInvitationService().setNavigatorKey(_zegoNavigatorKey);

  // ✅ Recomendado por Zego (system calling UI / background)
  try {
    await ZegoUIKit().initLog();
    await ZegoUIKitPrebuiltCallInvitationService().useSystemCallingUI(
      [ZegoUIKitSignalingPlugin()],
    );
  } catch (e, st) {
    debugPrint('⚠️ Zego useSystemCallingUI falló: $e\n$st');
  }

  // ✅ No dejamos que un problema de ZIMKit rompa login
  try {
    await ZIMKit().init(appID: kZegoAppId, appSign: kZegoAppSign);
  } catch (e, st) {
    debugPrint('⚠️ ZIMKit init falló (la app seguirá corriendo): $e\n$st');
  }

  runApp(const LissenApp());
}

class LissenApp extends StatelessWidget {
  const LissenApp({super.key});

  @override
  Widget build(BuildContext context) {
    const bgGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF020617),
        Color(0xFF0B1B4D),
        Color(0xFF0F172A),
      ],
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,

      // ✅ navigatorKey para Call Invitation
      navigatorKey: _zegoNavigatorKey,

      theme: ChatTheme.dark(),
      darkTheme: ChatTheme.dark(),
      themeMode: ThemeMode.system,

      builder: (context, child) {
        final media = MediaQuery.of(context);
        return Container(
          decoration: const BoxDecoration(gradient: bgGradient),
          child: SafeArea(
            top: false,
            bottom: true,
            child: MediaQuery(
              data: media.copyWith(
                padding: media.padding.copyWith(bottom: 0),
              ),
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
      },

      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snap.data;

        if (user == null) {
          // Si no hay usuario, aseguramos des-inicializar
          // (evita notificaciones “fantasma” después de logout)
          ZegoUIKitPrebuiltCallInvitationService().uninit();
          return const AuthScreen();
        }

        return _ZegoCallBootstrapper(
          uid: user.uid,
          child: GlobalSessionRatingListener(
            child: _RootController(userId: user.uid),
          ),
        );
      },
    );
  }
}

/// Inicializa Call Invitation justo después del login (1 vez)
class _ZegoCallBootstrapper extends StatefulWidget {
  final String uid;
  final Widget child;

  const _ZegoCallBootstrapper({required this.uid, required this.child});

  @override
  State<_ZegoCallBootstrapper> createState() => _ZegoCallBootstrapperState();
}

class _ZegoCallBootstrapperState extends State<_ZegoCallBootstrapper> {
  bool _inited = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (_inited) return;
    _inited = true;

    // nombre para mostrar (si tienes alias en users/{uid}, puedes tomarlo de ahí)
    String name = FirebaseAuth.instance.currentUser?.displayName ?? 'Usuario';

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .get();
      final data = userDoc.data();
      final alias = (data?['alias'] ?? data?['displayName'] ?? '').toString();
      if (alias.trim().isNotEmpty) name = alias.trim();
    } catch (_) {}

    try {
      // OJO: esto debe correr tras login SIEMPRE (auto-login incluido) :contentReference[oaicite:6]{index=6}
      await ZegoUIKitPrebuiltCallInvitationService().init(
        appID: kZegoAppId,
        appSign: kZegoAppSign,
        userID: widget.uid,
        userName: name,
        plugins: [ZegoUIKitSignalingPlugin()],
      );
    } catch (e, st) {
      debugPrint('⚠️ Call Invitation init falló: $e\n$st');
    }
  }

  @override
  void dispose() {
    // No uninit aquí: solo en logout. (si lo haces aquí, se rompe al navegar)
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _RootController extends StatelessWidget {
  final String userId;

  const _RootController({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    final docRef = FirebaseFirestore.instance.collection('users').doc(userId);

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: docRef.get(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snap.hasError) {
          return Scaffold(
            body: Center(
              child: Text(
                'Error cargando usuario:\n${snap.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        if (!snap.hasData || !snap.data!.exists) {
          FirebaseFirestore.instance.collection('users').doc(userId).set({
            'uid': userId,
            'onboardingCompleted': false,
          }, SetOptions(merge: true));

          return OnboardingScreen(uid: userId, initialData: null);
        }

        final data = snap.data!.data() ?? {};
        final onboardingCompleted = data['onboardingCompleted'] == true;

        if (!onboardingCompleted) {
          return OnboardingScreen(
            uid: userId,
            initialData: data.isEmpty ? null : data,
          );
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('sessions')
              .where('participants', arrayContains: userId)
              .where('status', isEqualTo: 'active')
              .snapshots(),
          builder: (context, sesSnap) {
            if (sesSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (sesSnap.hasError) {
              return Scaffold(
                body: Center(
                  child: Text(
                    'Error cargando sesiones:\n${sesSnap.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            final docs = sesSnap.data?.docs ?? [];

            if (docs.isNotEmpty) {
              final sessionId = docs.first.id;
              return SessionConversationScreen(sessionId: sessionId);
            }

            return const LissenHome();
          },
        );
      },
    );
  }
}
