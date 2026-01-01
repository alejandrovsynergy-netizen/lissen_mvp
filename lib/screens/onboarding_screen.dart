import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:geocoding/geocoding.dart';

import 'onboarding/onboarding_ui.dart';
import 'onboarding/steps/role_step.dart';
import 'onboarding/steps/role_clarifications_step.dart';
import 'onboarding/steps/basic_info_step.dart';
import 'onboarding/steps/gender_prefs_step.dart';
import 'onboarding/steps/location_step.dart';
import 'onboarding/steps/terms_step.dart';
import 'onboarding/steps/finish_step.dart';

class OnboardingScreen extends StatefulWidget {
  final String uid;
  final Map<String, dynamic>? initialData;

  const OnboardingScreen({super.key, required this.uid, this.initialData});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  bool _saving = false;
  String? _error;

  // Campos principales
  final TextEditingController _aliasC = TextEditingController();
  final TextEditingController _ageC = TextEditingController();
  final TextEditingController _countryC = TextEditingController();
  final TextEditingController _cityC = TextEditingController();
  final TextEditingController _bioC = TextEditingController();

  String? _role; // speaker / companion
  String? _gender; // hombre / mujer / otro / nsnc
  bool _termsAccepted = false;

  // aclaraciones según rol
  bool _roleClarificationsAccepted = false;

  // Preferencia
  String? _preferredGender; // hombres / mujeres / nobinario / todos

  // Geo
  double? _geoLat;
  double? _geoLng;
  bool _locLoading = false;
  String? _locError;

  // Foto
  String? _photoUrl;
  Uint8List? _photoBytes;
  bool _uploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    final d = widget.initialData ?? {};

    _aliasC.text = d['alias'] ?? '';
    _role = d['role'] as String?;
    _gender = d['gender'] as String?;
    _ageC.text = d['age']?.toString() ?? '';
    _countryC.text = d['country'] ?? '';
    _cityC.text = d['city'] ?? '';
    _bioC.text = d['bio'] ?? '';
    _termsAccepted = d['termsAccepted'] == true;

    _photoUrl = d['photoUrl'] as String?;

    _preferredGender = d['preferredGender'] as String?;
    final legacyTarget = d['targetGender'];
    if (_preferredGender == null && legacyTarget is String) {
      _preferredGender = legacyTarget;
    }

    _geoLat = (d['geoLat'] is num) ? (d['geoLat'] as num).toDouble() : null;
    _geoLng = (d['geoLng'] is num) ? (d['geoLng'] as num).toDouble() : null;

    // Si luego decides persistir esta bandera y leerla:
    // _roleClarificationsAccepted = d['roleClarificationsAccepted'] == true;

