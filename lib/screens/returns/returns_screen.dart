import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/database/db.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import 'return_form_screen.dart';

class ReturnsScreen extends StatefulWidget {
  const ReturnsScreen({super.key});
  @override
  State<ReturnsScreen> createState() => _ReturnsScreenState();
}

class _ReturnsScreenState extends State<ReturnsScreen> {
  List<Map<String, dynamic>> _returns = [];
  bool _loading = true;
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to   = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await DB.instance.getReturns(
      from: _from.toIso8601String().substring(0, 10),
      to:   _to.toIso8601String().substring(0, 10),
    );
    if (mounted) setState(() { _returns = data; _loading = false; });
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

  void _newReturn() {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const ReturnFormScreen()))
        .then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final symbol   = settings.currencySymbol;
    final fmt      = DateFormat('dd/MM/yyyy HH:mm');
    final theme    = Theme.of(context);
    final total    = _returns.fold<double>(
        0, (s, r) => s + ((r['total_amount'] as num?)?.toDouble() ?? 0));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Retours & Remboursements'),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            tooltip: 'Période',
            onPressed: _pickDateRange,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newReturn,
        icon: const Icon(Icons.assignment_return_outlined),
        label: const Text('Nouveau retour'),
      ),
      body: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Colors.orange.withOpacity(.1),
          child: Row(children: [
            const Icon(Icons.date_range, size: 16, color: Colors.orange),
            const SizedBox(width: 6),
            Text(
              '${DateFormat('dd/MM/yy').format(_from)} → ${DateFormat('dd/MM/yy').format(_to)}',
              style: const TextStyle(color: Colors.orange),
            ),
            const Spacer(),
            Text('${_returns.length} retour(s) — $symbol ${total.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
          ]),
        ),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_returns.isEmpty)
          Expanded(
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.assignment_return_outlined, size: 64,
                    color: theme.colorScheme.onSurface.withOpacity(.3)),
                const SizedBox(height: 12),
                const Text('Aucun retour sur cette période'),
              ]),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
              itemCount: _returns.length,
              itemBuilder: (_, i) {
                final r         = _returns[i];
                final amount    = (r['total_amount'] as num?)?.toDouble() ?? 0;
                final customer  = r['customer_name'] as String? ?? 'Client comptant';
                final employee  = r['employee_name'] as String? ?? '';
                final reason    = r['reason'] as String? ?? '';
                final createdAt = r['created_at'] as String? ?? '';
                DateTime? dt;
                try { dt = DateTime.parse(createdAt); } catch (_) {}
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ExpansionTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.orange.withOpacity(.15),
                      child: const Icon(Icons.assignment_return_outlined,
                          color: Colors.orange),
                    ),
                    title: Text(customer,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text([
                      'Vente #${r['sale_id']}',
                      if (reason.isNotEmpty) reason,
                    ].join(' • ')),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('$symbol ${amount.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, color: Colors.orange)),
                        if (dt != null)
                          Text(fmt.format(dt),
                              style: TextStyle(fontSize: 11,
                                  color: theme.colorScheme.onSurface.withOpacity(.6))),
                      ],
                    ),
                    children: [
                      _ReturnItemsList(returnId: r['id'] as int, symbol: symbol),
                      if (employee.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Row(children: [
                            const Icon(Icons.badge_outlined, size: 16, color: Colors.grey),
                            const SizedBox(width: 6),
                            Text('Par $employee',
                                style: const TextStyle(color: Colors.grey, fontSize: 13)),
                          ]),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
      ]),
    );
  }
}

class _ReturnItemsList extends StatefulWidget {
  final int returnId;
  final String symbol;
  const _ReturnItemsList({required this.returnId, required this.symbol});

  @override
  State<_ReturnItemsList> createState() => _ReturnItemsListState();
}

class _ReturnItemsListState extends State<_ReturnItemsList> {
  List<Map<String, dynamic>> _items = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    DB.instance.getReturnItems(widget.returnId).then((items) {
      if (mounted) setState(() { _items = items; _loaded = true; });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Padding(padding: EdgeInsets.all(8),
        child: LinearProgressIndicator());
    return Column(
      children: _items.map((item) {
        final qty    = (item['quantity'] as num).toDouble();
        final price  = (item['price'] as num).toDouble();
        final total  = (item['total'] as num).toDouble();
        return ListTile(
          dense: true,
          leading: const Icon(Icons.subdirectory_arrow_right, size: 18, color: Colors.grey),
          title: Text(item['product_name'] as String),
          subtitle: Text('${widget.symbol} ${price.toStringAsFixed(2)} × ${qty.toStringAsFixed(0)}'),
          trailing: Text('${widget.symbol} ${total.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
        );
      }).toList(),
    );
  }
}
