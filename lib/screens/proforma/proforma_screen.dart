import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/database/db.dart';
import '../../core/utils/helpers.dart';
import '../../core/utils/invoice_pdf.dart';
import '../../providers/settings_provider.dart';
import '../shared/pdf_preview_screen.dart';

/// Une ligne de proforma (devis). N'affecte ni le stock ni les ventes.
class _ProformaLine {
  final int? productId;
  final String name;
  final String unit;
  double qty;
  double price;
  _ProformaLine({
    this.productId,
    required this.name,
    this.unit = 'pcs',
    this.qty = 1,
    this.price = 0,
  });
  double get total => qty * price;
}

class ProformaScreen extends StatefulWidget {
  const ProformaScreen({super.key});

  @override
  State<ProformaScreen> createState() => _ProformaScreenState();
}

class _ProformaScreenState extends State<ProformaScreen> {
  final List<_ProformaLine> _lines = [];
  Map<String, dynamic>? _customer;

  double get _total => _lines.fold(0.0, (s, l) => s + l.total);

  // ── Ajouter un article via un sélecteur de produits ──────────────────────
  Future<void> _addProduct() async {
    final product = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _ProductPickerDialog(),
    );
    if (product == null) return;
    setState(() {
      final id = product['id'] as int?;
      _ProformaLine? existing;
      if (id != null) {
        for (final l in _lines) {
          if (l.productId == id) { existing = l; break; }
        }
      }
      if (existing != null) {
        existing.qty += 1;
      } else {
        _lines.add(_ProformaLine(
          productId: id,
          name: product['name'] as String,
          unit: product['unit'] as String? ?? 'pcs',
          qty: 1,
          price: (product['price'] as num?)?.toDouble() ?? 0,
        ));
      }
    });
  }

  Future<void> _selectCustomer() async {
    final customer = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _CustomerPickerDialog(),
    );
    if (customer != null) setState(() => _customer = customer);
  }

  Future<void> _print() async {
    if (_lines.isEmpty) {
      showError(context, 'Ajoutez au moins un article à la proforma.');
      return;
    }
    final s = context.read<SettingsProvider>();
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}  '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final doc = buildLetterInvoice(
      title: 'PROFORMA / DEVIS',
      dateStr: dateStr,
      businessName: s.businessName,
      businessAddress: s.businessAddress,
      businessPhone: s.businessPhone,
      logo: loadBusinessLogo(s.logoPath),
      customerName: _customer?['name'] as String?,
      currency: s.currencySymbol,
      lines: _lines
          .map((l) => InvoiceLine(
                name: l.name,
                qty: l.qty,
                unitPrice: l.price,
                total: l.total,
                unit: l.unit,
              ))
          .toList(),
      total: _total,
      footer: 'Devis valable 30 jours — Document non contractuel.',
    );
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PdfPreviewScreen(
        title: 'Aperçu — Proforma',
        document: doc,
        suggestedFileName: 'Proforma.pdf',
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final sym = context.watch<SettingsProvider>().currencySymbol;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Proforma / Devis'),
        actions: [
          if (_lines.isNotEmpty)
            IconButton(
              tooltip: 'Vider la proforma',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => setState(() {
                _lines.clear();
                _customer = null;
              }),
            ),
        ],
      ),
      body: Column(children: [
        // En-tête : client + ajouter article
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _selectCustomer,
                icon: const Icon(Icons.person_outline, size: 18),
                label: Text(
                  _customer == null ? 'Client (optionnel)' : _customer!['name'] as String,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _addProduct,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Ajouter un article'),
            ),
          ]),
        ),
        const Divider(height: 1),
        // Liste des articles
        Expanded(
          child: _lines.isEmpty
              ? const Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.request_quote_outlined, size: 48, color: Colors.grey),
                    SizedBox(height: 12),
                    Text('Aucun article. Cliquez « Ajouter un article ».',
                        style: TextStyle(color: Colors.grey)),
                  ]),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: _lines.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => _lineTile(_lines[i], i, sym),
                ),
        ),
        // Pied : total + imprimer
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: Border(top: BorderSide(color: Colors.grey.shade300)),
          ),
          child: Row(children: [
            Expanded(
              child: Text('TOTAL : ${formatCurrency(_total, symbol: sym)}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            FilledButton.icon(
              onPressed: _lines.isEmpty ? null : _print,
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: const Text('Aperçu / Imprimer'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _lineTile(_ProformaLine l, int i, String sym) {
    return ListTile(
      title: Text(l.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(children: [
          SizedBox(
            width: 90,
            child: _numField(
              label: 'Qté',
              value: l.qty,
              onChanged: (v) => setState(() => l.qty = v),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 130,
            child: _numField(
              label: 'Prix U.',
              value: l.price,
              onChanged: (v) => setState(() => l.price = v),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(formatCurrency(l.total, symbol: sym),
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ]),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.close, size: 18, color: Colors.red),
        onPressed: () => setState(() => _lines.removeAt(i)),
      ),
    );
  }

  Widget _numField({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return TextFormField(
      initialValue: value % 1 == 0 ? value.toInt().toString() : value.toString(),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: const OutlineInputBorder(),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (v) => onChanged(double.tryParse(v) ?? 0),
    );
  }
}

// ─── Sélecteur de produit ──────────────────────────────────────────────────
class _ProductPickerDialog extends StatefulWidget {
  const _ProductPickerDialog();
  @override
  State<_ProductPickerDialog> createState() => _ProductPickerDialogState();
}

class _ProductPickerDialogState extends State<_ProductPickerDialog> {
  List<Map<String, dynamic>> _products = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  Future<void> _load(String q) async {
    setState(() => _loading = true);
    final res = await DB.instance.getProducts(q: q);
    if (mounted) setState(() { _products = res; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final sym = context.read<SettingsProvider>().currencySymbol;
    return AlertDialog(
      title: const Text('Choisir un article'),
      content: SizedBox(
        width: 460,
        height: 460,
        child: Column(children: [
          TextField(
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Rechercher un produit…',
              prefixIcon: Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: _load,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _products.isEmpty
                    ? const Center(child: Text('Aucun produit'))
                    : ListView.separated(
                        itemCount: _products.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final p = _products[i];
                          return ListTile(
                            dense: true,
                            title: Text(p['name'] as String),
                            subtitle: Text('${p['category_name'] ?? ''}'),
                            trailing: Text(
                              formatCurrency((p['price'] as num?)?.toDouble() ?? 0, symbol: sym),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            onTap: () => Navigator.pop(context, p),
                          );
                        },
                      ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer')),
      ],
    );
  }
}

// ─── Sélecteur de client ───────────────────────────────────────────────────
class _CustomerPickerDialog extends StatefulWidget {
  const _CustomerPickerDialog();
  @override
  State<_CustomerPickerDialog> createState() => _CustomerPickerDialogState();
}

class _CustomerPickerDialogState extends State<_CustomerPickerDialog> {
  List<Map<String, dynamic>> _customers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  Future<void> _load(String q) async {
    setState(() => _loading = true);
    final res = await DB.instance.getCustomers(q: q);
    if (mounted) setState(() { _customers = res; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Choisir un client'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(children: [
          TextField(
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Rechercher un client…',
              prefixIcon: Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: _load,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _customers.isEmpty
                    ? const Center(child: Text('Aucun client'))
                    : ListView.separated(
                        itemCount: _customers.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final c = _customers[i];
                          final fn = (c['first_name'] as String?)?.isNotEmpty == true
                              ? ' ${c['first_name']}'
                              : '';
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.person_outline),
                            title: Text('${c['name']}$fn'),
                            subtitle: Text('${c['phone'] ?? ''}'),
                            onTap: () => Navigator.pop(context, c),
                          );
                        },
                      ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer')),
      ],
    );
  }
}
