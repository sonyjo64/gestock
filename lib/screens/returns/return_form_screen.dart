import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/database/db.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';

class ReturnFormScreen extends StatefulWidget {
  const ReturnFormScreen({super.key});
  @override
  State<ReturnFormScreen> createState() => _ReturnFormScreenState();
}

class _ReturnFormScreenState extends State<ReturnFormScreen> {
  final _saleSearchCtrl = TextEditingController();
  final _notesCtrl      = TextEditingController();
  final _reasonCtrl     = TextEditingController();

  List<Map<String, dynamic>> _sales        = [];
  Map<String, dynamic>?      _selectedSale;
  List<Map<String, dynamic>> _saleItems    = [];
  final Map<int, double>     _returnQtys   = {};
  bool _searching = false;
  bool _saving    = false;

  @override
  void dispose() {
    _saleSearchCtrl.dispose();
    _notesCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _searchSales(String q) async {
    if (q.trim().isEmpty) { setState(() => _sales = []); return; }
    setState(() => _searching = true);
    final id = int.tryParse(q.trim());
    List<Map<String, dynamic>> results;
    if (id != null) {
      final s = await DB.instance.getSaleById(id);
      results = s != null ? [s] : [];
    } else {
      results = await DB.instance.getSales();
      results = results
          .where((s) => (s['customer_name'] as String? ?? '')
              .toLowerCase().contains(q.toLowerCase()))
          .take(10)
          .toList();
    }
    if (mounted) setState(() { _sales = results; _searching = false; });
  }

  Future<void> _selectSale(Map<String, dynamic> sale) async {
    final items = await DB.instance.getSaleItems(sale['id'] as int);
    setState(() {
      _selectedSale = sale;
      _saleItems    = items;
      _returnQtys.clear();
      for (final item in items) {
        _returnQtys[item['id'] as int] = 0;
      }
      _sales = [];
      _saleSearchCtrl.clear();
    });
  }

  double get _totalReturn {
    double t = 0;
    for (final item in _saleItems) {
      final qty = _returnQtys[item['id'] as int] ?? 0;
      if (qty > 0) {
        t += qty * ((item['price'] as num).toDouble());
      }
    }
    return t;
  }

  Future<void> _submit() async {
    if (_selectedSale == null) return;
    final returnItems = _saleItems.where((item) {
      final qty = _returnQtys[item['id'] as int] ?? 0;
      return qty > 0;
    }).toList();
    if (returnItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sélectionnez au moins un article à retourner')));
      return;
    }
    setState(() => _saving = true);
    final auth = context.read<AuthProvider>();
    final ret = {
      'sale_id':      _selectedSale!['id'],
      'customer_id':  _selectedSale!['customer_id'],
      'employee_id':  auth.employeeId,
      'total_amount': _totalReturn,
      'reason':       _reasonCtrl.text.trim(),
      'notes':        _notesCtrl.text.trim(),
    };
    final items = returnItems.map((item) {
      final qty = _returnQtys[item['id'] as int]!;
      return {
        'product_id':   item['product_id'],
        'product_name': item['product_name'],
        'quantity':     qty,
        'price':        item['price'],
        'total':        qty * (item['price'] as num).toDouble(),
      };
    }).toList();
    await DB.instance.createReturn(ret, items);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Retour enregistré avec succès'),
              backgroundColor: Colors.green));
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final symbol   = settings.currencySymbol;
    final fmt      = DateFormat('dd/MM/yyyy HH:mm');

    return Scaffold(
      appBar: AppBar(title: const Text('Nouveau retour')),
      bottomNavigationBar: _selectedSale != null && _totalReturn > 0
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _submit,
                  icon: _saving
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.assignment_return_outlined),
                  label: Text('Confirmer le retour — $symbol ${_totalReturn.toStringAsFixed(2)}'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            )
          : null,
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // ── Recherche vente ──────────────────────────────────────────────────
        Text('Étape 1 — Rechercher la vente',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          controller: _saleSearchCtrl,
          decoration: InputDecoration(
            hintText: 'N° de vente ou nom du client…',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searching
                ? const Padding(padding: EdgeInsets.all(10),
                    child: SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)))
                : null,
            border: const OutlineInputBorder(),
          ),
          onChanged: _searchSales,
        ),
        if (_sales.isNotEmpty)
          Card(
            child: Column(
              children: _sales.map((s) {
                final customer = s['customer_name'] as String? ?? 'Client comptant';
                final total    = (s['total'] as num).toDouble();
                DateTime? dt;
                try { dt = DateTime.parse(s['created_at'] as String); } catch (_) {}
                return ListTile(
                  title: Text('Vente #${s['id']} — $customer'),
                  subtitle: dt != null ? Text(fmt.format(dt)) : null,
                  trailing: Text('$symbol ${total.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  onTap: () => _selectSale(s),
                );
              }).toList(),
            ),
          ),

        // ── Vente sélectionnée ───────────────────────────────────────────────
        if (_selectedSale != null) ...[
          const SizedBox(height: 20),
          Text('Étape 2 — Articles à retourner',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: _saleItems.map((item) {
                final itemId  = item['id'] as int;
                final maxQty  = (item['quantity'] as num).toDouble();
                final price   = (item['price'] as num).toDouble();
                final retQty  = _returnQtys[itemId] ?? 0;
                return ListTile(
                  title: Text(item['product_name'] as String),
                  subtitle: Text('$symbol ${price.toStringAsFixed(2)} × ${maxQty.toStringAsFixed(0)} vendus'),
                  trailing: SizedBox(
                    width: 130,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: retQty > 0
                            ? () => setState(() => _returnQtys[itemId] = retQty - 1)
                            : null,
                      ),
                      SizedBox(
                        width: 32,
                        child: Text('${retQty.toStringAsFixed(0)}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: retQty > 0
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                            )),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: retQty < maxQty
                            ? () => setState(() => _returnQtys[itemId] = retQty + 1)
                            : null,
                      ),
                    ]),
                  ),
                );
              }).toList(),
            ),
          ),

          // ── Motif & notes ────────────────────────────────────────────────
          const SizedBox(height: 16),
          Text('Étape 3 — Motif du retour',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _reasonCtrl,
            decoration: const InputDecoration(
              hintText: 'Motif (ex: produit défectueux, erreur de commande…)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtrl,
            decoration: const InputDecoration(
              hintText: 'Notes supplémentaires (optionnel)',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),

          if (_totalReturn > 0) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(.3)),
              ),
              child: Row(children: [
                const Icon(Icons.assignment_return_outlined, color: Colors.orange),
                const SizedBox(width: 12),
                const Text('Montant à rembourser :',
                    style: TextStyle(fontWeight: FontWeight.w500)),
                const Spacer(),
                Text('$symbol ${_totalReturn.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 18,
                        color: Colors.orange)),
              ]),
            ),
          ],
          const SizedBox(height: 80),
        ],
      ]),
    );
  }
}
