import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/database/db.dart';
import '../../core/utils/helpers.dart';
import '../../providers/settings_provider.dart';

class BankingScreen extends StatefulWidget {
  const BankingScreen({super.key});

  @override
  State<BankingScreen> createState() => _BankingScreenState();
}

class _BankingScreenState extends State<BankingScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<Map<String, dynamic>> _banks = [];
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _expenses = [];
  List<Map<String, dynamic>> _expenseHeads = [];
  int? _selectedBank;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final banks = await DB.instance.getBanks();
    final txns = await DB.instance.getBankTransactions(bankId: _selectedBank);
    final heads = await DB.instance.getExpenseHeads();
    final exps = await DB.instance.getExpenses();
    if (mounted) setState(() {
      _banks = banks;
      _transactions = txns;
      _expenseHeads = heads;
      _expenses = exps;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final sym = context.watch<SettingsProvider>().currencySymbol;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Banque & Dépenses'),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(icon: Icon(Icons.account_balance), text: 'Banques'),
            Tab(icon: Icon(Icons.swap_horiz), text: 'Transactions'),
            Tab(icon: Icon(Icons.receipt_long), text: 'Dépenses'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _buildBanksTab(sym),
                _buildTransactionsTab(sym),
                _buildExpensesTab(sym),
              ],
            ),
    );
  }

  Widget _buildBanksTab(String sym) {
    final totalBalance = _banks.fold(0.0, (s, b) => s + ((b['balance'] as num?)?.toDouble() ?? 0));
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: const Color(0xFF1565C0).withOpacity(0.05),
          child: Row(children: [
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Solde total', style: TextStyle(color: Colors.grey)),
                Text(formatCurrency(totalBalance, symbol: sym),
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1565C0))),
              ],
            )),
            ElevatedButton.icon(
              onPressed: () => _openBankForm(null),
              icon: const Icon(Icons.add),
              label: const Text('Nouvelle banque'),
            ),
          ]),
        ),
        Expanded(
          child: _banks.isEmpty
              ? const Center(child: Text('Aucune banque'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemCount: _banks.length,
                  itemBuilder: (_, i) {
                    final b = _banks[i];
                    final balance = (b['balance'] as num?)?.toDouble() ?? 0;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue.shade50,
                        child: const Icon(Icons.account_balance, color: Colors.blue),
                      ),
                      title: Text(b['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(b['account_number'] as String? ?? 'Sans numéro de compte'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(formatCurrency(balance, symbol: sym),
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: balance >= 0 ? Colors.green : Colors.red)),
                        const SizedBox(width: 8),
                        IconButton(icon: const Icon(Icons.add_circle_outline, color: Colors.green), tooltip: 'Dépôt',
                            onPressed: () => _addTransaction(b['id'] as int, 'deposit')),
                        IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.red), tooltip: 'Retrait',
                            onPressed: () => _addTransaction(b['id'] as int, 'withdrawal')),
                        IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _openBankForm(b)),
                      ]),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTransactionsTab(String sym) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          DropdownButton<int?>(
            value: _selectedBank,
            hint: const Text('Toutes les banques'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Toutes')),
              ..._banks.map((b) => DropdownMenuItem(value: b['id'] as int, child: Text(b['name'] as String))),
            ],
            onChanged: (v) { setState(() => _selectedBank = v); _load(); },
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: () => _selectedBank != null ? _addTransaction(_selectedBank!, 'deposit') : null,
            icon: const Icon(Icons.add),
            label: const Text('Ajouter'),
          ),
        ]),
      ),
      Expanded(
        child: _transactions.isEmpty
            ? const Center(child: Text('Aucune transaction'))
            : ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemCount: _transactions.length,
                itemBuilder: (_, i) {
                  final t = _transactions[i];
                  final type = t['type'] as String;
                  final amount = (t['amount'] as num).toDouble();
                  final isCredit = type == 'deposit';
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isCredit ? Colors.green.shade50 : Colors.red.shade50,
                      child: Icon(isCredit ? Icons.arrow_downward : Icons.arrow_upward,
                          color: isCredit ? Colors.green : Colors.red),
                    ),
                    title: Text(t['description'] as String? ?? _typeLabel(type)),
                    subtitle: Text('${t['bank_name']} • ${formatDate(t['date'] as String?)}'),
                    trailing: Text(
                      '${isCredit ? '+' : '-'} ${formatCurrency(amount, symbol: sym)}',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isCredit ? Colors.green : Colors.red),
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  Widget _buildExpensesTab(String sym) {
    final total = _expenses.fold(0.0, (s, e) => s + ((e['amount'] as num?)?.toDouble() ?? 0));
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(16),
        color: Colors.red.shade50,
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Total dépenses', style: TextStyle(color: Colors.grey)),
            Text(formatCurrency(total, symbol: sym),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red)),
          ])),
          Row(children: [
            OutlinedButton.icon(
              onPressed: _manageHeads,
              icon: const Icon(Icons.category),
              label: const Text('Catégories'),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _addExpense,
              icon: const Icon(Icons.add),
              label: const Text('Dépense'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            ),
          ]),
        ]),
      ),
      Expanded(
        child: _expenses.isEmpty
            ? const Center(child: Text('Aucune dépense'))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemCount: _expenses.length,
                itemBuilder: (_, i) {
                  final e = _expenses[i];
                  return ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFFFEBEE),
                      child: Icon(Icons.receipt_long, color: Colors.red),
                    ),
                    title: Text(e['head_name'] as String? ?? 'Divers'),
                    subtitle: Text('${e['description'] ?? ''} • ${formatDate(e['date'] as String?)}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(formatCurrency((e['amount'] as num).toDouble(), symbol: sym),
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                      IconButton(
                        icon: const Icon(Icons.delete, size: 16, color: Colors.grey),
                        onPressed: () async {
                          await DB.instance.deleteExpense(e['id'] as int);
                          _load();
                        },
                      ),
                    ]),
                  );
                },
              ),
      ),
    ]);
  }

  String _typeLabel(String t) {
    switch (t) { case 'deposit': return 'Dépôt'; case 'withdrawal': return 'Retrait';
      case 'cheque': return 'Chèque'; default: return 'Virement'; }
  }

  Future<void> _openBankForm(Map<String, dynamic>? bank) async {
    await showDialog(context: context, builder: (_) => _BankFormDialog(bank: bank));
    _load();
  }

  Future<void> _addTransaction(int bankId, String defaultType) async {
    await showDialog(context: context, builder: (_) => _TransactionDialog(bankId: bankId, banks: _banks, defaultType: defaultType));
    _load();
  }

  Future<void> _addExpense() async {
    await showDialog(context: context, builder: (_) => _ExpenseDialog(heads: _expenseHeads, banks: _banks));
    _load();
  }

  Future<void> _manageHeads() async {
    await showDialog(context: context, builder: (_) => _ExpenseHeadsDialog(heads: _expenseHeads));
    _load();
  }
}

