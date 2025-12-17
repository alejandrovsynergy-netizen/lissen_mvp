import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error guardando datos: $e')));
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
