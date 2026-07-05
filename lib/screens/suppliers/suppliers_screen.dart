import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/database/db.dart';
import '../../providers/settings_provider.dart';
import 'supplier_ledger_screen.dart';

class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key});
  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  List<Map<String, dynamic>> _suppliers = [];
  final _searchCtrl = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final q = _searchCtrl.text.trim();
    final data = await DB.instance.getSuppliers(q: q.isEmpty ? null : q);
    if (mounted) setState(() { _suppliers = data; _loading = false; });
  }

  void _openLedger(Map<String, dynamic> s) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => SupplierLedgerScreen(supplier: s),
    )).then((_) => _load());
  }

  Future<void> _showForm([Map<String, dynamic>? s]) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _SupplierFormDialog(supplier: s),
    );
    if (result == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer le fournisseur'),
        content: Text('Supprimer "${s['name']}" ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await DB.instance.deleteSupplier(s['id'] as int);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final symbol = settings.currencySymbol;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fournisseurs'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load, tooltip: 'Actualiser'),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showForm(),
        icon: const Icon(Icons.add),
        label: const Text('Nouveau fournisseur'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Rechercher par nom ou téléphone…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear),
                        onPressed: () { _searchCtrl.clear(); _load(); })
                    : null,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => _load(),
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_suppliers.isEmpty)
            Expanded(
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.local_shipping_outlined, size: 64,
                      color: theme.colorScheme.onSurface.withOpacity(.3)),
                  const SizedBox(height: 12),
                  Text('Aucun fournisseur',
                      style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(.5))),
                ]),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
                itemCount: _suppliers.length,
                itemBuilder: (_, i) {
                  final s = _suppliers[i];
                  final balance = (s['balance'] as num?)?.toDouble() ?? 0;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: theme.colorScheme.primary.withOpacity(.15),
                        child: Icon(Icons.local_shipping_rounded,
                            color: theme.colorScheme.primary),
                      ),
                      title: Text(s['name'] as String,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        [
                          if ((s['phone'] as String?)?.isNotEmpty == true) s['phone'],
                          if ((s['email'] as String?)?.isNotEmpty == true) s['email'],
                        ].join(' • '),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('$symbol ${balance.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: balance > 0 ? Colors.orange : Colors.green,
                                )),
                            Text(balance > 0 ? 'À payer' : 'Soldé',
                                style: TextStyle(fontSize: 11,
                                    color: balance > 0 ? Colors.orange : Colors.green)),
                          ],
                        ),
                        const SizedBox(width: 8),
                        PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'ledger') _openLedger(s);
                            if (v == 'edit')   _showForm(s);
                            if (v == 'delete') _delete(s);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'ledger', child: Row(children: [
                              Icon(Icons.book_outlined, size: 18), SizedBox(width: 8),
                              Text('Voir le ledger'),
                            ])),
                            PopupMenuItem(value: 'edit', child: Row(children: [
                              Icon(Icons.edit_outlined, size: 18), SizedBox(width: 8),
                              Text('Modifier'),
                            ])),
                            PopupMenuItem(value: 'delete', child: Row(children: [
                              Icon(Icons.delete_outline, size: 18, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Supprimer', style: TextStyle(color: Colors.red)),
                            ])),
                          ],
                        ),
                      ]),
                      onTap: () => _openLedger(s),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _SupplierFormDialog extends StatefulWidget {
  final Map<String, dynamic>? supplier;
  const _SupplierFormDialog({this.supplier});
  @override
  State<_SupplierFormDialog> createState() => _SupplierFormDialogState();
}

class _SupplierFormDialogState extends State<_SupplierFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameCtrl    = TextEditingController(text: widget.supplier?['name']    as String? ?? '');
  late final _phoneCtrl   = TextEditingController(text: widget.supplier?['phone']   as String? ?? '');
  late final _emailCtrl   = TextEditingController(text: widget.supplier?['email']   as String? ?? '');
  late final _addressCtrl = TextEditingController(text: widget.supplier?['address'] as String? ?? '');
  late final _notesCtrl   = TextEditingController(text: widget.supplier?['notes']   as String? ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose(); _phoneCtrl.dispose(); _emailCtrl.dispose();
    _addressCtrl.dispose(); _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final data = {
      if (widget.supplier?['id'] != null) 'id': widget.supplier!['id'],
      'name':    _nameCtrl.text.trim(),
      'phone':   _phoneCtrl.text.trim(),
      'email':   _emailCtrl.text.trim(),
      'address': _addressCtrl.text.trim(),
      'notes':   _notesCtrl.text.trim(),
    };
    await DB.instance.upsertSupplier(data);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.supplier != null;
    return AlertDialog(
      title: Text(isEdit ? 'Modifier le fournisseur' : 'Nouveau fournisseur'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Nom *', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Champ requis' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(controller: _phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Téléphone', border: OutlineInputBorder()),
                  keyboardType: TextInputType.phone),
              const SizedBox(height: 12),
              TextFormField(controller: _emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                  keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 12),
              TextFormField(controller: _addressCtrl,
                  decoration: const InputDecoration(labelText: 'Adresse', border: OutlineInputBorder()),
                  maxLines: 2),
              const SizedBox(height: 12),
              TextFormField(controller: _notesCtrl,
                  decoration: const InputDecoration(labelText: 'Notes', border: OutlineInputBorder()),
                  maxLines: 2),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(isEdit ? 'Enregistrer' : 'Créer'),
        ),
      ],
    );
  }
}
