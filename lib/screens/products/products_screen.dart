import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/database/db.dart';
import '../../core/utils/helpers.dart';
import '../../providers/settings_provider.dart';
import 'product_form_screen.dart';
import 'product_import_screen.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _categories = [];
  int? _catFilter;
  bool _lowStock = false;
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final cats = await DB.instance.getCategories();
    final prods = await DB.instance.getProducts(q: _searchCtrl.text, catId: _catFilter, lowStock: _lowStock);
    if (mounted) setState(() { _categories = cats; _products = prods; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final sym = context.watch<SettingsProvider>().currencySymbol;
    return Scaffold(
      appBar: AppBar(
        title: Text('Produits (${_products.length})'),
        actions: [
          FilterChip(
            label: Text('Stock faible', style: TextStyle(color: _lowStock ? Colors.white : Colors.white70, fontSize: 13)),
            avatar: Icon(Icons.warning_amber_rounded, size: 16, color: _lowStock ? Colors.white : Colors.white70),
            selected: _lowStock,
            onSelected: (v) { setState(() => _lowStock = v); _load(); },
            selectedColor: Colors.orange.shade700,
            backgroundColor: Colors.white.withAlpha(30),
            side: BorderSide(color: _lowStock ? Colors.orange.shade700 : Colors.white38),
            showCheckmark: false,
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
            onPressed: _load,
          ),
          const SizedBox(width: 8),
          // ── Import CSV button
          OutlinedButton.icon(
            icon: const Icon(Icons.upload_file, size: 18),
            label: const Text('Importer CSV'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white70),
            ),
            onPressed: _openImport,
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () => _openForm(null),
            icon: const Icon(Icons.add),
            label: const Text('Nouveau produit'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                hintText: 'Rechercher par nom ou code-barre...',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (_) => _load(),
            )),
            const SizedBox(width: 12),
            DropdownButton<int?>(
              value: _catFilter,
              hint: const Text('Catégorie'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Toutes')),
                ..._categories.map((c) => DropdownMenuItem(value: c['id'] as int, child: Text(c['name'] as String))),
              ],
              onChanged: (v) { setState(() => _catFilter = v); _load(); },
            ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _products.isEmpty
                  ? const Center(child: Text('Aucun produit'))
                  : DataTable2(
                      products: _products,
                      sym: sym,
                      onEdit: _openForm,
                      onDelete: _delete,
                    ),
        ),
      ]),
    );
  }

  Future<void> _openForm(Map<String, dynamic>? product) async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => ProductFormScreen(product: product, categories: _categories),
    ));
    _load();
  }

  Future<void> _openImport() async {
    final imported = await Navigator.push<bool>(context, MaterialPageRoute(
      builder: (_) => const ProductImportScreen(),
    ));
    if (imported == true) _load(); // refresh list if products were added
  }

  Future<void> _delete(Map<String, dynamic> p) async {
    final ok = await confirmDialog(context, 'Supprimer le produit', 'Supprimer "${p['name']}" ?');
    if (ok) {
      await DB.instance.deleteProduct(p['id'] as int);
      _load();
    }
  }
}

class DataTable2 extends StatelessWidget {
  final List<Map<String, dynamic>> products;
  final String sym;
  final Function(Map<String, dynamic>) onEdit;
  final Function(Map<String, dynamic>) onDelete;

  const DataTable2({super.key, required this.products, required this.sym, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: DataTable(
        columnSpacing: 20,
        headingRowColor: WidgetStateProperty.all(Colors.blue.shade50),
        columns: const [
          DataColumn(label: Text('Produit', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Catégorie', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Prix vente', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
          DataColumn(label: Text('Prix achat', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
          DataColumn(label: Text('Stock', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
          DataColumn(label: Text('Code-barre', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
        ],
        rows: products.map((p) {
          final stock = (p['stock'] as num).toDouble();
          final minStock = (p['min_stock'] as num?)?.toDouble() ?? 5;
          final isLow = stock <= minStock;
          return DataRow(cells: [
            DataCell(Text(p['name'] as String, style: const TextStyle(fontWeight: FontWeight.w500))),
            DataCell(Text(p['category_name'] as String? ?? '—')),
            DataCell(Text(formatCurrency((p['price'] as num).toDouble(), symbol: sym))),
            DataCell(Text(formatCurrency((p['cost_price'] as num?)?.toDouble() ?? 0, symbol: sym))),
            DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
              Text('${stock.toInt()} ${p['unit'] ?? 'pcs'}',
                  style: TextStyle(color: isLow ? Colors.orange : null, fontWeight: isLow ? FontWeight.bold : null)),
              if (isLow) const SizedBox(width: 4),
              if (isLow) const Icon(Icons.warning_amber, size: 14, color: Colors.orange),
            ])),
            DataCell(Text(p['barcode'] as String? ?? '—', style: const TextStyle(fontFamily: 'monospace'))),
            DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.edit, size: 18, color: Colors.blue), onPressed: () => onEdit(p)),
              IconButton(icon: const Icon(Icons.delete, size: 18, color: Colors.red), onPressed: () => onDelete(p)),
            ])),
          ]);
        }).toList(),
      ),
    );
  }
}
