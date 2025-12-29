import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:zego_zimkit/zego_zimkit.dart';

import 'firebase_options.dart';
import 'screens/auth_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/lissen_home.dart';
import 'features/sessions/ui/session_screen.dart';
import 'screens/global_session_rating_listener.dart';
import 'features/zego/zego_config.dart';

import 'theme/chat_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  ZIMKit().init(appID: kZegoAppId);
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
        Color(0xFF020617), // slate-950
        Color(0xFF0B1B4D), // deep blue
        Color(0xFF0F172A), // slate-900
      ],
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,

      // ✅ Tema (tuya)
      theme: ChatTheme.dark(),
      darkTheme: ChatTheme.dark(),
      themeMode: ThemeMode.system,

      // ✅ Fondo global
      builder: (context, child) {
        return Container(
          decoration: const BoxDecoration(gradient: bgGradient),
          child: child ?? const SizedBox.shrink(),
        );
      },

      home: const _AuthGate(),
    );
  }
}

/// Escucha el estado de Firebase Auth.
/// Si no hay usuario -> AuthScreen
/// Si hay usuario -> _RootController envuelto con GlobalSessionRatingListener
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

        // 🔴 Sin usuario: mostrar tu pantalla real de login/registro
        if (user == null) {
          return const AuthScreen();
        }

        // 🟢 Con usuario: montamos el listener global alrededor del root
        return GlobalSessionRatingListener(
          child: _RootController(userId: user.uid),
        );
      },
    );
  }
}

/// Mira el documento en 'users/{uid}' y decide:
/// - si falta onboarding -> OnboardingScreen
/// - si ya está listo   ->
///     - si hay sesión activa -> SessionConversationScreen (LOCK-IN)
///     - si no hay sesión     -> LissenHome
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

        // 👇 Si no existe el documento en 'users/{userId}',
        // lo creamos vacío y mandamos a Onboarding.
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

        // 🔥 LOCK-IN solo depende de sessions, aquí sí usamos StreamBuilder
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
