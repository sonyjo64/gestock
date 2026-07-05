import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import '../../core/database/db.dart';
import '../../core/utils/helpers.dart';
import '../../core/utils/invoice_pdf.dart';
import '../../providers/settings_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SALES LIST SCREEN – consulter, annuler, imprimer les ventes
// ─────────────────────────────────────────────────────────────────────────────
class SalesListScreen extends StatefulWidget {
  final String? initialFrom;
  final String? initialTo;
  final String? title;

  const SalesListScreen({
    super.key,
    this.initialFrom,
    this.initialTo,
    this.title,
  });

  @override
  State<SalesListScreen> createState() => _SalesListScreenState();
}

class _SalesListScreenState extends State<SalesListScreen> {
  late DateTime _from;
  late DateTime _to;
  String _filterMethod = 'all';  // all | cash | card | credit | voided
  String _search = '';
  bool _loading = true;

  List<Map<String, dynamic>> _sales = [];
  List<Map<String, dynamic>> _filtered = [];

  final _searchCtrl = TextEditingController();

  // ── format helpers ──────────────────────────────────────────────────────────
  String get _fromStr => DateFormat('yyyy-MM-dd').format(_from);
  String get _toStr   => DateFormat('yyyy-MM-dd').format(_to);

  String _fmt(double v) => NumberFormat('#,##0.00', 'fr_FR').format(v);
  String _cur(double v, String sym) => '$sym ${_fmt(v)}';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = widget.initialFrom != null
        ? DateTime.parse(widget.initialFrom!)
        : DateTime(now.year, now.month, 1);
    _to = widget.initialTo != null
        ? DateTime.parse(widget.initialTo!)
        : now;
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── data ────────────────────────────────────────────────────────────────────
  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final data = await DB.instance.getSales(from: _fromStr, to: _toStr);
    if (mounted) {
      setState(() {
        _sales = data;
        _loading = false;
      });
      _applyFilter();
    }
  }

  void _applyFilter() {
    var list = _sales;
    if (_filterMethod == 'voided') {
      list = list.where((s) => s['status'] == 'voided').toList();
    } else if (_filterMethod != 'all') {
      list = list
          .where((s) =>
              s['payment_method'] == _filterMethod &&
              s['status'] != 'voided')
          .toList();
    } else {
      list = list.where((s) => s['status'] != 'voided').toList();
    }
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((s) {
        final name = (s['customer_name'] ?? '').toString().toLowerCase();
        final id   = s['id'].toString();
        return name.contains(q) || id.contains(q);
      }).toList();
    }
    setState(() => _filtered = list);
  }

  Future<void> _pickRange() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (r != null) {
      setState(() { _from = r.start; _to = r.end; });
      await _load();
    }
  }

  // ── totals ──────────────────────────────────────────────────────────────────
  double get _totalRev => _filtered.fold(0.0, (s, x) =>
      s + ((x['total'] as num?)?.toDouble() ?? 0));

  // ── BUILD ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final sp  = context.watch<SettingsProvider>();
    final sym = sp.currencySymbol;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? 'Ventes'),
        actions: [
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.white.withAlpha(30),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.date_range, size: 16),
            label: Text(
                '${DateFormat('dd/MM').format(_from)} – ${DateFormat('dd/MM').format(_to)}'),
            onPressed: _pickRange,
          ),
          IconButton(
              icon: const Icon(Icons.refresh), onPressed: _load, tooltip: 'Actualiser'),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // ── search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Rechercher client ou N° vente…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _search = '');
                          _applyFilter();
                        })
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: (v) {
                setState(() => _search = v);
                _applyFilter();
              },
            ),
          ),
          // ── filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              for (final f in [
                ('all',    'Toutes',  Icons.receipt_long,    Colors.blueGrey),
                ('cash',   'Espèces', Icons.money,           Colors.green),
                ('card',   'Carte',   Icons.credit_card,     Colors.blue),
                ('credit', 'Crédit',  Icons.account_balance_wallet, Colors.orange),
                ('voided', 'Annulées',Icons.cancel,          Colors.red),
              ]) ...[
                _filterChip(f.$1, f.$2, f.$3, f.$4),
                const SizedBox(width: 8),
              ],
            ]),
          ),
          // ── summary bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(children: [
              Text('${_filtered.length} vente${_filtered.length > 1 ? 's' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('Total : ${_cur(_totalRev, sym)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
            ]),
          ),
          // ── list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? _emptyState()
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        separatorBuilder: (_, __) => const SizedBox(height: 4),
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) => _saleCard(_filtered[i], sym, sp),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String key, String label, IconData icon, Color color) {
    final selected = _filterMethod == key;
    return FilterChip(
      selected: selected,
      avatar: Icon(icon, size: 16,
          color: selected ? Colors.white : color),
      label: Text(label),
      selectedColor: color,
      labelStyle: TextStyle(
          color: selected ? Colors.white : null,
          fontWeight: selected ? FontWeight.bold : null),
      onSelected: (_) {
        setState(() => _filterMethod = key);
        _applyFilter();
      },
    );
  }

  // ── sale card ────────────────────────────────────────────────────────────────
  Widget _saleCard(Map<String, dynamic> s, String sym, SettingsProvider sp) {
    final method  = s['payment_method'] as String? ?? 'cash';
    final status  = s['status'] as String? ?? 'completed';
    final total   = (s['total'] as num?)?.toDouble() ?? 0;
    final voided  = status == 'voided';
    final created = s['created_at']?.toString() ?? '';

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showDetail(s, sym, sp),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            // ── left icon
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: voided
                    ? Colors.grey.shade100
                    : _methodColor(method).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                voided ? Icons.cancel_outlined : _methodIcon(method),
                color: voided ? Colors.grey : _methodColor(method),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            // ── center info
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text('#${s['id']}',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13,
                          color: voided ? Colors.grey : null)),
                  const SizedBox(width: 8),
                  if (voided)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(4)),
                      child: const Text('ANNULÉ',
                          style: TextStyle(fontSize: 10, color: Colors.red,
                              fontWeight: FontWeight.bold)),
                    ),
                ]),
                const SizedBox(height: 2),
                Text(
                  s['customer_name']?.toString().isNotEmpty == true
                      ? s['customer_name'].toString()
                      : 'Client comptant',
                  style: TextStyle(fontSize: 12,
                      color: voided ? Colors.grey : Colors.grey.shade700),
                ),
                Text(
                  '${formatDateTime(created)}  •  ${s['employee_name'] ?? ''}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            )),
            // ── right amount
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_cur(total, sym),
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15,
                        color: voided ? Colors.grey : Colors.green.shade700,
                        decoration: voided ? TextDecoration.lineThrough : null)),
                const SizedBox(height: 2),
                Text(_methodLabel(method),
                    style: TextStyle(fontSize: 11,
                        color: voided ? Colors.grey : _methodColor(method))),
              ],
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 18),
          ]),
        ),
      ),
    );
  }

  Widget _emptyState() => Center(child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey),
      const SizedBox(height: 16),
      const Text('Aucune vente trouvée', style: TextStyle(fontSize: 16, color: Colors.grey)),
      const SizedBox(height: 8),
      TextButton.icon(
        icon: const Icon(Icons.date_range),
        label: const Text('Changer la période'),
        onPressed: _pickRange,
      ),
    ],
  ));

  // ══════════════════════════════════════════════════════════════════════════════
  // SALE DETAIL BOTTOM SHEET
  // ══════════════════════════════════════════════════════════════════════════════
  Future<void> _showDetail(
      Map<String, dynamic> s, String sym, SettingsProvider sp) async {
    final items = await DB.instance.getSaleItems(s['id'] as int);
    if (!mounted) return;

    final method   = s['payment_method'] as String? ?? 'cash';
    final status   = s['status'] as String? ?? 'completed';
    final subtotal = (s['subtotal'] as num?)?.toDouble() ?? 0;
    final discount = (s['discount'] as num?)?.toDouble() ?? 0;
    final tax      = (s['tax'] as num?)?.toDouble() ?? 0;
    final total    = (s['total'] as num?)?.toDouble() ?? 0;
    final amtPaid  = (s['amount_paid'] as num?)?.toDouble() ?? 0;
    final change   = (s['change_amount'] as num?)?.toDouble() ?? 0;
    final voided   = status == 'voided';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (_, sc) => Column(children: [
          // handle
          Container(margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          // header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Vente #${s['id']}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                Text(formatDateTime(s['created_at']?.toString()),
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ]),
              const Spacer(),
              if (voided)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.red.shade50, borderRadius: BorderRadius.circular(6)),
                  child: const Text('ANNULÉE',
                      style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.green.shade50, borderRadius: BorderRadius.circular(6)),
                  child: const Text('COMPLÉTÉE',
                      style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                ),
            ]),
          ),
          const SizedBox(height: 8),
          // info row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              _infoPill(Icons.person_outline,
                  s['customer_name']?.toString().isNotEmpty == true
                      ? s['customer_name'].toString() : 'Client comptant'),
              const SizedBox(width: 8),
              _infoPill(_methodIcon(method), _methodLabel(method)),
              if ((s['employee_name'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(width: 8),
                _infoPill(Icons.badge_outlined, s['employee_name'].toString()),
              ],
            ]),
          ),
          const Divider(height: 24),
          // ── items list
          Expanded(child: ListView(
            controller: sc,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              // items table
              Table(
                columnWidths: const {
                  0: FlexColumnWidth(3),
                  1: FlexColumnWidth(1),
                  2: FlexColumnWidth(1.5),
                  3: FlexColumnWidth(1.5),
                },
                children: [
                  // header
                  TableRow(
                    decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest),
                    children: ['Article', 'Qté', 'P.U.', 'Total']
                        .map((h) => Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 6),
                              child: Text(h,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 12)),
                            ))
                        .toList(),
                  ),
                  // rows
                  for (final item in items)
                    TableRow(children: [
                      _tCell(item['product_name']?.toString() ?? ''),
                      _tCell(_fmtQty((item['quantity'] as num?)?.toDouble() ?? 0)),
                      _tCell(_cur((item['price'] as num?)?.toDouble() ?? 0, sym)),
                      _tCell(_cur((item['total'] as num?)?.toDouble() ?? 0, sym)),
                    ]),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              // financials
              if (discount > 0)
                _finRow('Remise', '- ${_cur(discount, sym)}', color: Colors.red),
              if (tax > 0)
                _finRow('TVA', _cur(tax, sym)),
              _finRow('Sous-total', _cur(subtotal, sym)),
              const Divider(),
              _finRow('TOTAL', _cur(total, sym), bold: true, color: Colors.green, large: true),
              const SizedBox(height: 12),
              // payment
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: _methodColor(method).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10)),
                child: Column(children: [
                  _finRow('Mode de paiement', _methodLabel(method)),
                  if (amtPaid > 0) _finRow('Montant reçu', _cur(amtPaid, sym)),
                  if (change > 0)
                    _finRow('Monnaie rendue', _cur(change, sym),
                        color: Colors.green, bold: true),
                ]),
              ),
              const SizedBox(height: 24),
              // action buttons
              if (!voided) ...[
                Row(children: [
                  Expanded(child: OutlinedButton.icon(
                    icon: const Icon(Icons.print),
                    label: const Text('Imprimer le reçu'),
                    onPressed: () => _printReceipt(s, items, sp),
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Annuler la vente'),
                    onPressed: () => _voidSale(s['id'] as int),
                  )),
                ]),
              ] else
                OutlinedButton.icon(
                  icon: const Icon(Icons.print),
                  label: const Text('Imprimer le reçu'),
                  onPressed: () => _printReceipt(s, items, sp),
                ),
              const SizedBox(height: 20),
            ],
          )),
        ]),
      ),
    );
  }

  Widget _infoPill(IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
        color: Colors.grey.shade100, borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: Colors.grey.shade600),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
    ]),
  );

  Widget _tCell(String v) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
    child: Text(v, style: const TextStyle(fontSize: 12)),
  );

  Widget _finRow(String label, String value,
      {bool bold = false, Color? color, bool large = false}) {
    final style = TextStyle(
        fontWeight: bold ? FontWeight.bold : null,
        color: color,
        fontSize: large ? 16 : 13);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(child: Text(label, style: style)),
        Text(value, style: style),
      ]),
    );
  }

  // ── void sale ────────────────────────────────────────────────────────────────
  Future<void> _voidSale(int saleId) async {
    final ok = await confirmDialog(
        context,
        'Annuler la vente #$saleId ?',
        'Le stock sera restauré et la vente marquée comme annulée. Cette action est irréversible.');
    if (!ok || !mounted) return;
    Navigator.pop(context); // close bottom sheet
    final success = await DB.instance.voidSale(saleId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(success
            ? 'Vente #$saleId annulée avec succès'
            : 'Erreur lors de l\'annulation'),
        backgroundColor: success ? Colors.green.shade700 : Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ));
      if (success) await _load();
    }
  }

  // ── print receipt ────────────────────────────────────────────────────────────
  Future<void> _printReceipt(Map<String, dynamic> sale,
      List<Map<String, dynamic>> items, SettingsProvider settings) async {
    final sym      = settings.currencySymbol;
    final total    = (sale['total'] as num?)?.toDouble() ?? 0;
    final discount = (sale['discount'] as num?)?.toDouble() ?? 0;
    final tax      = (sale['tax'] as num?)?.toDouble() ?? 0;
    final amtPaid  = (sale['amount_paid'] as num?)?.toDouble() ?? 0;
    final change   = (sale['change_amount'] as num?)?.toDouble() ?? 0;
    final method   = sale['payment_method'] as String? ?? 'cash';
    final dateStr  = formatDateTime(sale['created_at']?.toString());
    final saleId   = sale['id'] as int;
    final showTax  = settings.settingValue('receipt_show_tax', '1') != '0';
    final footer   = settings.receiptFooter;

    final logo = loadBusinessLogo(settings.logoPath);

    final due = (total - amtPaid) > 0 ? total - amtPaid : 0.0;
    double? customerBalance;
    final customerId = sale['customer_id'] as int?;
    if (customerId != null) {
      final cust = await DB.instance.getCustomerById(customerId);
      if (!mounted) return;
      customerBalance = (cust?['balance'] as num?)?.toDouble();
    }

    final doc = buildLetterInvoice(
      title: 'REÇU N° $saleId',
      dateStr: dateStr,
      businessName: settings.businessName,
      businessAddress: settings.businessAddress,
      businessPhone: settings.businessPhone,
      logo: logo,
      currency: sym,
      lines: items.map((item) {
        final qty = (item['quantity'] as num?)?.toDouble() ?? 1;
        final itTotal = (item['total'] as num?)?.toDouble() ?? 0;
        return InvoiceLine(
          name: (item['product_name'] ?? '').toString(),
          qty: qty,
          unitPrice: qty != 0 ? itTotal / qty : itTotal,
          total: itTotal,
        );
      }).toList(),
      discount: discount,
      tax: showTax && tax > 0 ? tax : 0,
      total: total,
      paymentLabel: paymentMethodLabel(method),
      customerName: sale['customer_name'] as String?,
      amountPaid: amtPaid,
      change: change,
      amountDue: due,
      customerBalance: customerBalance,
      footer: footer,
    );

    await Printing.layoutPdf(
        onLayout: (_) => doc.save(), name: 'Reçu_#$saleId');
  }

  // ── helpers ──────────────────────────────────────────────────────────────────
  String _fmtQty(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toString();

  Color _methodColor(String m) {
    switch (m) {
      case 'cash':   return Colors.green;
      case 'card':   return Colors.blue;
      case 'credit': return Colors.orange;
      default:       return Colors.grey;
    }
  }

  IconData _methodIcon(String m) {
    switch (m) {
      case 'cash':   return Icons.payments_rounded;
      case 'card':   return Icons.credit_card_rounded;
      case 'credit': return Icons.account_balance_wallet_rounded;
      default:       return Icons.swap_horiz;
    }
  }

  String _methodLabel(String m) {
    switch (m) {
      case 'cash':   return 'Espèces';
      case 'card':   return 'Carte';
      case 'credit': return 'Crédit';
      default:       return 'Virement';
    }
  }
}
