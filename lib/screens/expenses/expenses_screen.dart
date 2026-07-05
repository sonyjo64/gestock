import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/database/db.dart';
import '../../providers/settings_provider.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});
  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<Map<String, dynamic>> _expenses  = [];
  List<Map<String, dynamic>> _heads     = [];
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
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final fStr = _from.toIso8601String().substring(0, 10);
    final tStr = _to.toIso8601String().substring(0, 10);
    final results = await Future.wait([
      DB.instance.getExpenses(from: fStr, to: tStr),
      DB.instance.getExpenseHeads(),
    ]);
    if (mounted) setState(() {
      _expenses = results[0];
      _heads    = results[1];
      _loading  = false;
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

  Future<void> _showForm([Map<String, dynamic>? expense]) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _ExpenseFormDialog(expense: expense, heads: _heads),
    );
    if (result == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer la dépense'),
        content: const Text('Cette dépense sera supprimée définitivement.'),
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
      await DB.instance.deleteExpense(e['id'] as int);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final symbol   = settings.currencySymbol;
    final fmt      = DateFormat('dd/MM/yy');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dépenses'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(icon: Icon(Icons.list_alt), text: 'Liste'),
            Tab(icon: Icon(Icons.category_outlined), text: 'Catégories'),
          ],
        ),
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
        onPressed: () => _showForm(),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle dépense'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(controller: _tab, children: [
              _ExpensesList(
                expenses: _expenses,
                symbol: symbol,
                fmt: fmt,
                from: _from,
                to: _to,
                onEdit: _showForm,
                onDelete: _delete,
              ),
              _HeadsTab(heads: _heads, onRefresh: _load),
            ]),
    );
  }
}

class _ExpensesList extends StatelessWidget {
  final List<Map<String, dynamic>> expenses;
  final String symbol;
  final DateFormat fmt;
  final DateTime from, to;
  final void Function(Map<String, dynamic>) onEdit;
  final void Function(Map<String, dynamic>) onDelete;

  const _ExpensesList({
    required this.expenses, required this.symbol, required this.fmt,
    required this.from, required this.to,
    required this.onEdit, required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final total = expenses.fold<double>(
        0, (s, e) => s + ((e['amount'] as num?)?.toDouble() ?? 0));
    final theme = Theme.of(context);

    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: theme.colorScheme.primary.withOpacity(.08),
        child: Row(children: [
          Icon(Icons.date_range, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text('${fmt.format(from)} → ${fmt.format(to)}',
              style: TextStyle(color: theme.colorScheme.primary)),
          const Spacer(),
          Text('Total : $symbol ${total.toStringAsFixed(2)}',
              style: TextStyle(fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary)),
        ]),
      ),
      if (expenses.isEmpty)
        Expanded(
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.receipt_long_outlined, size: 56,
                  color: theme.colorScheme.onSurface.withOpacity(.3)),
              const SizedBox(height: 8),
              const Text('Aucune dépense sur cette période'),
            ]),
          ),
        )
      else
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
            itemCount: expenses.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (_, i) {
              final e = expenses[i];
              final amount = (e['amount'] as num).toDouble();
              final head   = e['head_name'] as String? ?? 'Divers';
              final date   = e['date'] as String? ?? '';
              final desc   = e['description'] as String? ?? '';
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.red.withOpacity(.12),
                    child: const Icon(Icons.receipt_long_outlined, color: Colors.red),
                  ),
                  title: Text(head, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: desc.isNotEmpty ? Text(desc, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Column(mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('$symbol ${amount.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                      Text(date.length >= 10 ? fmt.format(DateTime.parse(date)) : date,
                          style: TextStyle(fontSize: 11,
                              color: theme.colorScheme.onSurface.withOpacity(.6))),
                    ]),
                    const SizedBox(width: 4),
                    PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'edit')   onEdit(e);
                        if (v == 'delete') onDelete(e);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Row(children: [
                          Icon(Icons.edit_outlined, size: 18), SizedBox(width: 8), Text('Modifier'),
                        ])),
                        PopupMenuItem(value: 'delete', child: Row(children: [
                          Icon(Icons.delete_outline, size: 18, color: Colors.red), SizedBox(width: 8),
                          Text('Supprimer', style: TextStyle(color: Colors.red)),
                        ])),
                      ],
                    ),
                  ]),
                ),
              );
            },
          ),
        ),
    ]);
  }
}