    _initLocation();
  }

  @override
  void dispose() {
    _aliasC.dispose();
    _ageC.dispose();
    _countryC.dispose();
    _cityC.dispose();
    _bioC.dispose();
    super.dispose();
  }

  // ============================================================
  // UBICACIÓN APROXIMADA + AUTOLLENADO
  // ============================================================
  Future<void> _initLocation() async {
    setState(() {
      _locLoading = true;
      _locError = null;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _locError =
              'La ubicación del dispositivo está desactivada. Puedes continuar, '
              'pero no podremos usar tu posición aproximada.';
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() {
          _locError =
              'No diste permiso de ubicación. Puedes continuar, pero no podremos '
              'usar tu posición aproximada.';
        });
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final double lat = pos.latitude;
      final double lng = pos.longitude;

      String? city;
      String? country;

      try {
        final placemarks = await placemarkFromCoordinates(lat, lng);
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          city = (p.locality != null && p.locality!.isNotEmpty)
              ? p.locality
              : p.subAdministrativeArea;
          country = p.country;
        }
      } catch (e) {
        debugPrint('Error en geocoding (no se pudo obtener ciudad/país): $e');
      }

      setState(() {
        _geoLat = lat;
        _geoLng = lng;
        _locError = null;

        _cityC.text = (city != null && city.isNotEmpty)
            ? city!
            : (_cityC.text.isEmpty ? 'Ubicación detectada' : _cityC.text);

        _countryC.text = (country != null && country.isNotEmpty)
            ? country!
            : (_countryC.text.isEmpty ? 'País no disponible' : _countryC.text);
      });
    } catch (e) {
      setState(() {
        _locError = 'Error obteniendo ubicación: $e';
      });
    } finally {
      if (mounted) setState(() => _locLoading = false);
    }
  }

  // ============================================================
  // FOTO
  // ============================================================
  Future<void> _pickProfilePhoto() async {
    try {
      setState(() => _error = null);

      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 75,
        maxWidth: 800,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      setState(() => _photoBytes = bytes);

      setState(() => _uploadingPhoto = true);

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('users')
          .child(widget.uid)
          .child('profile.jpg');

      await storageRef.putData(bytes);
      final url = await storageRef.getDownloadURL();

      setState(() => _photoUrl = url);
    } catch (e) {
      setState(() {
        _error = 'Error subiendo foto: $e';
      });
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  // ============================================================
  // GUARDAR TODO (tu lógica)
  // ============================================================
  Future<void> _saveAll() async {
    if (_saving) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final alias = _aliasC.text.trim();
      final age = int.tryParse(_ageC.text.trim());
      final country = _countryC.text.trim();
      final city = _cityC.text.trim();
      final bio = _bioC.text.trim();

      if (alias.length < 3) throw 'El alias debe tener al menos 3 caracteres.';
      if (_role == null) throw 'Debes elegir tu rol.';
      if (!_roleClarificationsAccepted) {
        throw 'Debes aceptar las aclaraciones de tu rol.';
      }
      if (_gender == null) throw 'Debes elegir tu género.';
      if (age == null || age < 18 || age > 90) throw 'Escribe una edad válida.';
      if (country.isEmpty || city.isEmpty) throw 'Escribe país y ciudad.';
      if (_preferredGender == null) throw 'Elige con quién prefieres hablar.';
      if (!_termsAccepted) throw 'Debes aceptar los términos de uso.';
      if (_photoUrl == null || _photoUrl!.isEmpty) {
        throw 'Sube una foto de perfil para continuar.';
      }

      final data = <String, dynamic>{
        'uid': widget.uid,
        'alias': alias,
        'role': _role,
        'gender': _gender,
        'age': age,
        'country': country,
        'city': city,
        'bio': bio,
        'photoUrl': _photoUrl,
        'termsAccepted': _termsAccepted,
        'preferredGender': _preferredGender,
        'targetGender': _preferredGender, // compat
        'onboardingCompleted': true,
        'roleClarificationsAccepted': _roleClarificationsAccepted,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (_geoLat != null && _geoLng != null) {
        data['geoLat'] = _geoLat;
        data['geoLng'] = _geoLng;
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .set(data, SetOptions(merge: true));

      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ============================================================
  // UI PRINCIPAL (ahora con steps desacoplados)
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final steps = <Widget>[
      RoleStep(
        role: _role,
        onRoleSelected: (v) => setState(() => _role = v),
        onRoleChangedResetClarifications: () =>
            setState(() => _roleClarificationsAccepted = false),
      ),
      RoleClarificationsStep(
        role: _role,
        accepted: _roleClarificationsAccepted,
        onAcceptedChanged: (v) => setState(() => _roleClarificationsAccepted = v),
      ),
      BasicInfoStep(
        aliasC: _aliasC,
        ageC: _ageC,
        bioC: _bioC,
        role: _role,
        photoUrl: _photoUrl,
        photoBytes: _photoBytes,
        uploadingPhoto: _uploadingPhoto,
        onPickPhoto: _pickProfilePhoto,
      ),
      GenderPrefsStep(
        gender: _gender,
        preferredGender: _preferredGender,
        onGenderChanged: (v) => setState(() => _gender = v),
        onPreferredGenderChanged: (v) => setState(() => _preferredGender = v),
      ),
      LocationStep(
        cityC: _cityC,
        countryC: _countryC,
        locLoading: _locLoading,
        locError: _locError,
        geoLat: _geoLat,
        geoLng: _geoLng,
        onUseLocation: _initLocation,
      ),
      TermsStep(
        termsAccepted: _termsAccepted,
        onTermsChanged: (v) => setState(() => _termsAccepted = v),
      ),
      FinishStep(alias: _aliasC.text.trim()),
    ];

    final isLastStep = _step == steps.length - 1;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Completa tu perfil'),
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                OnboardingStepIndicator(current: _step, total: steps.length),
                const SizedBox(height: 24),
                Expanded(child: steps[_step]),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.error,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar:
          _buildNavigation(isLastStep: isLastStep, totalSteps: steps.length),
    );
  }

  // ============================================================
  // NAV BOTTOM (misma lógica que ya tienes)
  // ============================================================
  Widget _buildNavigation({required bool isLastStep, required int totalSteps}) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          if (_step > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: _saving
                    ? null
                    : () {
                        setState(() {
                          _error = null;
                          _step--;
                        });
                      },
                child: const Text('Atrás'),
              ),
            ),
          if (_step > 0) const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: _saving
                  ? null
                  : () {
                      setState(() => _error = null);

                      if (!isLastStep) {
                        if (_step == 0 && _role == null) {
                          setState(() => _error = 'Debes elegir tu rol para continuar.');
                          return;
                        }
                        if (_step == 1 && !_roleClarificationsAccepted) {
                          setState(() => _error = 'Debes aceptar las aclaraciones de tu rol.');
                          return;
                        }
                        if (_step == 2 && (_photoUrl == null || _photoUrl!.isEmpty)) {
                          setState(() => _error = 'Debes subir una foto de perfil para continuar.');
                          return;
                        }
                        if (_step == 4) {
                          final city = _cityC.text.trim();
                          final country = _countryC.text.trim();
                          if (city.isEmpty || country.isEmpty) {
                            setState(() => _error =
                                'Escribe tu ciudad y país, o usa el botón de ubicación para rellenarlos.');
                            return;
                          }
                        }

                        setState(() => _step++);
                      } else {
                        _saveAll();
                      }
                    },
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isLastStep ? 'Finalizar' : 'Siguiente'),
            ),
          ),
        ],
      ),
    );
  }
}
