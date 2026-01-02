import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EditProfileScreen extends StatefulWidget {
  final String uid;
  final Map<String, dynamic>? initialData;

  const EditProfileScreen({
    super.key,
    required this.uid,
    required this.initialData,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _aliasC;
  late TextEditingController _ageC;
  late TextEditingController _countryC;
  late TextEditingController _cityC;
  late TextEditingController _bioC;

  String? _role;
  String? _gender;
  String? _preferredGender;

  bool _saving = false;
  String? _error;

  // ============================================================
  // SUGERENCIAS DE BIOGRAFÍA POR ROL
  // ============================================================

  // Hablante (speaker)
  final List<String> _speakerBioSuggestions = [
    'Busco conversaciones directas y con contenido. Me interesa aprender de otras perspectivas y respetar el tiempo de ambos.',
    'Me gusta platicar con buena vibra, pero también sé ponerme serio cuando el tema lo amerita.',
    'Prefiero la honestidad, aunque incomode un poco, a las pláticas falsas o llenas de pose.',
    'Me interesa entender cómo piensan los demás y cuestionar mis propias ideas.',
    'Me gusta combinar humor y sentido común para hablar de temas reales, no de apariencias.',
    'Podemos hablar de relaciones, trabajo, decisiones difíciles o simplemente del día a día.',
    'A veces solo necesito alguien que escuche sin juzgar y dé un punto de vista claro.',
    'No busco drama, busco conversación inteligente y respetuosa.',
    'Puedo ser serio o relajado según el tema; lo importante es que la conversación tenga sentido.',
    'Si quieres hablar sin filtros pero con respeto, aquí hay espacio para eso.',
  ];

  // Compañera (companion)
  final List<String> _companionBioSuggestions = [
    'Ofrezco un espacio de conversación tranquilo, respetuoso y sin juicios.',
    'Soy relajada, hablo claro y valoro a las personas que respetan el tiempo y los límites.',
    'Me gusta reír, platicar de todo un poco y hacer que la charla se sienta ligera.',
    'Puedo escuchar lo que traes en la cabeza y ayudarte a ver las cosas desde otro ángulo.',
    'No busco novelas, prefiero conversaciones honestas y con buena comunicación.',
    'Me adapto al tono de la persona: seria, casual o muy platicadora, según lo que necesites.',
    'Podemos hablar de relaciones, metas, trabajo, emociones o simplemente pasar el rato.',
    'Me interesa que te sientas cómodo para decir lo que realmente piensas.',
    'Si traes la mente cargada, aquí puedes desahogarte con calma y sin drama.',
    'Soy directa, respetuosa y real; la idea es que la conversación te deje algo útil.',
  ];

  int _bioSuggestionIndex = -1;

  void _applyNextBioSuggestion() {
    final bool isCompanion = _role == 'companion';
    final List<String> list = isCompanion
        ? _companionBioSuggestions
        : _speakerBioSuggestions;

    if (list.isEmpty) return;

    setState(() {
      _bioSuggestionIndex = (_bioSuggestionIndex + 1) % list.length;
      final suggestion = list[_bioSuggestionIndex];

      _bioC.text = suggestion;
      _bioC.selection = TextSelection.fromPosition(
        TextPosition(offset: _bioC.text.length),
      );
    });
  }

  @override
  void initState() {
    super.initState();
    final d = widget.initialData ?? {};

    _aliasC = TextEditingController(text: d['alias'] ?? '');
    _ageC = TextEditingController(
      text: d['age'] != null ? d['age'].toString() : '',
    );
    _countryC = TextEditingController(text: d['country'] ?? '');
    _cityC = TextEditingController(text: d['city'] ?? '');
    _bioC = TextEditingController(text: d['bio'] ?? '');

    _role = d['role'] as String?;
    _gender = d['gender'] as String?;
    _preferredGender = d['preferredGender'] as String? ?? 'todos';
  }

  Future<bool> _isAliasTaken(String alias) async {
    final normalized = alias.trim().toLowerCase();
    if (normalized.isEmpty) return false;

    final byLower = await FirebaseFirestore.instance
        .collection('users')
        .where('aliasLower', isEqualTo: normalized)
        .limit(1)
        .get();
    if (byLower.docs.isNotEmpty) {
      final docId = byLower.docs.first.id;
      return docId != widget.uid;
    }

    final byExact = await FirebaseFirestore.instance
        .collection('users')
        .where('alias', isEqualTo: alias.trim())
        .limit(1)
        .get();
    if (byExact.docs.isNotEmpty) {
      final docId = byExact.docs.first.id;
      return docId != widget.uid;
    }

    return false;
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

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

      // Validaciones similares al onboarding
      if (alias.length < 3) {
        throw 'El alias debe tener al menos 3 caracteres.';
      }
      if (await _isAliasTaken(alias)) {
        throw 'El alias ya esta en uso.';
      }
      if (_role == null) {
        throw 'Debes elegir tu rol.';
      }
      if (_gender == null) {
        throw 'Debes elegir tu género.';
      }
      if (age == null || age < 18 || age > 90) {
        throw 'Escribe una edad válida (entre 18 y 90).';
      }
      if (country.isEmpty || city.isEmpty) {
        throw 'Escribe país y ciudad.';
      }
      if (_preferredGender == null) {
        throw 'Elige con quién prefieres hablar.';
      }

      await FirebaseFirestore.instance.collection('users').doc(widget.uid).set({
        'alias': alias,
        'aliasLower': alias.toLowerCase(),
        'age': age,
        'country': country,
        'city': city,
        'bio': bio,
        'role': _role,
        'gender': _gender,
        'preferredGender': _preferredGender ?? 'todos',
        'targetGender': _preferredGender ?? 'todos', // compatibilidad
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _roleLabel(String? role) {
    switch (role) {
      case 'speaker':
        return 'Hablante (cliente)';
      case 'companion':
        return 'Compañera';
      default:
        return 'Sin rol definido';
    }
  }

  @override
  Widget build(BuildContext context) {
    final roleLabel = _roleLabel(_role);

    return Scaffold(
      appBar: AppBar(title: const Text('Editar perfil')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // Alias
              TextFormField(
                controller: _aliasC,
                decoration: const InputDecoration(
                  labelText: 'Alias',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().length < 3) {
                    return 'Alias muy corto';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Rol (solo lectura)
              TextFormField(
                readOnly: true,
                enabled: false,
                initialValue: roleLabel,
                decoration: const InputDecoration(
                  labelText: 'Rol',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // Género
              DropdownButtonFormField<String>(
                value: _gender,
                decoration: const InputDecoration(
                  labelText: 'Tu género',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'hombre', child: Text('Hombre')),
                  DropdownMenuItem(value: 'mujer', child: Text('Mujer')),
                  DropdownMenuItem(
                    value: 'otro',
                    child: Text('No binario / Otro'),
                  ),
                  DropdownMenuItem(
                    value: 'nsnc',
                    child: Text('Prefiero no decir'),
                  ),
                ],
                onChanged: (v) => setState(() => _gender = v),
              ),
              const SizedBox(height: 12),

              // Edad
              TextFormField(
                controller: _ageC,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Edad',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Escribe tu edad';
                  }
                  final n = int.tryParse(v.trim());
                  if (n == null || n < 18 || n > 90) {
                    return 'Edad inválida (18–90)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // País
              TextFormField(
                controller: _countryC,
                decoration: const InputDecoration(
                  labelText: 'País',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Escribe tu país';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Ciudad
              TextFormField(
                controller: _cityC,
                decoration: const InputDecoration(
                  labelText: 'Ciudad',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Escribe tu ciudad';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Biografía con botón de "Sugerencias"
              TextFormField(
                controller: _bioC,
                maxLines: 4,
                style: const TextStyle(
                  fontStyle: FontStyle.italic, // estilo distinto SOLO en bio
                ),
                decoration: InputDecoration(
                  labelText: 'Biografía (opcional)',
                  helperText:
                      'Si no sabes qué escribir, toca "Sugerencias" y luego edita a tu gusto.',
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                  suffixIcon: TextButton(
                    onPressed: _applyNextBioSuggestion,
                    child: const Text(
                      'Sugerencias',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Preferred gender
              DropdownButtonFormField<String>(
                value: _preferredGender,
                decoration: const InputDecoration(
                  labelText: '¿Con quién quieres hablar?',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'hombres', child: Text('Hombres')),
                  DropdownMenuItem(value: 'mujeres', child: Text('Mujeres')),
                  DropdownMenuItem(
                    value: 'nobinario',
                    child: Text('No binario'),
                  ),
                  DropdownMenuItem(value: 'todos', child: Text('Todos')),
                ],
                onChanged: (v) => setState(() => _preferredGender = v),
              ),
              const SizedBox(height: 16),

              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 8),
              ],

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Guardar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
