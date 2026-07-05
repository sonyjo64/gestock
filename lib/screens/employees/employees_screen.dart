import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/database/db.dart';
import '../../core/utils/helpers.dart';
import '../../providers/auth_provider.dart';

class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  List<Map<String, dynamic>> _employees = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await DB.instance.getEmployees();
    if (mounted) setState(() { _employees = data; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.isAdmin) {
      return const Scaffold(body: Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text('Accès réservé aux administrateurs', style: TextStyle(color: Colors.grey)),
        ],
      )));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Employés (${_employees.length})'),
        actions: [
          ElevatedButton.icon(
            onPressed: () => _openForm(null),
            icon: const Icon(Icons.person_add),
            label: const Text('Nouvel employé'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _employees.isEmpty
              ? const Center(child: Text('Aucun employé'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemCount: _employees.length,
                  itemBuilder: (_, i) {
                    final e = _employees[i];
                    final role = e['role'] as String;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _roleColor(role).withOpacity(0.15),
                        child: Icon(Icons.person, color: _roleColor(role)),
                      ),
                      title: Text(e['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${e['username']} • PIN: ${e['pin'] ?? '—'}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Chip(
                            label: Text(_roleLabel(role), style: const TextStyle(fontSize: 11)),
                            backgroundColor: _roleColor(role).withOpacity(0.15),
                            side: BorderSide(color: _roleColor(role).withOpacity(0.4)),
                            padding: EdgeInsets.zero,
                          ),
                          const SizedBox(width: 8),
                          IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _openForm(e)),
                          if (e['username'] != 'admin')
                            IconButton(icon: const Icon(Icons.delete, size: 18, color: Colors.red), onPressed: () => _delete(e)),
                        ],
                      ),
                    );
                  },
                ),
    );
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'admin': return Colors.red;
      case 'manager': return Colors.blue;
      case 'cashier': return Colors.green;
      default: return Colors.grey;
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'admin': return 'Administrateur';
      case 'manager': return 'Manager';
      case 'cashier': return 'Caissier';
      default: return 'Staff';
    }
  }

  Future<void> _openForm(Map<String, dynamic>? employee) async {
    await showDialog(
      context: context,
      builder: (_) => _EmployeeFormDialog(employee: employee),
    );
    _load();
  }

  Future<void> _delete(Map<String, dynamic> e) async {
    final ok = await confirmDialog(context, 'Supprimer l\'employé', 'Supprimer "${e['name']}" ?');
    if (ok) { await DB.instance.deleteEmployee(e['id'] as int); _load(); }
  }
}

class _EmployeeFormDialog extends StatefulWidget {
  final Map<String, dynamic>? employee;
  const _EmployeeFormDialog({this.employee});

  @override
  State<_EmployeeFormDialog> createState() => _EmployeeFormDialogState();
}

class _EmployeeFormDialogState extends State<_EmployeeFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  String _role = 'cashier';
  Map<String, bool> _perms = {
    'pos': true, 'products': false, 'categories': false,
    'customers': false, 'suppliers': false, 'employees': false,
    'reports': false, 'banking': false, 'settings': false,
  };
  bool _saving = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    final e = widget.employee;
    if (e != null) {
      _nameCtrl.text = e['name'] as String;
      _userCtrl.text = e['username'] as String;
      _pinCtrl.text = e['pin'] as String? ?? '';
      _role = e['role'] as String;
      try {
        final p = jsonDecode(e['permissions'] as String? ?? '{}') as Map<String, dynamic>;
        _perms = _perms.map((k, _) => MapEntry(k, p[k] as bool? ?? false));
        if (_role == 'admin') _perms = _perms.map((k, _) => MapEntry(k, true));
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _userCtrl, _passCtrl, _pinCtrl]) c.dispose();
    super.dispose();
  }

  void _setRole(String role) {
    setState(() {
      _role = role;
      if (role == 'admin') {
        _perms = _perms.map((k, _) => MapEntry(k, true));
      } else if (role == 'cashier') {
        _perms = {
          'pos': true, 'products': false, 'categories': false,
          'customers': true, 'suppliers': false, 'employees': false,
          'reports': false, 'banking': false, 'settings': false,
        };
      } else if (role == 'manager') {
        _perms = {
          'pos': true, 'products': true, 'categories': true,
          'customers': true, 'suppliers': true, 'employees': false,
          'reports': true, 'banking': false, 'settings': false,
        };
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final data = {
      if (widget.employee?['id'] != null) 'id': widget.employee!['id'],
      'name': _nameCtrl.text.trim(),
      'username': _userCtrl.text.trim(),
      'password': _passCtrl.text,
      'pin': _pinCtrl.text.trim().isEmpty ? null : _pinCtrl.text.trim(),
      'role': _role,
      'permissions': jsonEncode(_perms),
    };
    await DB.instance.upsertEmployee(data, hashPwd: _passCtrl.text.isNotEmpty);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.employee != null;
    final permLabels = {
      'pos': 'Caisse POS', 'products': 'Produits', 'categories': 'Catégories',
      'customers': 'Clients', 'suppliers': 'Fournisseurs', 'employees': 'Employés',
      'reports': 'Rapports', 'banking': 'Banque', 'settings': 'Paramètres',
    };
    return AlertDialog(
      title: Text(isEdit ? 'Modifier l\'employé' : 'Nouvel employé'),
      content: SizedBox(
        width: 580,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nom complet *'),
                  validator: (v) => (v == null || v.isEmpty) ? 'Requis' : null,
                )),
                const SizedBox(width: 12),
                Expanded(child: TextFormField(
                  controller: _userCtrl,
                  decoration: const InputDecoration(labelText: 'Nom d\'utilisateur *'),
                  validator: (v) => (v == null || v.isEmpty) ? 'Requis' : null,
                )),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: TextFormField(
                  controller: _passCtrl,
                  decoration: InputDecoration(
                    labelText: isEdit ? 'Nouveau mot de passe (optionnel)' : 'Mot de passe *',
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  obscureText: _obscure,
                  validator: isEdit ? null : (v) => (v == null || v.isEmpty) ? 'Requis' : null,
                )),
                const SizedBox(width: 12),
                Expanded(child: TextFormField(
                  controller: _pinCtrl,
                  decoration: const InputDecoration(labelText: 'Code PIN (4 chiffres)'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                )),
              ]),
              const SizedBox(height: 20),
              const Text('Rôle', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'cashier', label: Text('Caissier'), icon: Icon(Icons.point_of_sale, size: 16)),
                  ButtonSegment(value: 'manager', label: Text('Manager'), icon: Icon(Icons.manage_accounts, size: 16)),
                  ButtonSegment(value: 'admin', label: Text('Admin'), icon: Icon(Icons.admin_panel_settings, size: 16)),
                  ButtonSegment(value: 'staff', label: Text('Staff'), icon: Icon(Icons.person, size: 16)),
                ],
                selected: {_role},
                onSelectionChanged: (s) => _setRole(s.first),
              ),
              const SizedBox(height: 20),
              const Text('Permissions par module', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: _perms.entries.map((e) => FilterChip(
                  label: Text(permLabels[e.key] ?? e.key),
                  selected: e.value,
                  onSelected: _role == 'admin' ? null : (v) => setState(() => _perms[e.key] = v),
                  selectedColor: Colors.blue.withOpacity(0.2),
                )).toList(),
              ),
            ],
          )),
        ),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.close, size: 16),
          label: const Text('Annuler'),
          onPressed: () => Navigator.pop(context),
        ),
        FilledButton.icon(
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save_rounded, size: 18),
          label: const Text('Enregistrer'),
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }
}
