import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/database/db.dart';
import '../../core/utils/helpers.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import 'stock_movements_screen.dart';

class StockScreen extends StatefulWidget {
  const StockScreen({super.key});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _filtered = [];
  String _filter = 'all';
  String _search = '';
  bool _loading = true;

  static const _filters = [
    ('all',  'Tous',        Icons.all_inclusive,   Colors.blue),
    ('ok',   'OK',          Icons.check_circle,    Colors.green),
    ('low',  'Faible',      Icons.warning_amber,   Colors.orange),
    ('out',  'Rupture',     Icons.remove_circle,   Colors.red),
  ];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final all = await DB.instance.getStockProducts(filter: 'all');
    if (mounted) setState(() {
      _products = all;
      _loading = false;
      _applyFilter();
    });
  }

  void _applyFilter() {
    final q = _search.toLowerCase();
    setState(() {
      _filtered = _products.where((p) {
        final matchSearch = q.isEmpty ||
            (p['name'] as String).toLowerCase().contains(q) ||
            (p['barcode'] as String? ?? '').toLowerCase().contains(q);

        final stock = (p['stock'] as num).toDouble();
        final min   = (p['min_stock'] as num).toDouble();
        final bool matchFilter;
        switch (_filter) {
          case 'ok':  matchFilter = stock > min; break;
          case 'low': matchFilter = stock > 0 && stock <= min; break;
          case 'out': matchFilter = stock <= 0; break;
          default:    matchFilter = true;
        }
        return matchSearch && matchFilter;
      }).toList();
    });
  }

  // Count by status
  int _countFilter(String f) {
    return _products.where((p) {
      final s = (p['stock'] as num).toDouble();
      final m = (p['min_stock'] as num).toDouble();
      switch (f) {
        case 'ok':  return s > m;
        case 'low': return s > 0 && s <= m;
        case 'out': return s <= 0;
        default:    return true;
      }
    }).length;
  }

  Future<void> _showAdjustDialog(Map<String, dynamic> product) async {
    final ctrl = TextEditingController();
    String mode = 'add'; // 'add', 'remove', 'set'

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
        title: Text('Ajuster le stock — ${product['name']}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Builder(builder: (ctx) {
            final primary = Theme.of(ctx).colorScheme.primary;
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.primaryContainer.withAlpha(80),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Stock actuel :', style: TextStyle(color: primary)),
                Text(
                  '${(product['stock'] as num).toStringAsFixed(0)} ${product['unit'] ?? 'pcs'}',
                  style: TextStyle(fontWeight: FontWeight.bold, color: primary, fontSize: 18),
                ),
              ]),
            );
          }),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'add',    label: Text('Ajouter'),    icon: Icon(Icons.add)),
              ButtonSegment(value: 'remove', label: Text('Retirer'),    icon: Icon(Icons.remove)),
              ButtonSegment(value: 'set',    label: Text('Définir'),    icon: Icon(Icons.edit)),
            ],
            selected: {mode},
            onSelectionChanged: (s) => setS(() => mode = s.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
            decoration: InputDecoration(
              labelText: mode == 'add' ? 'Quantité à ajouter' :
                         mode == 'remove' ? 'Quantité à retirer' : 'Nouveau stock',
              suffixText: product['unit'] as String? ?? 'pcs',
              prefixIcon: Icon(mode == 'add' ? Icons.add : mode == 'remove' ? Icons.remove : Icons.edit),
            ),
          ),
        ]),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Annuler'),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.save_rounded, size: 18),
            label: const Text('Enregistrer'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      )),
    );

    if (result != true) return;
    final val = double.tryParse(ctrl.text.trim());
    if (val == null || val < 0) return;

    final id = product['id'] as int;
    final current = (product['stock'] as num).toDouble();
    double delta;
    switch (mode) {
      case 'add':    delta = val; break;
      case 'remove': delta = -val; break;
      default:       delta = val - current; // 'set'
    }

    final auth = context.read<AuthProvider>();
    await DB.instance.adjustStockWithLog(
        id, product['name'] as String, delta,
        mode == 'add' ? 'Entrée stock' : mode == 'remove' ? 'Sortie stock' : 'Ajustement manuel',
        auth.employeeId);
    await _load();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Stock de "${product['name']}" mis à jour'),
        backgroundColor: Colors.green,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final sym = context.watch<SettingsProvider>().currencySymbol;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestion des stocks'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'Mouvements de stock',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const StockMovementsScreen())),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load, tooltip: 'Rafraîchir'),
        ],
      ),
      body: Column(children: [
        // Search + filter bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(children: [
            Expanded(child: TextField(
              decoration: const InputDecoration(
                hintText: 'Rechercher un produit...',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) { _search = v; _applyFilter(); },
            )),
            const SizedBox(width: 16),
            ...(_filters.map((f) {
              final (key, label, icon, color) = f;
              final count = _countFilter(key);
              final selected = _filter == key;
              return Padding(
                padding: const EdgeInsets.only(left: 8),
                child: FilterChip(
                  avatar: Icon(icon, size: 16, color: selected ? Colors.white : color),
                  label: Text('$label ($count)'),
                  selected: selected,
                  selectedColor: color,
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : null,
                    fontWeight: selected ? FontWeight.bold : null,
                  ),
                  onSelected: (_) { setState(() => _filter = key); _applyFilter(); },
                ),
              );
            })),
          ]),
        ),
        const Divider(height: 1),

        // Table header
        Builder(builder: (context) {
          final cs = Theme.of(context).colorScheme;
          final headerStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: cs.onSurfaceVariant);
          return Container(
            color: cs.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              Expanded(flex: 3, child: Text('Produit',    style: headerStyle)),
              Expanded(flex: 2, child: Text('Catégorie',  style: headerStyle)),
              SizedBox(width: 100, child: Text('Prix vente', style: headerStyle, textAlign: TextAlign.right)),
              SizedBox(width: 80,  child: Text('Stock',    style: headerStyle, textAlign: TextAlign.center)),
              SizedBox(width: 80,  child: Text('Minimum',  style: headerStyle, textAlign: TextAlign.center)),
              SizedBox(width: 90,  child: Text('Statut',   style: headerStyle, textAlign: TextAlign.center)),
              SizedBox(width: 60,  child: Text('Action',   style: headerStyle, textAlign: TextAlign.center)),
            ]),
          );
        }),
        const Divider(height: 1),

        // Product list
        Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _filtered.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.search_off, size: 48, color: Colors.grey),
                const SizedBox(height: 12),
                Text(_search.isNotEmpty ? 'Aucun produit trouvé pour "$_search"' : 'Aucun produit dans cette catégorie',
                    style: const TextStyle(color: Colors.grey)),
              ]))
            : ListView.separated(
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemCount: _filtered.length,
                itemBuilder: (_, i) => _buildRow(_filtered[i], sym),
              )),
      ]),
    );
  }

  Widget _buildRow(Map<String, dynamic> p, String sym) {
    final stock = (p['stock'] as num).toDouble();
    final min   = (p['min_stock'] as num).toDouble();
    final Color statusColor;
    final String statusLabel;
    final IconData statusIcon;
    if (stock <= 0) {
      statusColor = Colors.red; statusLabel = 'Rupture'; statusIcon = Icons.remove_circle;
    } else if (stock <= min) {
      statusColor = Colors.orange; statusLabel = 'Faible'; statusIcon = Icons.warning_amber;
    } else {
      statusColor = Colors.green; statusLabel = 'OK'; statusIcon = Icons.check_circle;
    }

    return InkWell(
      onTap: () => _showAdjustDialog(p),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          // Product
          Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
            if ((p['barcode'] as String?)?.isNotEmpty == true)
              Text(p['barcode'] as String, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ])),
          // Category
          Expanded(flex: 2, child: Text(
            p['category_name'] as String? ?? '—',
            style: const TextStyle(color: Colors.grey),
            overflow: TextOverflow.ellipsis,
          )),
          // Price
          SizedBox(width: 100, child: Text(
            formatCurrency((p['price'] as num).toDouble(), symbol: sym),
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w500),
          )),
          // Stock
          SizedBox(width: 80, child: Text(
            stock.toStringAsFixed(stock.truncateToDouble() == stock ? 0 : 1),
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold, color: statusColor, fontSize: 15),
          )),
          // Min
          SizedBox(width: 80, child: Text(
            min.toStringAsFixed(min.truncateToDouble() == min ? 0 : 1),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          )),
          // Status badge
          SizedBox(width: 90, child: Center(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: statusColor.withOpacity(0.4)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(statusIcon, color: statusColor, size: 12),
              const SizedBox(width: 4),
              Text(statusLabel, style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.bold)),
            ]),
          ))),
          // Action
          SizedBox(width: 60, child: Center(child: IconButton(
            icon: const Icon(Icons.edit_rounded, size: 18),
            tooltip: 'Ajuster le stock',
            onPressed: () => _showAdjustDialog(p),
          ))),
        ]),
      ),
    );
  }
}
