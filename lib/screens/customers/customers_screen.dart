import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/database/db.dart';
import '../../core/utils/helpers.dart';
import '../../providers/settings_provider.dart';
import 'package:provider/provider.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  List<Map<String, dynamic>> _customers = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await DB.instance.getCustomers(q: _searchCtrl.text);
    if (mounted) setState(() { _customers = data; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final sym = context.watch<SettingsProvider>().currencySymbol;
    return Scaffold(
      appBar: AppBar(
        title: Text('Clients (${_customers.length})'),
        actions: [
          ElevatedButton.icon(
            onPressed: () => _openForm(null),
            icon: const Icon(Icons.person_add),
            label: const Text('Nouveau client'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              hintText: 'Rechercher par nom ou téléphone...',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
            onChanged: (_) => _load(),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _customers.isEmpty
                  ? const Center(child: Text('Aucun client'))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemCount: _customers.length,
                      itemBuilder: (_, i) {
                        final c = _customers[i];
                        final balance = (c['balance'] as num?)?.toDouble() ?? 0;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: c['type'] == 'wholesale' ? Colors.blue.shade100 : Colors.green.shade100,
                            child: Text(
                              (c['name'] as String)[0].toUpperCase(),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: c['type'] == 'wholesale' ? Colors.blue : Colors.green,
                              ),
                            ),
                          ),
                          title: Text(
                            '${c['name']}${(c['first_name'] as String?)?.isNotEmpty == true ? ' ${c['first_name']}' : ''}',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('${c['phone'] ?? ''} • ${c['type'] == 'wholesale' ? 'Grossiste' : 'Détail'}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (balance != 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: balance < 0 ? Colors.red.shade50 : Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: balance < 0 ? Colors.red.shade200 : Colors.green.shade200),
                                  ),
                                  child: Text(
                                    formatCurrency(balance, symbol: sym),
                                    style: TextStyle(
                                      color: balance < 0 ? Colors.red : Colors.green,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 8),
                              IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _openForm(c)),
                              IconButton(icon: const Icon(Icons.delete, size: 18, color: Colors.red), onPressed: () => _delete(c)),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ]),
    );
  }

  Future<void> _openForm(Map<String, dynamic>? customer) async {
    await showDialog(context: context, builder: (_) => _CustomerFormDialog(customer: customer));
    _load();
  }

  Future<void> _delete(Map<String, dynamic> c) async {
    final ok = await confirmDialog(context, 'Supprimer le client', 'Supprimer "${c['name']}" ?');
    if (ok) { await DB.instance.deleteCustomer(c['id'] as int); _load(); }
  }
}

class _CustomerFormDialog extends StatefulWidget {
  final Map<String, dynamic>? customer;
  const _CustomerFormDialog({this.customer});

  @override
  State<_CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends State<_CustomerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _detteCtrl = TextEditingController();
  final _creditCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _type = 'retail';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.customer;
    if (c != null) {
      _nameCtrl.text = c['name'] as String;
      _firstNameCtrl.text = c['first_name'] as String? ?? '';
      _phoneCtrl.text = c['phone'] as String? ?? '';
      _emailCtrl.text = c['email'] as String? ?? '';
      _addressCtrl.text = c['address'] as String? ?? '';
      _creditCtrl.text = (c['credit_limit'] as num?)?.toString() ?? '0';
      _notesCtrl.text = c['notes'] as String? ?? '';
      _type = c['type'] as String? ?? 'retail';
      // Solde négatif = dette → on affiche le montant dû (positif).
      final bal = (c['balance'] as num?)?.toDouble() ?? 0;
      final dette = bal < 0 ? -bal : 0.0;
      _detteCtrl.text = dette == 0
          ? ''
          : (dette % 1 == 0 ? dette.toInt().toString() : dette.toString());
    } else {
      _creditCtrl.text = '0';
    }
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _firstNameCtrl, _phoneCtrl, _emailCtrl, _addressCtrl, _detteCtrl, _creditCtrl, _notesCtrl]) c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    await DB.instance.upsertCustomer({
      if (widget.customer?['id'] != null) 'id': widget.customer!['id'],
      'name': _nameCtrl.text.trim(),
      'first_name': _firstNameCtrl.text.trim().isEmpty ? null : _firstNameCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
      'email': _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
      'address': _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
      'type': _type,
      // Dette saisie (positive) → solde négatif (convention : négatif = doit).
      'balance': -(double.tryParse(_detteCtrl.text) ?? 0),
      'credit_limit': double.tryParse(_creditCtrl.text) ?? 0,
      'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.customer == null ? 'Nouveau client' : 'Modifier le client'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(child: TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Nom *', prefixIcon: Icon(Icons.person)),
                validator: (v) => (v == null || v.isEmpty) ? 'Requis' : null,
              )),
              const SizedBox(width: 12),
              Expanded(child: TextFormField(
                controller: _firstNameCtrl,
                decoration: const InputDecoration(labelText: 'Prénom', prefixIcon: Icon(Icons.badge_outlined)),
              )),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextFormField(
                controller: _phoneCtrl,
                decoration: const InputDecoration(labelText: 'Téléphone', prefixIcon: Icon(Icons.phone)),
                keyboardType: TextInputType.phone,
              )),
              const SizedBox(width: 12),
              Expanded(child: TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email)),
                keyboardType: TextInputType.emailAddress,
              )),
            ]),
            const SizedBox(height: 12),
            TextFormField(
              controller: _addressCtrl,
              decoration: const InputDecoration(labelText: 'Adresse', prefixIcon: Icon(Icons.location_on)),
            ),
            const SizedBox(height: 12),
            Row(children: [
              const Text('Type : '),
              const SizedBox(width: 12),
              ChoiceChip(
                label: const Text('Détail'),
                selected: _type == 'retail',
                onSelected: (_) => setState(() => _type = 'retail'),
                selectedColor: Colors.green,
                labelStyle: TextStyle(color: _type == 'retail' ? Colors.white : null),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Grossiste'),
                selected: _type == 'wholesale',
                onSelected: (_) => setState(() => _type = 'wholesale'),
                selectedColor: Colors.blue,
                labelStyle: TextStyle(color: _type == 'wholesale' ? Colors.white : null),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextFormField(
                controller: _detteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Dette (montant dû)',
                  prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
              )),
              const SizedBox(width: 12),
              Expanded(child: TextFormField(
                controller: _creditCtrl,
                decoration: const InputDecoration(labelText: 'Limite de crédit', prefixIcon: Icon(Icons.credit_score)),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
              )),
            ]),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(labelText: 'Notes'),
              maxLines: 2,
            ),
          ]),
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