class _BankFormDialog extends StatefulWidget {
  final Map<String, dynamic>? bank;
  const _BankFormDialog({this.bank});

  @override
  State<_BankFormDialog> createState() => _BankFormDialogState();
}

class _BankFormDialogState extends State<_BankFormDialog> {
  final _nameCtrl = TextEditingController();
  final _accountCtrl = TextEditingController();
  final _balanceCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final b = widget.bank;
    if (b != null) {
      _nameCtrl.text = b['name'] as String;
      _accountCtrl.text = b['account_number'] as String? ?? '';
      _balanceCtrl.text = (b['balance'] as num?)?.toString() ?? '0';
    } else {
      _balanceCtrl.text = '0';
    }
  }

  @override
  void dispose() { for (final c in [_nameCtrl, _accountCtrl, _balanceCtrl]) c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.bank == null ? 'Nouvelle banque' : 'Modifier la banque'),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Nom de la banque *')),
        const SizedBox(height: 12),
        TextField(controller: _accountCtrl, decoration: const InputDecoration(labelText: 'Numéro de compte')),
        const SizedBox(height: 12),
        if (widget.bank == null) TextField(
          controller: _balanceCtrl,
          decoration: const InputDecoration(labelText: 'Solde initial'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.-]'))],
        ),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        ElevatedButton(
          onPressed: () async {
            await DB.instance.upsertBank({
              if (widget.bank?['id'] != null) 'id': widget.bank!['id'],
              'name': _nameCtrl.text.trim(),
              'account_number': _accountCtrl.text.trim().isEmpty ? null : _accountCtrl.text.trim(),
              if (widget.bank == null) 'balance': double.tryParse(_balanceCtrl.text) ?? 0,
            });
            if (context.mounted) Navigator.pop(context);
          },
          child: Text(widget.bank == null ? 'Créer' : 'Mettre à jour'),
        ),
      ],
    );
  }
}

class _TransactionDialog extends StatefulWidget {
  final int bankId;
  final List<Map<String, dynamic>> banks;
  final String defaultType;
  const _TransactionDialog({required this.bankId, required this.banks, required this.defaultType});

  @override
  State<_TransactionDialog> createState() => _TransactionDialogState();
}

class _TransactionDialogState extends State<_TransactionDialog> {
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _refCtrl = TextEditingController();
  late String _type;
  late int _bankId;

  @override
  void initState() { super.initState(); _type = widget.defaultType; _bankId = widget.bankId; }

