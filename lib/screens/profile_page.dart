import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'profile/help_account_screen.dart';
import 'profile/services/companion_code_service.dart';
import 'profile/services/profile_photo_service.dart';
import 'profile/services/sign_out_service.dart';

import 'profile/account_security_screen.dart';
import 'profile/companion_config_screen.dart';
import 'profile/money_activity_screen.dart';

import 'edit_profile_screen.dart';
import 'gallery_screen.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _companionCodeEnsured = false;
  String? _ensuredUid;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ImagePicker _picker = ImagePicker();
 
  // ============================================================
  // Cambiar foto de perfil
  // ============================================================
  Future<void> _changeProfilePhoto() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (picked == null) return;

    try {
      final bytes = await picked.readAsBytes();
      await ProfilePhotoService.setNewProfilePhotoFromBytes(
        uid: user.uid,
        bytes: bytes,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error subiendo foto: $e')),
      );
    }
  }


  // ============================================================
  // Navegar a EDITAR PERFIL (pantalla existente)
  // ============================================================
  void _navigateToEditProfile(String uid, Map<String, dynamic> userData) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            EditProfileScreen(uid: uid, initialData: userData),
      ),
    );
  }

  // ============================================================
  // Navegar a GALERÍA
  // ============================================================
  void _openGallery(String uid) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => GalleryScreen(uid: uid)));
  }

  // ============================================================
  // Helpers de labels
  // ============================================================
  String _roleLabel(String role) {
    switch (role) {
      case 'speaker':
        return 'Hablante';
      case 'companion':
        return 'Compañera';
      default:
        return 'Sin rol definido';
    }
  }

  String _genderLabel(String gender) {
    switch (gender) {
      case 'hombre':
        return 'Hombre';
      case 'mujer':
        return 'Mujer';
      case 'otro':
        return 'No binario / Otro';
      case 'nsnc':
        return 'Prefiero no decir';
      default:
        return 'No especificado';
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('No autenticado.')));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snap.data!.data() ?? {};

        // ✅ Si cambió el usuario, resetea el flag
        if (_ensuredUid != user.uid) {
          _ensuredUid = user.uid;
          _companionCodeEnsured = false;
        }

        // Campos básicos
        final alias = (data['alias'] ?? user.email ?? 'Usuario') as String;
        final role = data['role'] as String? ?? '';
        final gender = data['gender'] as String? ?? '';
        final age = data['age']?.toString() ?? '—';
        final country = data['country'] as String? ?? '—';
        final city = data['city'] as String? ?? '—';
        final photoUrl = data['photoUrl'] as String?;

        // Nombre real (obligatorio desde onboarding; pero lo hacemos seguro)
        final realName = (data['name'] as String?)?.trim() ?? '';
        final displayName = realName.isNotEmpty ? '$alias ($realName)' : alias;

        // Biografía
        final bio = (data['bio'] as String?)?.trim() ?? '';
        // Si es compañera, aseguramos que tenga un código
        if (role == 'companion' && !_companionCodeEnsured) {
          _companionCodeEnsured = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            CompanionCodeService.ensureCompanionCode(
              uid: user.uid,
              userData: data,
            );
          });
        }


        return Scaffold(
          appBar: AppBar(
            centerTitle: true,
            title: const SizedBox.shrink(), // sin texto "Perfil"
            elevation: 0,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ======================================================
                // HEADER SIN CARD (estilo WhatsApp)
                // ======================================================
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: _changeProfilePhoto,
                            child: CircleAvatar(
                              radius: 32,
                              backgroundImage:
                                  photoUrl != null ? NetworkImage(photoUrl) : null,
                              child: photoUrl == null
                                  ? const Icon(Icons.person, size: 32)
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayName,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                if (age != 'null' && age != '—')
                                  Text(
                                    '$age años',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey[300],
                                    ),
                                  ),
                                if (user.email != null &&
                                    user.email!.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    user.email!,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey[400],
                                    ),
                                  ),
                                ],
                                if (role.isNotEmpty || gender.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    '${role.isNotEmpty ? _roleLabel(role) : ''}'
                                    '${role.isNotEmpty && gender.isNotEmpty ? ' · ' : ''}'
                                    '${gender.isNotEmpty ? _genderLabel(gender) : ''}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[300],
                                    ),
                                  ),
                                ],
                                if (city != '—' || country != '—') ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    '$city, $country',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[400],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () => _openGallery(user.uid),
                            icon: const Icon(Icons.collections_outlined),
                            tooltip: 'Galería de fotos',
                          ),
                        ],
                      ),
                      if (bio.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Biografía',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          bio,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[200],
                          ),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),

                // ======================================================
                // MENÚ PRINCIPAL DEL PANEL PRIVADO (sin cards, sin líneas)
                // ======================================================
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Configuración'),
                  subtitle: role == 'companion'
                      ? const Text(
                          'Disponibilidad, tarifas y código de compañera.',
                          style: TextStyle(fontSize: 12),
                        )
                      : const Text(
                          'Preferencias generales de uso.',
                          style: TextStyle(fontSize: 12),
                        ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CompanionConfigScreen(
                          uid: user.uid,
                          isCompanion: role == 'companion',
                        ),
                      ),
                    );
                  },
                ),

                ListTile(
                  leading: const Icon(Icons.attach_money),
                  title: const Text('Dinero y actividad'),
                  subtitle: const Text(
                    'Pagos e historial de movimientos.',
                    style: TextStyle(fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MoneyActivityScreen(uid: user.uid),
                      ),
                    );
                  },
                ),

                ListTile(
                  leading: const Icon(Icons.vpn_key_outlined),
                  title: const Text('Editar cuenta'),
                  subtitle: const Text(
                    'Nombre, alias, datos personales y más.',
                    style: TextStyle(fontSize: 12),
                  ),
                  onTap: () => _navigateToEditProfile(user.uid, data),
                ),

                // DATOS DE SEGURIDAD
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Datos de seguridad'),
                  subtitle: const Text(
                    'Nombre, teléfono y correo para recuperar tu cuenta.',
                    style: TextStyle(fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AccountSecurityScreen(uid: user.uid),
                      ),
                    );
                  },
                ),

                ListTile(
                  leading: const Icon(Icons.help_outline),
                  title: const Text('Ayuda y cuenta'),
                  subtitle: const Text(
                    'Ayuda, términos, contacto, eliminar cuenta.',
                    style: TextStyle(fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const HelpAccountScreen(),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 24),

                // ======================================================
                // BOTÓN CERRAR SESIÓN
                // ======================================================
                Center(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    onPressed: () async {
                      try {
                        await SignOutService.signOutHard();
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error al cerrar sesión: $e')),
                        );
                      }
                    },

                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text(
                      'Cerrar sesión',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
