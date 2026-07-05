import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/database/db.dart';
import '../../providers/settings_provider.dart';

class SupplierLedgerScreen extends StatefulWidget {
  final Map<String, dynamic> supplier;
  const SupplierLedgerScreen({super.key, required this.supplier});

  @override
  State<SupplierLedgerScreen> createState() => _SupplierLedgerScreenState();
}

class _SupplierLedgerScreenState extends State<SupplierLedgerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<Map<String, dynamic>> _payments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await DB.instance
        .getSupplierPayments(widget.supplier['id'] as int);
    if (mounted) setState(() { _payments = data; _loading = false; });
  }

  Future<void> _addPayment() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _PaymentDialog(supplier: widget.supplier),
    );
    if (result == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final symbol  = settings.currencySymbol;
    final balance = (widget.supplier['balance'] as num?)?.toDouble() ?? 0;
    final theme   = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.supplier['name'] as String),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(icon: Icon(Icons.receipt_long), text: 'Paiements'),
            Tab(icon: Icon(Icons.info_outline), text: 'Infos'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addPayment,
        icon: const Icon(Icons.payments_outlined),
        label: const Text('Enregistrer paiement'),
      ),
      body: Column(children: [
        _BalanceBanner(balance: balance, symbol: symbol),
        Expanded(
          child: TabBarView(controller: _tab, children: [
            _loading
                ? const Center(child: CircularProgressIndicator())
                : _PaymentsList(payments: _payments, symbol: symbol, theme: theme),
            _SupplierInfoTab(supplier: widget.supplier),
          ]),
        ),
      ]),
    );
  }
}

class _BalanceBanner extends StatelessWidget {
  final double balance;
  final String symbol;
  const _BalanceBanner({required this.balance, required this.symbol});

  @override
  Widget build(BuildContext context) {
    final color = balance > 0 ? Colors.orange.shade700 : Colors.green.shade700;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      color: color.withOpacity(.12),
      child: Row(children: [
        Icon(balance > 0 ? Icons.warning_amber_rounded : Icons.check_circle_outline,
            color: color),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Solde fournisseur',
              style: TextStyle(fontSize: 12, color: color)),
          Text('$symbol ${balance.toStringAsFixed(2)}',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: color)),
        ]),
        const Spacer(),
        Text(balance > 0 ? 'À payer' : 'Aucune dette',
            style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _PaymentsList extends StatelessWidget {
  final List<Map<String, dynamic>> payments;
  final String symbol;
  final ThemeData theme;
  const _PaymentsList({required this.payments, required this.symbol, required this.theme});

  @override
  Widget build(BuildContext context) {
    if (payments.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.payments_outlined, size: 56,
              color: theme.colorScheme.onSurface.withOpacity(.3)),
          const SizedBox(height: 8),
          const Text('Aucun paiement enregistré'),
        ]),
      );
    }
    final fmt = DateFormat('dd/MM/yyyy');
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
      itemCount: payments.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (_, i) {
        final p = payments[i];
        final amount = (p['amount'] as num).toDouble();
        final date   = p['date'] as String? ?? '';
        final method = p['payment_method'] as String? ?? 'cash';
        final note   = p['note'] as String? ?? '';
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.green.withOpacity(.15),
              child: const Icon(Icons.payments_outlined, color: Colors.green),
            ),
            title: Text('$symbol ${amount.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text([
              _methodLabel(method),
              if (note.isNotEmpty) note,
            ].join(' • ')),
            trailing: Text(
              date.length >= 10 ? fmt.format(DateTime.parse(date)) : date,
              style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(.6)),
            ),
          ),
        );
      },
    );
  }

  String _methodLabel(String m) {
    switch (m) {
      case 'card':     return 'Carte';
      case 'transfer': return 'Virement';
      case 'cheque':   return 'Chèque';
      default:         return 'Espèces';
    }
  }
}

class _SupplierInfoTab extends StatelessWidget {
  final Map<String, dynamic> supplier;
  const _SupplierInfoTab({required this.supplier});

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      _InfoRow(Icons.person_outline,      'Nom',      supplier['name']    as String? ?? '—'),
      _InfoRow(Icons.phone_outlined,      'Téléphone',supplier['phone']   as String? ?? '—'),
      _InfoRow(Icons.email_outlined,      'Email',    supplier['email']   as String? ?? '—'),
      _InfoRow(Icons.location_on_outlined,'Adresse',  supplier['address'] as String? ?? '—'),
      _InfoRow(Icons.notes_outlined,      'Notes',    supplier['notes']   as String? ?? '—'),
    ]);
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ]),
      ]),
    );
  }
}

class _PaymentDialog extends StatefulWidget {
  final Map<String, dynamic> supplier;
  const _PaymentDialog({required this.supplier});
  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final _formKey    = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _noteCtrl   = TextEditingController();
  String _method = 'cash';
  bool   _saving = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final amount = double.parse(_amountCtrl.text.trim().replaceAll(',', '.'));
    await DB.instance.addSupplierPayment({
      'supplier_id':    widget.supplier['id'],
      'amount':         amount,
      'payment_method': _method,
      'note':           _noteCtrl.text.trim(),
      'date':           DateTime.now().toIso8601String().substring(0, 10),
    });
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Paiement — ${widget.supplier['name']}'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: _amountCtrl,
              decoration: const InputDecoration(labelText: 'Montant *', border: OutlineInputBorder()),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Champ requis';
                if (double.tryParse(v.replaceAll(',', '.')) == null) return 'Nombre invalide';
                return null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _method,
              decoration: const InputDecoration(labelText: 'Mode de paiement', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'cash',     child: Text('Espèces')),
                DropdownMenuItem(value: 'card',     child: Text('Carte')),
                DropdownMenuItem(value: 'transfer', child: Text('Virement')),
                DropdownMenuItem(value: 'cheque',   child: Text('Chèque')),
              ],
              onChanged: (v) => setState(() => _method = v!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _noteCtrl,
              decoration: const InputDecoration(labelText: 'Note', border: OutlineInputBorder()),
              maxLines: 2,
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Enregistrer'),
        ),
      ],
    );
  }
}
