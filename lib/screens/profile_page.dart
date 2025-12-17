import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // para Clipboard
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';


import '../widgets/companion_rates_block.dart';
import 'edit_profile_screen.dart';
import 'gallery_screen.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ImagePicker _picker = ImagePicker();

  // ============================================================
  // Disponibilidad estructurada (días + horas)
  // (se precarga aquí para que ConfigScreen la use luego)
  // ============================================================
  List<int> _selectedDays = []; // 1–7 (L–D)
  int _startHour = 18;
  int _endHour = 22;
  bool _availabilityInitialized = false;
  bool _savingAvailability = false;

  // ============================================================
  // Generar código de compañera
  // ============================================================
  String _generateCompanionCodeLocal() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random.secure();
    final buffer = StringBuffer();
    for (int i = 0; i < 6; i++) {
      buffer.write(chars[rand.nextInt(chars.length)]);
    }
    return 'LIS-${buffer.toString()}';
  }

  Future<void> _ensureCompanionCode(
    String uid,
    Map<String, dynamic> data,
  ) async {
    final existing = (data['companionCode'] as String?)?.trim();
    if (existing != null && existing.isNotEmpty) {
      return;
    }

    try {
      final String newCode = _generateCompanionCodeLocal();
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'companionCode': newCode,
      }, SetOptions(merge: true));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generando código de compañera: $e')),
      );
    }
  }

  // ============================================================
  // Cambiar foto de perfil
  // ============================================================
  Future<void> _changeProfilePhoto() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final XFile? picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (picked == null) return;

    try {
      final storageRef = FirebaseStorage.instance.ref().child(
        'users/${user.uid}/profile_photo.jpg',
      );

      final bytes = await picked.readAsBytes();
      await storageRef.putData(bytes);
      final url = await storageRef.getDownloadURL();

      // Actualizar foto de perfil
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'photoUrl': url,
      }, SetOptions(merge: true));

      // ==========================================
      // También guardar la foto en la GALERÍA
      // ==========================================
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('gallery')
          .add({
            'url': url,
            'type': 'photo', // asumiendo que usas este campo
            'fromProfile': true,
            'createdAt': FieldValue.serverTimestamp(),
          });

      setState(() {}); // refrescar avatar
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error subiendo foto: $e')));
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
  // ============================================================
// Cerrar sesión “hard” (Firebase + providers)
// ============================================================
Future<void> _signOutHard() async {
  try {
    // 1) Cierra Google (si aplica)
    try { await GoogleSignIn().signOut(); } catch (_) {}
    try { await GoogleSignIn().disconnect(); } catch (_) {}

    // 2) Cierra Facebook (si aplica)
    try { await FacebookAuth.instance.logOut(); } catch (_) {}

    // 3) Cierra Firebase
    await FirebaseAuth.instance.signOut();

    // Nota: NO navegamos manualmente.
    // Tu app ya tiene un AuthGate que detecta el signOut y te manda al login.
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error al cerrar sesión: $e')),
    );
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

        // Código de compañera
        final companionCode = (data['companionCode'] as String?)?.trim() ?? '';

        // Disponibilidad estructurada (se usa en ConfigScreen)
        if (!_availabilityInitialized && role == 'companion') {
          final days = (data['availabilityDays'] as List<dynamic>?) ?? [];
          _selectedDays = days.map((e) => e as int).toList();
          _startHour = data['availabilityStartHour'] ?? 18;
          _endHour = data['availabilityEndHour'] ?? 22;
          _availabilityInitialized = true;
        }

        // Si es compañera, aseguramos que tenga un código
        if (role == 'companion') {
          _ensureCompanionCode(user.uid, data);
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
                              backgroundImage: photoUrl != null
                                  ? NetworkImage(photoUrl)
                                  : null,
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
                      await _signOutHard();
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

// ===================================================================
// PANTALLA: DATOS DE SEGURIDAD (NOMBRE REAL, TELÉFONO, CORREO)
// ===================================================================
class AccountSecurityScreen extends StatefulWidget {
  final String uid;

  const AccountSecurityScreen({super.key, required this.uid});

  @override
  State<AccountSecurityScreen> createState() => _AccountSecurityScreenState();
}

class _AccountSecurityScreenState extends State<AccountSecurityScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  late TextEditingController _nameC;
  late TextEditingController _phoneC;

  String _email = '';
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameC = TextEditingController();
    _phoneC = TextEditingController();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .get();

      final data = snap.data() ?? {};
      final name = (data['name'] as String?) ?? '';
      final phone = (data['phoneNumber'] as String?) ?? '';

      final currentUser = _auth.currentUser;
      _email = currentUser?.email ?? (data['email'] as String? ?? '');

      _nameC.text = name;
      _phoneC.text = phone;
    } catch (_) {
      // si falla, dejamos campos vacíos
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
    });

    try {
      await FirebaseFirestore.instance.collection('users').doc(widget.uid).set({
        'name': _nameC.text.trim(),
        'phoneNumber': _phoneC.text.trim(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Datos de seguridad actualizados.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error guardando datos: $e')));
    } finally {
      if (!mounted) return;
      setState(() {
        _saving = false;
      });
    }
  }

  @override
  void dispose() {
    _nameC.dispose();
    _phoneC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Datos de seguridad')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Datos de seguridad')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Estos datos se usan para identificarte y ayudarte a recuperar tu cuenta.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameC,
              decoration: const InputDecoration(
                labelText: 'Nombre completo',
                hintText: 'Ej. María López',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneC,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Número de teléfono',
                hintText: 'Ej. +52 1 55 1234 5678',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              readOnly: true,
              enabled: false,
              controller: TextEditingController(text: _email),
              decoration: const InputDecoration(
                labelText: 'Correo de la cuenta',
                helperText:
                    'Por seguridad, el correo no se puede cambiar directamente desde la app.',
                helperMaxLines: 3,
                suffixIcon: Icon(Icons.lock_outline, size: 18),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Si necesitas cambiar tu correo, contáctanos a soporte para realizar una verificación adicional.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save, size: 16),
              label: Text(_saving ? 'Guardando...' : 'Guardar cambios'),
            ),
          ],
        ),
      ),
    );
  }
}

