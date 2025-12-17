import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// 🔵 Google / Facebook
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool isLogin = true;
  bool loading = false;

  final emailC = TextEditingController();
  final passC = TextEditingController();

  String? errorText;

  // ✅ Mejor: instancia única
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  // ====== WRAPPERS PARA LOS BOTONES (void, no async) ======
  void _handleGoogleBtn() {
    if (loading) return;
    _signInWithGoogle();
  }

  void _handleFacebookBtn() {
    if (loading) return;
    _signInWithFacebook();
  }

  @override
  void dispose() {
    emailC.dispose();
    passC.dispose();
    super.dispose();
  }

  // ============================================================
  // ✅ Validación simple (evita errores tontos y requests inútiles)
  // ============================================================
  bool _validateEmailPass({required bool forRegister}) {
    final email = emailC.text.trim();
    final pass = passC.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      setState(() => errorText = 'Escribe un email válido.');
      return false;
    }
    if (pass.isEmpty) {
      setState(() => errorText = 'Escribe tu contraseña.');
      return false;
    }
    if (forRegister && pass.length < 6) {
      setState(() => errorText = 'La contraseña debe tener al menos 6 caracteres.');
      return false;
    }
    return true;
  }

  // ============================================================
  // 🔵 LOGIN CON EMAIL
  // ============================================================
  Future<void> _login() async {
    if (!_validateEmailPass(forRegister: false)) return;

    setState(() {
      loading = true;
      errorText = null;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailC.text.trim(),
        password: passC.text.trim(),
      );
      // 🚫 No navegamos aquí, el AuthGate de main.dart se encarga
    } on FirebaseAuthException catch (e) {
      setState(() => errorText = _firebaseErrorMsg(e));
    } catch (_) {
      setState(() => errorText = 'Ocurrió un error inesperado al iniciar sesión.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // ============================================================
  // 🔵 REGISTRO CON EMAIL
  // ============================================================
  Future<void> _register() async {
    if (!_validateEmailPass(forRegister: true)) return;

    setState(() {
      loading = true;
      errorText = null;
    });

    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: emailC.text.trim(),
        password: passC.text.trim(),
      );

      final uid = cred.user!.uid;
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'uid': uid,
        'onboardingCompleted': false,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      // AuthGate decide si manda a onboarding o home
    } on FirebaseAuthException catch (e) {
      setState(() => errorText = _firebaseErrorMsg(e));
    } catch (_) {
      setState(() => errorText = 'Ocurrió un error inesperado al crear tu cuenta.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // ============================================================
  // 🔵 GOOGLE SIGN-IN (login + registro)
  // ============================================================
  Future<void> _signInWithGoogle() async {
    setState(() {
      loading = true;
      errorText = null;
    });

    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        // Usuario canceló
        if (mounted) setState(() => loading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCred = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );

      final uid = userCred.user!.uid;
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final snap = await userRef.get();

      // Solo creamos el doc si NO existe (para no pisar onboardingCompleted)
      if (!snap.exists) {
        await userRef.set({
          'uid': uid,
          'onboardingCompleted': false,
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      // AuthGate ya se encargará de mandar a Onboarding o Home
    } on FirebaseAuthException catch (e) {
      setState(() => errorText = _firebaseErrorMsg(e));
    } catch (_) {
      setState(() => errorText = 'Error al iniciar con Google.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // ============================================================
  // 🔵 FACEBOOK LOGIN (login + registro)
  // ============================================================
  Future<void> _signInWithFacebook() async {
    setState(() {
      loading = true;
      errorText = null;
    });

    try {
      // Si ves sesiones "pegadas", prueba descomentar esto:
      // await FacebookAuth.instance.logOut();

      final LoginResult result = await FacebookAuth.instance.login();

      if (result.status == LoginStatus.cancelled) {
        if (mounted) setState(() => loading = false);
        return;
      }

      if (result.status != LoginStatus.success) {
        if (mounted) {
          setState(() => errorText = 'No se pudo iniciar con Facebook.');
        }
        return;
      }

      final accessToken = result.accessToken;
      if (accessToken == null) {
        if (mounted) {
          setState(() => errorText = 'No se pudo obtener el token de Facebook.');
        }
        return;
      }

      final credential = FacebookAuthProvider.credential(accessToken.token);

      final userCred = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );

      final uid = userCred.user!.uid;
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final snap = await userRef.get();

      if (!snap.exists) {
        await userRef.set({
          'uid': uid,
          'onboardingCompleted': false,
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } on FirebaseAuthException catch (e) {
      setState(() => errorText = _firebaseErrorMsg(e));
    } catch (e) {
      setState(() => errorText = 'Error al iniciar con Facebook.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // ============================================================
  // 🔵 TRADUCIR ERRORES DE FIREBASE
  // ============================================================
  String _firebaseErrorMsg(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'El email no es válido.';
      case 'user-not-found':
        return 'No existe una cuenta con ese email.';
      case 'wrong-password':
        return 'Contraseña incorrecta.';
      case 'email-already-in-use':
        return 'Ese email ya está registrado.';
      case 'weak-password':
        return 'La contraseña es muy débil.';
      case 'account-exists-with-different-credential':
        return 'Ese correo ya existe con otro método de inicio.';
      case 'user-disabled':
        return 'Esta cuenta está deshabilitada.';
      case 'too-many-requests':
        return 'Demasiados intentos. Intenta más tarde.';
      default:
        return 'Error: ${e.message ?? 'No se pudo autenticar.'}';
    }
  }

  // ============================================================
  // 🔵 UI
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(isLogin ? 'Iniciar sesión' : 'Crear cuenta'),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ========= LOGO + TITULO =========
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.mic_none,
                      size: 56,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Bienvenido a Lissen',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Conversaciones que sí valen la pena.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // ========= BOTONES SOCIALES =========
                _buildSocialButtons(),

                const SizedBox(height: 24),

                // ========= SEPARADOR =========
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    const SizedBox(width: 8),
                    Text(
                      'o usa tu correo',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(child: Divider()),
                  ],
                ),

                const SizedBox(height: 24),

                // ========= EMAIL + PASSWORD =========
                TextField(
                  controller: emailC,
                  keyboardType: TextInputType.emailAddress,
                  enabled: !loading,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passC,
                  obscureText: true,
                  enabled: !loading,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña',
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 16),

                if (errorText != null)
                  Text(
                    errorText!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),

                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: loading
                        ? null
                        : () => isLogin ? _login() : _register(),
                    child: loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(isLogin ? 'Iniciar sesión' : 'Crear cuenta'),
                  ),
                ),

                const SizedBox(height: 20),

                // ========= TOGGLE LOGIN / REGISTRO =========
                TextButton(
                  onPressed: loading
                      ? null
                      : () {
                          setState(() {
                            errorText = null;
                            isLogin = !isLogin;
                          });
                        },
                  child: Text(
                    isLogin
                        ? '¿No tienes cuenta? Crear cuenta'
                        : '¿Ya tienes cuenta? Iniciar sesión',
                  ),
                ),

                const SizedBox(height: 8),

                // ========= TEXTO DE CONFIANZA =========
                Text(
                  'Lissen nunca comparte tus datos de acceso con otras personas.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // 🔵 BOTONES SOCIALES (UI) – estilo tipo captura
  // ============================================================
  Widget _buildSocialButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Facebook (azul, texto blanco, pill)
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: loading ? null : _handleFacebookBtn,
          child: Opacity(
            opacity: loading ? 0.6 : 1,
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF1877F2),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    child: const Icon(
                      Icons.facebook,
                      size: 18,
                      color: Color(0xFF1877F2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Continuar con Facebook',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Google (gris claro, texto negro, pill, G multicolor sin PNG)
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: loading ? null : _handleGoogleBtn,
          child: Opacity(
            opacity: loading ? 0.6 : 1,
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.grey),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _GoogleLogoG(),
                  SizedBox(width: 12),
                  Text(
                    'Continuar con Google',
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// 🔵 Widget privado para la "G" multicolor de Google (sin PNG)
// ============================================================
class _GoogleLogoG extends StatelessWidget {
  const _GoogleLogoG();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
      ),
      alignment: Alignment.center,
      child: ShaderMask(
        shaderCallback: (Rect bounds) {
          return const SweepGradient(
            colors: [
              Color(0xFF4285F4), // azul
              Color(0xFF34A853), // verde
              Color(0xFFFBBC05), // amarillo
              Color(0xFFEA4335), // rojo
              Color(0xFF4285F4), // cerrar el círculo
            ],
          ).createShader(bounds);
        },
        child: const Text(
          'G',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Colors.white, // se usa como máscara
          ),
        ),
      ),
    );
  }
}