class _HeadsTab extends StatelessWidget {
  final List<Map<String, dynamic>> heads;
  final VoidCallback onRefresh;
  const _HeadsTab({required this.heads, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          const Text('Catégories de dépenses',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          FilledButton.icon(
            onPressed: () async {
              final r = await showDialog<bool>(
                context: context,
                builder: (_) => const _HeadFormDialog(),
              );
              if (r == true) onRefresh();
            },
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Ajouter'),
          ),
        ]),
      ),
      Expanded(
        child: heads.isEmpty
            ? const Center(child: Text('Aucune catégorie'))
            : ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: heads.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final h = heads[i];
                  return ListTile(
                    leading: const Icon(Icons.label_outline),
                    title: Text(h['name'] as String),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () async {
                        await DB.instance.deleteExpenseHead(h['id'] as int);
                        onRefresh();
                      },
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}

class _HeadFormDialog extends StatefulWidget {
  const _HeadFormDialog();
  @override
  State<_HeadFormDialog> createState() => _HeadFormDialogState();
}

class _HeadFormDialogState extends State<_HeadFormDialog> {
  final _ctrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (_ctrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    await DB.instance.upsertExpenseHead({'name': _ctrl.text.trim()});
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nouvelle catégorie'),
    content: TextField(
      controller: _ctrl,
      decoration: const InputDecoration(
          labelText: 'Nom de la catégorie', border: OutlineInputBorder()),
      autofocus: true,
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
      ElevatedButton(
        onPressed: _saving ? null : _save,
        child: _saving
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Text('Créer'),
      ),
    ],
  );
}

class _ExpenseFormDialog extends StatefulWidget {
  final Map<String, dynamic>? expense;
  final List<Map<String, dynamic>> heads;
  const _ExpenseFormDialog({this.expense, required this.heads});
  @override
  State<_ExpenseFormDialog> createState() => _ExpenseFormDialogState();
}

class _ExpenseFormDialogState extends State<_ExpenseFormDialog> {
  final _formKey  = GlobalKey<FormState>();
  final _amtCtrl  = TextEditingController();
  final _descCtrl = TextEditingController();
  int? _headId;
  String _headName = '';
  String _method   = 'cash';
  DateTime _date   = DateTime.now();
  bool _saving     = false;

  @override
  void initState() {
    super.initState();
    final e = widget.expense;
    if (e != null) {
      _amtCtrl.text  = (e['amount'] as num).toStringAsFixed(2);
      _descCtrl.text = e['description'] as String? ?? '';
      _headId        = e['head_id'] as int?;
      _headName      = e['head_name'] as String? ?? '';
      _method        = e['payment_method'] as String? ?? 'cash';
      final d = e['date'] as String?;
      if (d != null && d.length >= 10) _date = DateTime.parse(d);
    }
  }

  @override
  void dispose() { _amtCtrl.dispose(); _descCtrl.dispose(); super.dispose(); }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_headId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sélectionnez une catégorie')));
      return;
    }
    setState(() => _saving = true);
    final data = {
      if (widget.expense?['id'] != null) 'id': widget.expense!['id'],
      'head_id':        _headId,
      'head_name':      _headName,
      'amount':         double.parse(_amtCtrl.text.replaceAll(',', '.')),
      'payment_method': _method,
      'description':    _descCtrl.text.trim(),
      'date':           _date.toIso8601String().substring(0, 10),
    };
    if (widget.expense != null) {
      await DB.instance.updateExpense(data);
    } else {
      await DB.instance.addExpense(data);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.expense != null;
    final fmt    = DateFormat('dd/MM/yyyy');
    return AlertDialog(
      title: Text(isEdit ? 'Modifier la dépense' : 'Nouvelle dépense'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<int>(
                value: _headId,
                decoration: const InputDecoration(
                    labelText: 'Catégorie *', border: OutlineInputBorder()),
                items: widget.heads.map((h) => DropdownMenuItem(
                  value: h['id'] as int,
                  child: Text(h['name'] as String),
                )).toList(),
                onChanged: (v) {
                  final h = widget.heads.firstWhere((x) => x['id'] == v);
                  setState(() { _headId = v; _headName = h['name'] as String; });
                },
                validator: (v) => v == null ? 'Requis' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amtCtrl,
                decoration: const InputDecoration(
                    labelText: 'Montant *', border: OutlineInputBorder()),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Requis';
                  if (double.tryParse(v.replaceAll(',', '.')) == null) return 'Invalide';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _method,
                decoration: const InputDecoration(
                    labelText: 'Mode de paiement', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'cash',     child: Text('Espèces')),
                  DropdownMenuItem(value: 'card',     child: Text('Carte')),
                  DropdownMenuItem(value: 'transfer', child: Text('Virement')),
                ],
                onChanged: (v) => setState(() => _method = v!),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                      labelText: 'Date', border: OutlineInputBorder()),
                  child: Row(children: [
                    Text(fmt.format(_date)),
                    const Spacer(),
                    const Icon(Icons.calendar_today, size: 16),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(
                    labelText: 'Description', border: OutlineInputBorder()),
                maxLines: 2,
              ),
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
              : Text(isEdit ? 'Enregistrer' : 'Ajouter'),
        ),
      ],
    );
  }
}
