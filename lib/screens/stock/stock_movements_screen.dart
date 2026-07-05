import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/database/db.dart';
import '../../providers/settings_provider.dart';

class StockMovementsScreen extends StatefulWidget {
  const StockMovementsScreen({super.key});
  @override
  State<StockMovementsScreen> createState() => _StockMovementsScreenState();
}

class _StockMovementsScreenState extends State<StockMovementsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<Map<String, dynamic>> _adjustments = [];
  List<Map<String, dynamic>> _salesMov    = [];
  List<Map<String, dynamic>> _products    = [];
  int? _filterProductId;
  bool _loading = true;
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to   = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final fStr = _from.toIso8601String().substring(0, 10);
    final tStr = _to.toIso8601String().substring(0, 10);
    final results = await Future.wait([
      DB.instance.getStockAdjustments(
          productId: _filterProductId, from: fStr, to: tStr),
      DB.instance.getStockMovements(fStr, tStr),
      DB.instance.getProducts(),
    ]);
    if (mounted) setState(() {
      _adjustments = results[0];
      _salesMov    = results[1];
      _products    = results[2];
      _loading     = false;
    });
  }

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (range != null) {
      setState(() { _from = range.start; _to = range.end; });
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yy');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mouvements de stock'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(icon: Icon(Icons.tune_rounded),    text: 'Ajustements'),
            Tab(icon: Icon(Icons.trending_down),   text: 'Ventes'),
          ],
        ),
        actions: [
          if (_tab.index == 0)
            DropdownButton<int?>(
              value: _filterProductId,
              hint: const Text('Produit', style: TextStyle(color: Colors.white70, fontSize: 13)),
              dropdownColor: Theme.of(context).colorScheme.surface,
              underline: const SizedBox(),
              icon: const Icon(Icons.filter_alt_outlined, color: Colors.white),
              items: [
                const DropdownMenuItem(value: null, child: Text('Tous')),
                ..._products.map((p) => DropdownMenuItem(
                  value: p['id'] as int,
                  child: Text(p['name'] as String,
                      overflow: TextOverflow.ellipsis),
                )),
              ],
              onChanged: (v) { setState(() => _filterProductId = v); _load(); },
            ),
          IconButton(
            icon: const Icon(Icons.date_range),
            tooltip: 'Période',
            onPressed: _pickDateRange,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Theme.of(context).colorScheme.primary.withOpacity(.08),
                child: Row(children: [
                  const Icon(Icons.date_range, size: 16),
                  const SizedBox(width: 6),
                  Text('${fmt.format(_from)} → ${fmt.format(_to)}'),
                ]),
              ),
              Expanded(
                child: TabBarView(controller: _tab, children: [
                  _AdjustmentsList(adjustments: _adjustments),
                  _SalesMovList(salesMov: _salesMov),
                ]),
              ),
            ]),
    );
  }
}

class _AdjustmentsList extends StatelessWidget {
  final List<Map<String, dynamic>> adjustments;
  const _AdjustmentsList({required this.adjustments});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (adjustments.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.tune_rounded, size: 56, color: theme.colorScheme.onSurface.withOpacity(.3)),
          const SizedBox(height: 8),
          const Text('Aucun ajustement sur cette période'),
        ]),
      );
    }
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: adjustments.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (_, i) {
        final a      = adjustments[i];
        final delta  = (a['delta'] as num).toDouble();
        final isIn   = delta > 0;
        final color  = isIn ? Colors.green : Colors.red;
        final reason = a['reason'] as String? ?? '';
        final emp    = a['employee_name'] as String? ?? '';
        DateTime? dt;
        try { dt = DateTime.parse(a['created_at'] as String); } catch (_) {}
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: color.withOpacity(.15),
              child: Icon(
                isIn ? Icons.add_circle_outline : Icons.remove_circle_outline,
                color: color,
              ),
            ),
            title: Text(a['product_name'] as String,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text([
              if (reason.isNotEmpty) reason,
              if (emp.isNotEmpty) 'par $emp',
            ].join(' • ')),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${isIn ? '+' : ''}${delta.toStringAsFixed(0)}',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16, color: color)),
                if (dt != null)
                  Text(fmt.format(dt),
                      style: TextStyle(fontSize: 11,
                          color: theme.colorScheme.onSurface.withOpacity(.6))),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SalesMovList extends StatelessWidget {
  final List<Map<String, dynamic>> salesMov;
  const _SalesMovList({required this.salesMov});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final symbol   = settings.currencySymbol;
    final theme    = Theme.of(context);
    if (salesMov.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.trending_down, size: 56, color: theme.colorScheme.onSurface.withOpacity(.3)),
          const SizedBox(height: 8),
          const Text('Aucune vente sur cette période'),
        ]),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: salesMov.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (_, i) {
        final m       = salesMov[i];
        final sold    = (m['qty_sold'] as num?)?.toDouble() ?? 0;
        final revenue = (m['revenue'] as num?)?.toDouble() ?? 0;
        final current = (m['current_stock'] as num?)?.toDouble() ?? 0;
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.blue.withOpacity(.12),
              child: const Icon(Icons.inventory_2_outlined, color: Colors.blue),
            ),
            title: Text(m['product_name'] as String,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              'Stock actuel : ${current.toStringAsFixed(0)} ${m['unit'] ?? ''}',
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('−${sold.toStringAsFixed(0)} vendus',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.red)),
                Text('$symbol ${revenue.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 12,
                        color: theme.colorScheme.onSurface.withOpacity(.7))),
              ],
            ),
          ),
        );
      },
    );
  }
}
