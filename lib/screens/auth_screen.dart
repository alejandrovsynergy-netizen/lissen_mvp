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

  final GoogleSignIn _googleSignIn = GoogleSignIn();

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
    } on FirebaseAuthException catch (e) {
      setState(() => errorText = _firebaseErrorMsg(e));
    } catch (_) {
      setState(() => errorText = 'Ocurrió un error inesperado al iniciar sesión.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

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
    } on FirebaseAuthException catch (e) {
      setState(() => errorText = _firebaseErrorMsg(e));
    } catch (_) {
      setState(() => errorText = 'Ocurrió un error inesperado al crear tu cuenta.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      loading = true;
      errorText = null;
    });

    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        if (mounted) setState(() => loading = false);
        return;
      }

      final googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCred = await FirebaseAuth.instance.signInWithCredential(credential);

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
    } catch (_) {
      setState(() => errorText = 'Error al iniciar con Google.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _signInWithFacebook() async {
    setState(() {
      loading = true;
      errorText = null;
    });

    try {
      final LoginResult result = await FacebookAuth.instance.login();

      if (result.status == LoginStatus.cancelled) {
        if (mounted) setState(() => loading = false);
        return;
      }

      if (result.status != LoginStatus.success) {
        if (mounted) setState(() => errorText = 'No se pudo iniciar con Facebook.');
        return;
      }

      final accessToken = result.accessToken;
      if (accessToken == null) {
        if (mounted) setState(() => errorText = 'No se pudo obtener el token de Facebook.');
        return;
      }

      final credential = FacebookAuthProvider.credential(accessToken.token);
      final userCred = await FirebaseAuth.instance.signInWithCredential(credential);

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
    } catch (_) {
      setState(() => errorText = 'Error al iniciar con Facebook.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _sendPasswordReset() async {
    if (loading) return;

    final email = emailC.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => errorText = 'Escribe un email valido.');
      return;
    }

    setState(() {
      loading = true;
      errorText = null;
    });

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Te enviamos un correo para restablecer tu contrasena.'),
        ),
      );
    } on FirebaseAuthException catch (e) {
      setState(() => errorText = _firebaseErrorMsg(e));
    } catch (_) {
      setState(() => errorText = 'No se pudo enviar el correo.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

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
        return 'Hubo un problema al autenticar. Intenta de nuevo.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(isLogin ? 'Iniciar sesión' : 'Crear cuenta'),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // =========================
                // HEADER SOLO EN LOGIN
                // =========================
                if (isLogin) ...[
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.mic_none, size: 56, color: cs.primary),
                      const SizedBox(height: 12),
                      Text(
                        'Bienvenido a Lissen',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Conversaciones que sí valen la pena.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                ] else ...[
                  // =========================
                  // HEADER SOLO EN CREAR CUENTA
                  // (SIN "Bienvenido" NI subtítulo)
                  // =========================
                  const SizedBox(height: 6),
                  Text(
                    'Selecciona una opción o ingresa tu correo',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 18),
                ],

                // =========================
                // BOTONES SOCIALES (arriba en crear cuenta)
                // =========================
                _buildSocialButtons(loading: loading),

                const SizedBox(height: 22),

                // =========================
                // SEPARADOR
                // =========================
                Row(
                  children: [
                    Expanded(
                      child: Divider(color: cs.onSurfaceVariant.withOpacity(0.35)),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      isLogin ? 'o usa tu correo' : 'o crea tu cuenta con correo',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Divider(color: cs.onSurfaceVariant.withOpacity(0.35)),
                    ),
                  ],
                ),

                const SizedBox(height: 22),

                // =========================
                // CAMPOS
                // =========================
                TextField(
                  controller: emailC,
                  keyboardType: TextInputType.emailAddress,
                  enabled: !loading,
                  decoration: const InputDecoration(
                    labelText: 'Correo electrónico',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passC,
                  obscureText: true,
                  enabled: !loading,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña',
                  ),
                ),

                if (isLogin) ...[
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: loading ? null : _sendPasswordReset,
                      child: const Text('Olvide mi contrasena'),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                const SizedBox(height: 16),

                if (errorText != null)
                  Text(
                    errorText!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.error,
                      fontSize: 12,
                    ),
                  ),

                const SizedBox(height: 16),

                // =========================
                // CTA
                // =========================
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: loading ? null : () => isLogin ? _login() : _register(),
                    child: loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(isLogin ? 'Iniciar sesión' : 'Crear cuenta'),
                  ),
                ),

                const SizedBox(height: 18),

                // =========================
                // TOGGLE
                // =========================
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

                Text(
                  'Lissen nunca comparte tus datos de acceso con otras personas.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
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

  Widget _buildSocialButtons({required bool loading}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // GOOGLE (blanco, borde, logo estilo oficial)
        OutlinedButton(
          onPressed: loading ? null : _handleGoogleBtn,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: const StadiumBorder(),
            backgroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFFE0E0E0)),
            foregroundColor: Colors.black87,
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _GoogleLogoG(),
              SizedBox(width: 12),
              Text(
                'Continuar con Google',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // FACEBOOK (azul oficial)
        ElevatedButton(
          onPressed: loading ? null : _handleFacebookBtn,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: const StadiumBorder(),
            backgroundColor: const Color(0xFF1877F2),
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.facebook_rounded),
              SizedBox(width: 12),
              Text(
                'Continuar con Facebook',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

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
              Color(0xFF4285F4),
            ],
          ).createShader(bounds);
        },
        child: const Text(
          'G',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