  @override
  void dispose() { for (final c in [_amountCtrl, _descCtrl, _refCtrl]) c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ajouter une transaction'),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(
          value: _type,
          decoration: const InputDecoration(labelText: 'Type'),
          items: const [
            DropdownMenuItem(value: 'deposit', child: Text('Dépôt')),
            DropdownMenuItem(value: 'withdrawal', child: Text('Retrait')),
            DropdownMenuItem(value: 'cheque', child: Text('Chèque')),
            DropdownMenuItem(value: 'transfer', child: Text('Virement')),
          ],
          onChanged: (v) => setState(() => _type = v!),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          value: _bankId,
          decoration: const InputDecoration(labelText: 'Banque'),
          items: widget.banks.map((b) => DropdownMenuItem(value: b['id'] as int, child: Text(b['name'] as String))).toList(),
          onChanged: (v) => setState(() => _bankId = v!),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _amountCtrl,
          decoration: const InputDecoration(labelText: 'Montant *'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
        ),
        const SizedBox(height: 12),
        TextField(controller: _descCtrl, decoration: const InputDecoration(labelText: 'Description')),
        const SizedBox(height: 12),
        TextField(controller: _refCtrl, decoration: const InputDecoration(labelText: 'Référence / N° chèque')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        ElevatedButton(
          onPressed: () async {
            final amount = double.tryParse(_amountCtrl.text) ?? 0;
            if (amount <= 0) return;
            await DB.instance.addBankTransaction({
              'bank_id': _bankId,
              'type': _type,
              'amount': amount,
              'description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
              'reference': _refCtrl.text.trim().isEmpty ? null : _refCtrl.text.trim(),
              'cheque_number': _type == 'cheque' ? _refCtrl.text.trim() : null,
            });
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _ExpenseDialog extends StatefulWidget {
  final List<Map<String, dynamic>> heads;
  final List<Map<String, dynamic>> banks;
  const _ExpenseDialog({required this.heads, required this.banks});

  @override
  State<_ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<_ExpenseDialog> {
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  int? _headId;
  String? _headName;
  String _payMethod = 'cash';
  int? _bankId;

  @override
  void dispose() { for (final c in [_amountCtrl, _descCtrl]) c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouvelle dépense'),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<int?>(
          value: _headId,
          decoration: const InputDecoration(labelText: 'Catégorie'),
          items: [
            const DropdownMenuItem(value: null, child: Text('Divers')),
            ...widget.heads.map((h) => DropdownMenuItem(value: h['id'] as int, child: Text(h['name'] as String))),
          ],
          onChanged: (v) {
            setState(() {
              _headId = v;
              _headName = v == null ? null : widget.heads.firstWhere((h) => h['id'] == v)['name'] as String;
            });
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _amountCtrl,
          decoration: const InputDecoration(labelText: 'Montant *'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _payMethod,
          decoration: const InputDecoration(labelText: 'Mode de paiement'),
          items: const [
            DropdownMenuItem(value: 'cash', child: Text('Espèces')),
            DropdownMenuItem(value: 'bank', child: Text('Banque')),
            DropdownMenuItem(value: 'card', child: Text('Carte')),
          ],
          onChanged: (v) => setState(() => _payMethod = v!),
        ),
        if (_payMethod == 'bank' && widget.banks.isNotEmpty) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            value: _bankId,
            decoration: const InputDecoration(labelText: 'Banque'),
            items: widget.banks.map((b) => DropdownMenuItem(value: b['id'] as int, child: Text(b['name'] as String))).toList(),
            onChanged: (v) => setState(() => _bankId = v),
          ),
        ],
        const SizedBox(height: 12),
        TextField(controller: _descCtrl, decoration: const InputDecoration(labelText: 'Description')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        ElevatedButton(
          onPressed: () async {
            final amount = double.tryParse(_amountCtrl.text) ?? 0;
            if (amount <= 0) return;
            await DB.instance.addExpense({
              'head_id': _headId,
              'head_name': _headName ?? 'Divers',
              'amount': amount,
              'payment_method': _payMethod,
              'bank_id': _bankId,
              'description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
            });
            if (context.mounted) Navigator.pop(context);
          },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _ExpenseHeadsDialog extends StatefulWidget {
  final List<Map<String, dynamic>> heads;
  const _ExpenseHeadsDialog({required this.heads});

  @override
  State<_ExpenseHeadsDialog> createState() => _ExpenseHeadsDialogState();
}

class _ExpenseHeadsDialogState extends State<_ExpenseHeadsDialog> {
  final _ctrl = TextEditingController();
  late List<Map<String, dynamic>> _heads;

  @override
  void initState() { super.initState(); _heads = List.from(widget.heads); }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _add() async {
    if (_ctrl.text.trim().isEmpty) return;
    await DB.instance.upsertExpenseHead({'name': _ctrl.text.trim()});
    final updated = await DB.instance.getExpenseHeads();
    setState(() { _heads = updated; _ctrl.clear(); });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Catégories de dépenses'),
      content: SizedBox(
        width: 380,
        height: 400,
        child: Column(children: [
          Row(children: [
            Expanded(child: TextField(controller: _ctrl, decoration: const InputDecoration(hintText: 'Nom de la catégorie', isDense: true))),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: _add, child: const Text('Ajouter')),
          ]),
          const SizedBox(height: 12),
          Expanded(child: ListView.builder(
            itemCount: _heads.length,
            itemBuilder: (_, i) => ListTile(
              dense: true,
              leading: const Icon(Icons.label),
              title: Text(_heads[i]['name'] as String),
            ),
          )),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer'))],
    );
  }
}
