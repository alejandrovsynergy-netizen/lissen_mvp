import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'legal_document_screen.dart';
import 'legal_texts.dart';

class HelpAccountScreen extends StatefulWidget {
  const HelpAccountScreen({super.key});

  @override
  State<HelpAccountScreen> createState() => _HelpAccountScreenState();
}

class _HelpAccountScreenState extends State<HelpAccountScreen> {
  final TextEditingController _messageC = TextEditingController();
  bool _sending = false;
  bool _deleting = false;

  @override
  void dispose() {
    _messageC.dispose();
    super.dispose();
  }

  Future<void> _sendHelpMessage(String uid) async {
    final msg = _messageC.text.trim();
    if (msg.isEmpty) return;
    if (_sending) return;

    setState(() => _sending = true);
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final recentSnap = await FirebaseFirestore.instance
          .collection('support_messages')
          .where('uid', isEqualTo: uid)
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .limit(3)
          .get();

      if (recentSnap.docs.length >= 2) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Limite diario alcanzado: 2 mensajes por dia.'),
          ),
        );
        return;
      }

      await FirebaseFirestore.instance.collection('support_messages').add({
        'uid': uid,
        'message': msg,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      _messageC.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mensaje enviado.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo enviar: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<bool> _confirmDeleteDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar cuenta'),
        content: const Text(
          'Esta accion elimina tu cuenta de forma permanente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    return confirm == true;
  }

  Future<bool> _reauthWithGoogle() async {
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Inicio con Google cancelado.')),
        );
      }
      return false;
    }

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    await FirebaseAuth.instance.currentUser!.reauthenticateWithCredential(
      credential,
    );
    return true;
  }

  Future<bool> _reauthWithFacebook() async {
    final result = await FacebookAuth.instance.login();
    if (result.status != LoginStatus.success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo iniciar con Facebook.')),
        );
      }
      return false;
    }

    final accessToken = result.accessToken;
    if (accessToken == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo obtener el token de Facebook.')),
        );
      }
      return false;
    }

    final credential = FacebookAuthProvider.credential(accessToken.token);
    await FirebaseAuth.instance.currentUser!.reauthenticateWithCredential(
      credential,
    );
    return true;
  }

  Future<void> _deleteAccountData(String uid) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).delete();
    await FirebaseAuth.instance.currentUser!.delete();
    await FirebaseAuth.instance.signOut();
  }

  Future<void> _confirmDeleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (_deleting) return;

    final providers = user.providerData.map((p) => p.providerId).toSet();
    final hasPassword = providers.contains('password');
    final hasGoogle = providers.contains('google.com');
    final hasFacebook = providers.contains('facebook.com');

    if (hasPassword) {
      final email = user.email;
      if (email == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo verificar tu cuenta.')),
        );
        return;
      }

      final passwordC = TextEditingController();
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Eliminar cuenta'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Esta accion elimina tu cuenta de forma permanente.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordC,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Contrasena',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar'),
            ),
          ],
        ),
      );

      final password = passwordC.text;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        passwordC.dispose();
      });
      if (confirm != true) return;
      if (password.trim().isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Debes escribir tu contrasena.')),
        );
        return;
      }

      setState(() => _deleting = true);
      try {
        final credential = EmailAuthProvider.credential(
          email: email,
          password: password.trim(),
        );
        await user.reauthenticateWithCredential(credential);
        await _deleteAccountData(user.uid);

        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
      } on FirebaseAuthException catch (e) {
        if (!mounted) return;
        final msg = e.message ?? 'No se pudo eliminar la cuenta.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo eliminar: $e')),
        );
      } finally {
        if (mounted) setState(() => _deleting = false);
      }
      return;
    }

    if (hasGoogle || hasFacebook) {
      final confirmed = await _confirmDeleteDialog();
      if (!confirmed) return;

      setState(() => _deleting = true);
      try {
        bool reauthOk = false;
        if (hasGoogle) {
          reauthOk = await _reauthWithGoogle();
        } else if (hasFacebook) {
          reauthOk = await _reauthWithFacebook();
        }

        if (!reauthOk) {
          if (mounted) setState(() => _deleting = false);
          return;
        }

        await _deleteAccountData(user.uid);
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
      } on FirebaseAuthException catch (e) {
        if (!mounted) return;
        final msg = e.message ?? 'No se pudo eliminar la cuenta.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo eliminar: $e')),
        );
      } finally {
        if (mounted) setState(() => _deleting = false);
      }
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No se pudo verificar tu cuenta. Contacta soporte.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ayuda y cuenta')),
        body: const Center(
          child: Text(
            'Necesitas iniciar sesión para ver esta sección.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Ayuda y cuenta')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data?.data() ?? {};

          void _openDoc(String title, String content) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => LegalDocumentScreen(
                  title: title,
                  content: content,
                ),
              ),
            );
          }

          final List<String> blockedUsers =
              (data['blockedUsers'] as List<dynamic>?)
                      ?.map((e) => e.toString())
                      .toList() ??
                  [];
          Future<void> unblockUser(String blockedUid) async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Desbloquear usuario'),
                content: const Text(
                  '¿Quieres desbloquear a este usuario?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancelar'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Desbloquear'),
                  ),
                ],
              ),
            );

            if (confirm != true) return;

            try {
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .update({
                'blockedUsers': FieldValue.arrayRemove([blockedUid]),
              });

              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Usuario desbloqueado.')),
              );
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('No se pudo desbloquear: $e')),
              );
            }
          }

          return ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.block),
                title: const Text('Usuarios bloqueados'),
                subtitle: Text(
                  blockedUsers.isEmpty
                      ? 'No has bloqueado a nadie.'
                      : 'Has bloqueado ${blockedUsers.length} usuario(s).',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              if (blockedUsers.isNotEmpty) const Divider(height: 8),

              if (blockedUsers.isNotEmpty)
                ...blockedUsers.map(
                  (uid) => ListTile(
                    leading: const Icon(Icons.person_off_outlined, size: 20),
                    title: Text(uid, style: const TextStyle(fontSize: 13)),
                    subtitle: const Text(
                      'Bloqueado',
                      style: TextStyle(fontSize: 11),
                    ),
                    trailing: TextButton(
                      onPressed: () => unblockUser(uid),
                      child: const Text('Desbloquear'),
                    ),
                  ),
                ),

              if (blockedUsers.isNotEmpty) const Divider(height: 8),

              const ListTile(
                leading: Icon(Icons.chat_bubble_outline),
                title: Text('Ayuda y sugerencias'),
                subtitle: Text(
                  'Cuéntanos si tienes problemas o ideas para mejorar Lissen.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  children: [
                    TextField(
                      controller: _messageC,
                      minLines: 2,
                      maxLines: 4,
                      maxLength: 240,
                      textInputAction: TextInputAction.send,
                      decoration: const InputDecoration(
                        hintText: 'Escribe un mensaje corto...',
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                      onSubmitted: (_) => _sendHelpMessage(user.uid),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed:
                            _sending ? null : () => _sendHelpMessage(user.uid),
                        child: _sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Enviar mensaje'),
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(height: 8),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('Terminos y condiciones'),
                subtitle: const Text(
                  'Lee los terminos bajo los cuales funciona Lissen.',
                  style: TextStyle(fontSize: 12),
                ),
                onTap: () => _openDoc(kTermsTitle, kTermsAndConditionsText),
              ),
              const Divider(height: 8),
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('Politica de privacidad'),
                subtitle: const Text(
                  'Conoce como protegemos tu informacion.',
                  style: TextStyle(fontSize: 12),
                ),
                onTap: () => _openDoc(kPrivacyNoticeTitle, kPrivacyNoticeText),
              ),
              const Divider(height: 8),
              const ListTile(
                leading: Icon(Icons.email_outlined),
                title: Text('Información de contacto'),
                subtitle: Text(
                  'alejandro.v.synergy@gmail.com - 8991590100',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const Divider(height: 8),
              ListTile(
                leading: const Icon(Icons.delete_forever_outlined),
                title: const Text(
                  'Eliminar cuenta',
                  style: TextStyle(color: Colors.red),
                ),
                subtitle: const Text(
                  'Esta opcion elimina tu cuenta permanentemente.',
                  style: TextStyle(fontSize: 12),
                ),
                onTap: _deleting ? null : _confirmDeleteAccount,
              ),
            ],
          );
        },
      ),
    );
  }
}