// ===================================================================
// PANTALLA: CONFIGURACIÓN (ENGRANE)
// ===================================================================
class CompanionConfigScreen extends StatefulWidget {
  final String uid;
  final bool isCompanion;

  const CompanionConfigScreen({
    super.key,
    required this.uid,
    required this.isCompanion,
  });

  @override
  State<CompanionConfigScreen> createState() => _CompanionConfigScreenState();
}

class _CompanionConfigScreenState extends State<CompanionConfigScreen> {
  List<int> _selectedDays = [];
  int _startHour = 18;
  int _endHour = 22;
  bool _availabilityInitialized = false;
  bool _savingAvailability = false;

  bool _savingRates = false;

  Future<void> _saveAvailability() async {
    setState(() {
      _savingAvailability = true;
    });

    try {
      await FirebaseFirestore.instance.collection('users').doc(widget.uid).set({
        'availabilityDays': _selectedDays,
        'availabilityStartHour': _startHour,
        'availabilityEndHour': _endHour,
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Disponibilidad actualizada.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error guardando disponibilidad: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _savingAvailability = false;
      });
    }
  }

  /// Marca las tarifas como confirmadas por la compañera.
  Future<void> _saveRates() async {
    setState(() {
      _savingRates = true;
    });

    try {
      await FirebaseFirestore.instance.collection('users').doc(widget.uid).set({
        'ratesLastConfirmedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tarifas guardadas y confirmadas.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error guardando tarifas: $e')));
    } finally {
      if (!mounted) return;
      setState(() {
        _savingRates = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isCompanion) {
      return Scaffold(
        appBar: AppBar(title: const Text('Configuración')),
        body: const Center(
          child: Text(
            'Configuración avanzada disponible solo para cuentas de compañera.',
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(widget.uid)
            .snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snap.data!.data() ?? {};
          final companionCode =
              (data['companionCode'] as String?)?.trim() ?? '';

          if (!_availabilityInitialized) {
            final days = (data['availabilityDays'] as List<dynamic>?) ?? [];
            _selectedDays = days.map((e) => e as int).toList();
            _startHour = data['availabilityStartHour'] ?? 18;
            _endHour = data['availabilityEndHour'] ?? 22;
            _availabilityInitialized = true;
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // CÓDIGO DE COMPAÑERA
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Código de compañera',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Comparte este código con hablantes para que sus ofertas '
                          'sean dirigidas solo a ti.',
                          style: TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  color: Colors.grey.shade900,
                                ),
                                child: Text(
                                  companionCode.isEmpty
                                      ? 'Generando código...'
                                      : companionCode,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    letterSpacing: 1.2,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: companionCode.isEmpty
                                  ? null
                                  : () async {
                                      await Clipboard.setData(
                                        ClipboardData(text: companionCode),
                                      );
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('Código copiado.'),
                                        ),
                                      );
                                    },
                              icon: const Icon(Icons.copy),
                              tooltip: 'Copiar código',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // DISPONIBILIDAD
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Disponibilidad típica',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Selecciona los días y el rango de horas en que sueles estar disponible.',
                          style: TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: List.generate(7, (index) {
                            final dayNumber = index + 1;
                            final labels = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
                            final isSelected = _selectedDays.contains(
                              dayNumber,
                            );

                            return ChoiceChip(
                              label: Text(labels[index]),
                              selected: isSelected,
                              onSelected: (val) {
                                setState(() {
                                  if (val) {
                                    _selectedDays.add(dayNumber);
                                  } else {
                                    _selectedDays.remove(dayNumber);
                                  }
                                });
                              },
                            );
                          }),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Text('Desde'),
                            const SizedBox(width: 8),
                            DropdownButton<int>(
                              value: _startHour,
                              items: List.generate(24, (i) {
                                return DropdownMenuItem(
                                  value: i,
                                  child: Text('$i:00'),
                                );
                              }),
                              onChanged: (val) {
                                if (val == null) return;
                                setState(() {
                                  _startHour = val;
                                });
                              },
                            ),
                            const SizedBox(width: 16),
                            const Text('Hasta'),
                            const SizedBox(width: 8),
                            DropdownButton<int>(
                              value: _endHour,
                              items: List.generate(24, (i) {
                                return DropdownMenuItem(
                                  value: i,
                                  child: Text('$i:00'),
                                );
                              }),
                              onChanged: (val) {
                                if (val == null) return;
                                setState(() {
                                  _endHour = val;
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton.icon(
                            onPressed: _savingAvailability
                                ? null
                                : _saveAvailability,
                            icon: _savingAvailability
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save, size: 16),
                            label: Text(
                              _savingAvailability
                                  ? 'Guardando...'
                                  : 'Guardar disponibilidad',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // TARIFAS BASE + BOTÓN GUARDAR
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tarifas base',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Ajusta tus tarifas y presiona "Guardar tarifas" para que los cambios cuenten.',
                          style: TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        const CompanionRatesBlock(),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton.icon(
                            onPressed: _savingRates ? null : () => _saveRates(),
                            icon: _savingRates
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save, size: 16),
                            label: Text(
                              _savingRates ? 'Guardando...' : 'Guardar tarifas',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ===================================================================
// PANTALLA: DINERO Y ACTIVIDAD
// ===================================================================
// ===================================================================
// PANTALLA: DINERO Y ACTIVIDAD
// ===================================================================
class MoneyActivityScreen extends StatefulWidget {
  final String uid;

  const MoneyActivityScreen({super.key, required this.uid});

  @override
  State<MoneyActivityScreen> createState() => _MoneyActivityScreenState();
}

class _MoneyActivityScreenState extends State<MoneyActivityScreen> {
  // 0 = Métodos de pago (Stripe), 1 = Historial
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dinero y actividad')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(widget.uid)
            .snapshots(),
        builder: (context, userSnap) {
          if (userSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final userData = userSnap.data?.data() ?? {};

          // Rol del usuario para controlar lo que se muestra
          final String role = (userData['role'] as String?) ?? '';
          final bool isCompanion = role == 'companion';
          final bool isSpeaker = role == 'speaker';

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() => _selectedTab = 0);
                        },
                        child: const Text('Métodos de pago'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() => _selectedTab = 1);
                        },
                        child: const Text('Historial de pagos'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _selectedTab == 0
                      ? _buildStripeConfig(
                          userData,
                          isSpeaker: isSpeaker,
                          isCompanion: isCompanion,
                        )
                      : _buildPaymentsHistory(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ============================================================
  // SECCIÓN "MÉTODOS DE PAGO" (estructura pensada para Stripe)
  // ============================================================
  Widget _buildStripeConfig(
    Map<String, dynamic> userData, {
    required bool isSpeaker,
    required bool isCompanion,
  }) {
    // Estos campos se llenarán desde tu backend cuando Stripe esté integrado.
    final stripeCustomerId = (userData['stripeCustomerId'] as String?)
        ?.trim(); // hablante
    final stripeAccountId = (userData['stripeAccountId'] as String?)
        ?.trim(); // compañera
    final chargesEnabled = userData['stripeChargesEnabled'] as bool?;
    final payoutsEnabled = userData['stripePayoutsEnabled'] as bool?;
    final defaultPmBrand = (userData['stripeDefaultPmBrand'] as String?)
        ?.trim();
    final defaultPmLast4 = (userData['stripeDefaultPmLast4'] as String?)
        ?.trim();

    // Estados legibles:
    String _statusPagosComoHablante() {
      if (stripeCustomerId == null || stripeCustomerId.isEmpty) {
        return 'Aún no tienes un método de pago registrado.';
      }
      final enabledText = chargesEnabled == true
          ? 'Cobros habilitados'
          : 'Cobros pendientes';
      if (defaultPmBrand != null && defaultPmLast4 != null) {
        return '$enabledText • $defaultPmBrand • **** $defaultPmLast4';
      }
      return enabledText;
    }

    String _statusCobrosComoCompanera() {
      if (stripeAccountId == null || stripeAccountId.isEmpty) {
        return 'Aún no tienes una cuenta de cobro conectada.';
      }
      final payoutsText = payoutsEnabled == true
          ? 'Retiros habilitados'
          : 'Retiros pendientes';
      return '$payoutsText • Cuenta conectada: $stripeAccountId';
    }

    final bool noRoleDefined = !isSpeaker && !isCompanion;

    final List<Widget> children = [
      const Text(
        'Desde aquí vas a manejar tus cobros y pagos reales. '
        'Cuando conectemos Stripe, esta pantalla usará estos mismos bloques '
        'para mostrar tu información actualizada.',
        style: TextStyle(fontSize: 14),
      ),
      const SizedBox(height: 16),
    ];

    // ==========================
    // BLOQUE: PAGOS COMO HABLANTE
    // ==========================
    if (isSpeaker || noRoleDefined) {
      children.addAll([
        const Text(
          'Pagos como hablante',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Método de pago para tus sesiones como hablante.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.credit_card, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        stripeCustomerId == null || stripeCustomerId.isEmpty
                            ? 'Sin tarjeta guardada.'
                            : _statusPagosComoHablante(),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      // Aquí en el futuro vas a disparar el flujo real de Stripe
                      // (PaymentSheet / SetupIntent / backend).
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'La conexión con Stripe se activará en una etapa posterior.',
                          ),
                        ),
                      );
                    },
                    child: const Text(
                      'Configurar método de pago',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
      ]);
    }

    // ==============================
    // BLOQUE: COBROS COMO COMPAÑERA
    // ==============================
    if (isCompanion || noRoleDefined) {
      children.addAll([
        const Text(
          'Cobros como compañera',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cuenta donde recibirás el dinero de tus sesiones.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.account_balance_wallet_outlined, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _statusCobrosComoCompanera(),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      // Aquí en el futuro vas a disparar el onboarding de Stripe Connect.
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'La conexión de cuenta para recibir dinero se activará cuando Stripe esté integrado.',
                          ),
                        ),
                      );
                    },
                    child: const Text(
                      'Conectar cuenta para recibir dinero',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
      ]);
    }

    children.add(
      const Text(
        'Cuando Stripe esté listo, estos mismos botones abrirán las pantallas '
        'oficiales para agregar tu tarjeta o conectar tu cuenta bancaria.',
        style: TextStyle(fontSize: 12),
      ),
    );

    return ListView(
      key: const ValueKey('metodos_pago'),
      padding: const EdgeInsets.all(16),
      children: children,
    );
  }

  // ============================================================
  // SECCIÓN "HISTORIAL DE PAGOS"
  // (la dejo igual que la tienes ahora)
  // ============================================================
  Widget _buildPaymentsHistory() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      key: const ValueKey('historial_pagos'),
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .collection('payments')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data?.docs ?? [];

        if (docs.isEmpty) {
          return const Center(
            child: Text(
              'No hay movimientos registrados.',
              style: TextStyle(fontSize: 15),
              textAlign: TextAlign.center,
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(height: 8),
          itemBuilder: (context, index) {
            final p = docs[index].data();

            final num amountCents = p['amountCents'] ?? 0;
            final String currency = (p['currency'] ?? 'MXN') as String;
            final String type = (p['type'] ?? 'sesión') as String;
            final String direction =
                (p['direction'] ?? 'payout') as String; // payout / charge
            final String status =
                (p['status'] ?? 'pendiente') as String; // pagado / pendiente

            final ts = p['createdAt'];
            DateTime? date;
            if (ts is Timestamp) date = ts.toDate();

            final sign = direction == 'charge' ? '-' : '+';
            final amount = amountCents / 100.0;

            final dateStr = date != null
                ? '${date.day.toString().padLeft(2, '0')}/'
                      '${date.month.toString().padLeft(2, '0')}/'
                      '${date.year}'
                : '';

            return ListTile(
              dense: true,
              leading: Icon(
                direction == 'charge' ? Icons.call_made : Icons.call_received,
                color: direction == 'charge' ? Colors.redAccent : Colors.green,
              ),
              title: Text(
                '$sign\$${amount.toStringAsFixed(2)} $currency',
                style: const TextStyle(fontSize: 15),
              ),
              subtitle: Text(
                '$type • $status${dateStr.isNotEmpty ? ' • $dateStr' : ''}',
                style: const TextStyle(fontSize: 12),
              ),
            );
          },
        );
      },
    );
  }
}

// ===================================================================
// PANTALLA: MÉTODOS DE PAGO (PLACEHOLDER)
// (La dejamos por compatibilidad, pero ya no es necesaria si usas
// solo MoneyActivityScreen con tabs.)
// ===================================================================
class PaymentMethodsScreen extends StatelessWidget {
  const PaymentMethodsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Métodos de pago')),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: Text(
            'Aquí podrás conectar tu cuenta bancaria o tarjeta '
            'para cobrar tus sesiones.\n\n'
            'Esta sección estará disponible próximamente.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14),
          ),
        ),
      ),
    );
  }
}

// ===================================================================
// PANTALLA: HISTORIAL DE PAGOS (ya cubierta dentro de MoneyActivity,
// la dejamos por compatibilidad si en algún punto la llamas directo)
// ===================================================================
class PaymentsHistoryScreen extends StatefulWidget {
  final String uid;

  const PaymentsHistoryScreen({super.key, required this.uid});

  @override
  State<PaymentsHistoryScreen> createState() => _PaymentsHistoryScreenState();
}

class _PaymentsHistoryScreenState extends State<PaymentsHistoryScreen> {
  // Filtro por fecha: últimos 7 días, 30 días, o todo
  String _dateFilter = '30'; // '7', '30', 'all'

  bool _isWithinDateFilter(Timestamp? ts) {
    if (ts == null) return false;
    if (_dateFilter == 'all') return true;

    final date = ts.toDate();
    final now = DateTime.now();
    final days = _dateFilter == '7' ? 7 : 30;
    final limit = now.subtract(Duration(days: days));
    return date.isAfter(limit);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historial de pagos')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(widget.uid)
            .snapshots(),
        builder: (context, userSnap) {
          if (userSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final userData = userSnap.data?.data() ?? {};
          final String role = (userData['role'] as String?) ?? '';

          final bool isCompanion = role == 'companion';
          final bool isSpeaker = role == 'speaker';

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(widget.uid)
                .collection('payments')
                .orderBy('createdAt', descending: true)
                .limit(200)
                .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snap.data?.docs ?? [];

              // Filtramos por:
              // - dirección según rol
              // - rango de fechas
              final filtered = docs.where((doc) {
                final p = doc.data();

                final String direction =
                    (p['direction'] ?? '') as String; // 'payout' o 'charge'
                final ts = p['createdAt'];
                if (ts is! Timestamp) return false;
                if (!_isWithinDateFilter(ts)) return false;

                if (isCompanion) {
                  // Compañera: solo pagos que ella ha recibido
                  return direction == 'payout';
                } else if (isSpeaker) {
                  // Hablante: solo pagos que él ha hecho
                  return direction == 'charge';
                } else {
                  // Rol raro / indefinido: mostramos todo
                  return true;
                }
              }).toList();

              // Cálculo de total según rol
              num totalCents = 0;
              for (final doc in filtered) {
                final p = doc.data();
                final num amountCents = p['amountCents'] ?? 0;
                totalCents += amountCents;
              }

              double _toAmount(num cents) => (cents / 100.0).toDouble();

              final String summaryLabel = isCompanion
                  ? 'Total ganado en este periodo'
                  : isSpeaker
                  ? 'Total pagado en este periodo'
                  : 'Total en este periodo';

              final String summaryValue =
                  '\$${_toAmount(totalCents).toStringAsFixed(2)} MXN';

              return Column(
                children: [
                  // =================== RESUMEN SUPERIOR ===================
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            summaryLabel,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            summaryValue,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // =================== FILTRO POR FECHA ===================
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('7 días'),
                          selected: _dateFilter == '7',
                          onSelected: (_) {
                            setState(() => _dateFilter = '7');
                          },
                        ),
                        ChoiceChip(
                          label: const Text('30 días'),
                          selected: _dateFilter == '30',
                          onSelected: (_) {
                            setState(() => _dateFilter = '30');
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Todo'),
                          selected: _dateFilter == 'all',
                          onSelected: (_) {
                            setState(() => _dateFilter = 'all');
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  // =================== LISTA DE MOVIMIENTOS ===================
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(
                            child: Text(
                              'No hay registros en este periodo.',
                              style: TextStyle(fontSize: 14),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(8),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 8),
                            itemBuilder: (context, index) {
                              final p = filtered[index].data();

                              final num amountCents = p['amountCents'] ?? 0;
                              final String currency =
                                  (p['currency'] ?? 'MXN') as String;
                              final String type =
                                  (p['type'] ?? 'sesión') as String;
                              final String status =
                                  (p['status'] ?? 'pendiente') as String;
                              final String direction =
                                  (p['direction'] ?? '') as String;

                              final ts = p['createdAt'];
                              DateTime? date;
                              if (ts is Timestamp) {
                                date = ts.toDate();
                              }

                              final double amount = _toAmount(amountCents);
                              final String sign = direction == 'charge'
                                  ? '-'
                                  : '+';

                              final String dateStr = date != null
                                  ? '${date.day.toString().padLeft(2, '0')}/'
                                        '${date.month.toString().padLeft(2, '0')}/'
                                        '${date.year}'
                                  : '';

                              final bool isIncome = direction == 'payout';

                              return ListTile(
                                dense: true,
                                leading: Icon(
                                  isIncome
                                      ? Icons.call_received
                                      : Icons.call_made,
                                  color: isIncome
                                      ? Colors.green
                                      : Colors.redAccent,
                                ),
                                title: Text(
                                  '$sign\$${amount.toStringAsFixed(2)} $currency',
                                  style: const TextStyle(fontSize: 15),
                                ),
                                subtitle: Text(
                                  '$type • $status'
                                  '${dateStr.isNotEmpty ? ' • $dateStr' : ''}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// ===================================================================
// PANTALLA: AYUDA Y CUENTA
// ===================================================================
class HelpAccountScreen extends StatelessWidget {
  const HelpAccountScreen({super.key});

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
          final List<String> blockedUsers =
              (data['blockedUsers'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [];

          return ListView(
            children: [
              // ================== USUARIOS BLOQUEADOS ==================
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
                  ),
                ),

              if (blockedUsers.isNotEmpty) const Divider(height: 8),

              // ================== RESTO DE OPCIONES ==================
              const ListTile(
                leading: Icon(Icons.chat_bubble_outline),
                title: Text('Ayuda y sugerencias'),
                subtitle: Text(
                  'Cuéntanos si tienes problemas o ideas para mejorar Lissen.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const Divider(height: 8),
              const ListTile(
                leading: Icon(Icons.description_outlined),
                title: Text('Términos y condiciones'),
                subtitle: Text(
                  'Lee los términos bajo los cuales funciona Lissen.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const Divider(height: 8),
              const ListTile(
                leading: Icon(Icons.privacy_tip_outlined),
                title: Text('Política de privacidad'),
                subtitle: Text(
                  'Conoce cómo protegemos tu información.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const Divider(height: 8),
              const ListTile(
                leading: Icon(Icons.email_outlined),
                title: Text('Información de contacto'),
                subtitle: Text(
                  'Escríbenos si necesitas soporte más detallado.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const Divider(height: 8),
              const ListTile(
                leading: Icon(Icons.delete_forever_outlined),
                title: Text(
                  'Eliminar cuenta',
                  style: TextStyle(color: Colors.red),
                ),
                subtitle: Text(
                  'Esta opción estará disponible próximamente.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
