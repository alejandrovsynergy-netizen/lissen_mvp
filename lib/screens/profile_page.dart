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
        builder: (context) => EditProfileScreen(uid: uid, initialData: userData),
      ),
    );
  }

  // ============================================================
  // Navegar a GALERÍA
  // ============================================================
  void _openGallery(String uid) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => GalleryScreen(uid: uid)),
    );
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
      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
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

        final theme = Theme.of(context);
        final cs = theme.colorScheme;

        // Colores "tipo preview" (solo visual)
        const emeraldA = Color(0xFF10B981);
        const emeraldB = Color(0xFF047857);
        const emeraldBorder = Color(0xFF34D399);

        final subtleWhite = cs.onBackground.withOpacity(0.78);
        final dimWhite = cs.onBackground.withOpacity(0.55);

        return Scaffold(
          // ✅ deja ver el fondo global detrás
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            centerTitle: true,
            title: const SizedBox.shrink(),
            elevation: 0,
            scrolledUnderElevation: 0,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ======================================================
                  // HEADER (flotando sobre el fondo)
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
                              child: Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [emeraldA, emeraldB],
                                  ),
                                  border: Border.all(
                                    color: emeraldBorder.withOpacity(0.40),
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: emeraldA.withOpacity(0.30),
                                      blurRadius: 18,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(2),
                                  child: ClipOval(
                                    child: CircleAvatar(
                                      backgroundColor: Colors.transparent,
                                      backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                                      child: photoUrl == null
                                          ? const Icon(Icons.person, size: 34, color: Colors.white)
                                          : null,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayName,
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      color: cs.onBackground,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  if (age != 'null' && age != '—')
                                    Text(
                                      '$age años',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: subtleWhite,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  if (user.email != null && user.email!.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      user.email!,
                                      style: theme.textTheme.bodySmall?.copyWith(color: dimWhite),
                                    ),
                                  ],
                                  if (role.isNotEmpty || gender.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      '${role.isNotEmpty ? _roleLabel(role) : ''}'
                                      '${role.isNotEmpty && gender.isNotEmpty ? ' · ' : ''}'
                                      '${gender.isNotEmpty ? _genderLabel(gender) : ''}',
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: subtleWhite,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                  if (city != '—' || country != '—') ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      '$city, $country',
                                      style: theme.textTheme.labelSmall?.copyWith(color: dimWhite),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              decoration: BoxDecoration(
                                color: emeraldA.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: emeraldA.withOpacity(0.20), width: 1),
                              ),
                              child: IconButton(
                                onPressed: () => _openGallery(user.uid),
                                icon: Icon(Icons.collections_outlined, color: emeraldA.withOpacity(0.90)),
                                tooltip: 'Galería de fotos',
                              ),
                            ),
                          ],
                        ),
                        if (bio.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Biografía',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: cs.onBackground,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            bio,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onBackground.withOpacity(0.80),
                              height: 1.35,
                            ),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),

                  // ======================================================
                  // MENÚ PRINCIPAL (misma lógica / mismos onTap)
                  // ======================================================
                  ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: emeraldA.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.settings_outlined, color: emeraldA.withOpacity(0.90)),
                    ),
                    title: Text(
                      'Configuración',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onBackground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      role == 'companion'
                          ? 'Disponibilidad, tarifas y código de compañera.'
                          : 'Preferencias generales de uso.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onBackground.withOpacity(0.70),
                      ),
                    ),
                    trailing: Icon(Icons.chevron_right, color: cs.onBackground.withOpacity(0.45)),
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
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: emeraldA.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.attach_money, color: emeraldA.withOpacity(0.90)),
                    ),
                    title: Text(
                      'Dinero y actividad',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onBackground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      'Pagos e historial de movimientos.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onBackground.withOpacity(0.70),
                      ),
                    ),
                    trailing: Icon(Icons.chevron_right, color: cs.onBackground.withOpacity(0.45)),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MoneyActivityScreen(uid: user.uid),
                        ),
                      );
                    },
                  ),

                  ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: emeraldA.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.vpn_key_outlined, color: emeraldA.withOpacity(0.90)),
                    ),
                    title: Text(
                      'Editar cuenta',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onBackground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      'Nombre, alias, datos personales y más.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onBackground.withOpacity(0.70),
                      ),
                    ),
                    trailing: Icon(Icons.chevron_right, color: cs.onBackground.withOpacity(0.45)),
                    onTap: () => _navigateToEditProfile(user.uid, data),
                  ),

                  ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: emeraldA.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.lock_outline, color: emeraldA.withOpacity(0.90)),
                    ),
                    title: Text(
                      'Datos de seguridad',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onBackground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      'Nombre, teléfono y correo para recuperar tu cuenta.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onBackground.withOpacity(0.70),
                      ),
                    ),
                    trailing: Icon(Icons.chevron_right, color: cs.onBackground.withOpacity(0.45)),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AccountSecurityScreen(uid: user.uid),
                        ),
                      );
                    },
                  ),

                  ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: emeraldA.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.help_outline, color: emeraldA.withOpacity(0.90)),
                    ),
                    title: Text(
                      'Ayuda y cuenta',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onBackground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      'Ayuda, términos, contacto, eliminar cuenta.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onBackground.withOpacity(0.70),
                      ),
                    ),
                    trailing: Icon(Icons.chevron_right, color: cs.onBackground.withOpacity(0.45)),
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
                  // BOTÓN CERRAR SESIÓN (misma lógica)
                  // ======================================================
                  Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFEF4444).withOpacity(0.30),
                            blurRadius: 18,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
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
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
