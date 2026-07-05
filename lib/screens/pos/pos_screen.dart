import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import '../../core/database/db.dart';
import '../../core/utils/helpers.dart';
import '../../core/utils/invoice_pdf.dart';
import '../sales/sales_screen.dart';
import '../../providers/pos_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  List<Map<String, dynamic>> _products   = [];
  List<Map<String, dynamic>> _categories = [];
  int?   _selectedCat;
  String _search  = '';
  bool   _loading = true;

  final _searchCtrl       = TextEditingController();
  final _searchFocusNode  = FocusNode();
  final _amountReceivedCtrl = TextEditingController(); // montant reçu du client

  // ── Fix: date computed once, not on every rebuild ───────────────────────
  late final String _sessionDate;

  // ── Fix: _productStocks is derived from _products — no separate state ──
  Map<int, double> get _productStocks => {
    for (final p in _products)
      if (p['id'] != null) p['id'] as int: (p['stock'] as num).toDouble()
  };

  @override
  void initState() {
    super.initState();
    _sessionDate = DateFormat('d MMM y').format(DateTime.now());
    _loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocusNode.dispose();
    _amountReceivedCtrl.dispose();
    super.dispose();
  }

  // ─── Data ────────────────────────────────────────────────────────────────
  Future<void> _loadData() async {
    setState(() => _loading = true);
    final cats  = await DB.instance.getCategories();
    final prods = await DB.instance.getProducts(q: _search, catId: _selectedCat);
    if (mounted) setState(() {
      _categories = cats;
      _products   = prods;
      _loading    = false;
    });
  }

  // ── Fix: post-sale refresh skips the category re-fetch ──────────────────
  Future<void> _refreshProducts() => _searchProducts(_search);

  Future<void> _searchProducts(String q) async {
    setState(() { _search = q; _loading = true; });
    final prods = await DB.instance.getProducts(q: q, catId: _selectedCat);
    if (mounted) setState(() { _products = prods; _loading = false; });
  }

  Future<void> _selectCategory(int? id) async {
    setState(() { _selectedCat = id; _loading = true; });
    final prods = await DB.instance.getProducts(q: _search, catId: id);
    if (mounted) setState(() { _products = prods; _loading = false; });
  }

  // ─── Scaffold ────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Caisse'),
        actions: [
          IconButton(
            icon: const Icon(Icons.pause_circle_outline),
            tooltip: 'Mettre en attente',
            onPressed: _holdOrder,
          ),
          IconButton(
            icon: const Icon(Icons.playlist_play_rounded),
            tooltip: 'Commandes en attente',
            onPressed: _showHeld,
          ),
        ],
      ),
      body: Row(
        children: [
          Expanded(flex: 3, child: Column(children: [
            _buildSearchBar(),
            _buildCategoryBar(),
            Expanded(child: _buildProductGrid()),
          ])),
          const VerticalDivider(width: 1),
          SizedBox(width: 390, child: _buildCart()),
        ],
      ),
    );
  }

  // ─── Product grid ────────────────────────────────────────────────────────
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: TextField(
        controller: _searchCtrl,
        focusNode:  _searchFocusNode,
        decoration: InputDecoration(
          hintText: 'Rechercher un produit ou scanner un code-barre…',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _search.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () { _searchCtrl.clear(); _searchProducts(''); })
              : null,
        ),
        onChanged: _searchProducts,
        inputFormatters: [LengthLimitingTextInputFormatter(100)],
      ),
    );
  }

  Widget _buildCategoryBar() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _catChip(null, 'Tous'),
          ..._categories.map((c) => _catChip(c['id'] as int, c['name'] as String)),
        ],
      ),
    );
  }

  Widget _catChip(int? id, String label) {
    final sel = _selectedCat == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: sel,
        onSelected: (_) => _selectCategory(id),
        selectedColor: const Color(0xFF1565C0),
        labelStyle: TextStyle(
          color: sel ? Colors.white : null,
          fontWeight: sel ? FontWeight.bold : null,
        ),
      ),
    );
  }

  Widget _buildProductGrid() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_products.isEmpty) return const Center(child: Text('Aucun produit trouvé'));
    final settings = context.watch<SettingsProvider>();
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180, childAspectRatio: 1.1,
        crossAxisSpacing: 10, mainAxisSpacing: 10,
      ),
      itemCount: _products.length,
      itemBuilder: (_, i) {
        final p       = _products[i];
        final stock   = (p['stock'] as num).toDouble();
        final inCart  = context.watch<PosProvider>().cart
            .where((c) => c.productId == p['id'])
            .fold(0.0, (s, c) => s + c.quantity);
        final noStock = stock <= 0;
        return Card(
          elevation: 2,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: noStock ? null : () => context.read<PosProvider>().addProduct(p),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: hexToColor(p['category_color'] as String? ?? '#1565C0').withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.inventory_2_outlined,
                        color: hexToColor(p['category_color'] as String? ?? '#1565C0'), size: 20),
                  ),
                  const Spacer(),
                  if (inCart > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: Colors.green, borderRadius: BorderRadius.circular(10)),
                      child: Text('${inCart.toInt()}',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                ]),
                const Spacer(),
                Text(p['name'] as String,
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13,
                        color: noStock ? Colors.grey : null),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(children: [
                  Text(
                    formatCurrency((p['price'] as num).toDouble(), symbol: settings.currencySymbol),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1565C0)),
                  ),
                  const Spacer(),
                  Text(
                    noStock ? 'Épuisé' : 'Stock: ${stock.toInt()}',
                    style: TextStyle(fontSize: 10, color: noStock ? Colors.red : Colors.grey),
                  ),
                ]),
              ]),
            ),
          ),
        );
      },
    );
  }

  // ─── CART PANEL ──────────────────────────────────────────────────────────
  Widget _buildCart() {
    final pos      = context.watch<PosProvider>();
    final settings = context.watch<SettingsProvider>();
    final sym      = settings.currencySymbol;

    return Column(children: [
      // ── Header: date + customer ──
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Column(children: [
          Row(children: [
            Icon(Icons.calendar_today_outlined, size: 14, color: Colors.grey.shade500),
            const SizedBox(width: 6),
            Text(_sessionDate,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          ]),
          const SizedBox(height: 8),
          InkWell(
            onTap: _selectCustomer,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Icon(Icons.person_outline, size: 18, color: Colors.grey.shade500),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    pos.customer == null
                        ? 'Client sans compte'
                        : pos.customer!['name'] as String,
                    style: TextStyle(
                      fontSize: 13,
                      color: pos.customer == null ? Colors.grey.shade500 : null,
                    ),
                  ),
                ),
                Icon(Icons.arrow_drop_down, color: Colors.grey.shade500),
              ]),
            ),
          ),
        ]),
      ),

      // ── Item list ──
      Expanded(
        child: pos.cart.isEmpty
            ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.shopping_cart_outlined, size: 48, color: Colors.grey),
                SizedBox(height: 12),
                Text('Panier vide', style: TextStyle(color: Colors.grey)),
              ]))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: pos.cart.length,
                // Fix: index-only key — honest about position-based identity
                itemBuilder: (_, i) {
                  final item  = pos.cart[i];
                  final stock = _productStocks[item.productId] ?? 0.0;
                  return _CartItemCard(
                    key: ValueKey(i),
                    item:             item,
                    stock:            stock,
                    sym:              sym,
                    onPriceChange:    (p) => pos.setPrice(i, p),
                    onQtyChange:      (q) => pos.setQty(i, q),
                    onDiscountChange: (d) => pos.setItemDiscount(i, d),
                    onDelete:         ()  => pos.removeItem(i),
                  );
                },
              ),
      ),

      // ── Footer ──
      Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (pos.orderDiscount > 0) ...[
            _summaryRow('Remise',
                '- ${formatCurrency(pos.orderDiscount, symbol: sym)}', Colors.red),
            const SizedBox(height: 2),
          ],
          if (pos.taxRate > 0) ...[
            _summaryRow('TVA (${pos.taxRate.toStringAsFixed(1)}%)',
                formatCurrency(pos.taxAmount, symbol: sym), null),
            const SizedBox(height: 2),
          ],
          // Remise input
          Row(children: [
            Icon(Icons.local_offer_outlined, size: 18, color: Colors.grey.shade500),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Remise',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                keyboardType: TextInputType.number,
                onChanged: (v) => pos.setOrderDiscount(double.tryParse(v) ?? 0),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          // Montant reçu du client + balance en direct
          Row(children: [
            Icon(Icons.payments_outlined, size: 18, color: Colors.grey.shade500),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _amountReceivedCtrl,
                decoration: InputDecoration(
                  hintText: 'Montant reçu',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
              ),
            ),
          ]),
          if ((double.tryParse(_amountReceivedCtrl.text) ?? 0) > 0) ...[
            const SizedBox(height: 6),
            Builder(builder: (_) {
              final received = double.tryParse(_amountReceivedCtrl.text) ?? 0;
              final diff = pos.total - received;
              if (diff > 0.005) {
                return _summaryRow('Reste à payer',
                    formatCurrency(diff, symbol: sym), Colors.deepOrange);
              } else if (diff < -0.005) {
                return _summaryRow('Monnaie à rendre',
                    formatCurrency(-diff, symbol: sym), Colors.green);
              }
              return _summaryRow('Payé intégralement', '✓', Colors.green);
            }),
          ],
          const SizedBox(height: 8),
          // Row 1: Find + New Bill
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SalesListScreen())),
                icon: const Icon(Icons.history, size: 16),
                label: const Text('Find'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.purple.shade700,
                  side: BorderSide(color: Colors.purple.shade700),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Fix: disabled when cart is empty, consistent with Print/Pay
            Expanded(
              child: OutlinedButton.icon(
                onPressed: pos.cart.isEmpty
                    ? null
                    : () => confirmDialog(context, 'Nouveau ticket',
                            'Vider le panier actuel ?')
                        .then((ok) {
                          if (ok) { pos.clear(); _amountReceivedCtrl.clear(); }
                        }),
                icon: const Icon(Icons.add_box_outlined, size: 16),
                label: const Text('New Bill'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  side: BorderSide(color: Colors.red.shade700),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          // Row 2: Print + Pay
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: pos.cart.isEmpty ? null : _printCurrentBill,
                icon: const Icon(Icons.print_outlined, size: 16),
                label: const Text('Print'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.green.shade700,
                  side: BorderSide(color: Colors.green.shade700),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: pos.cart.isEmpty ? null : _completeSale,
                icon: const Icon(Icons.credit_card_outlined, size: 16),
                label: Text(
                  'Pay ${formatCurrency(pos.total, symbol: sym)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
              ),
            ),
          ]),
        ]),
      ),
    ]);
  }

  Widget _summaryRow(String label, String value, Color? color) {
    return Row(children: [
      Text(label, style: TextStyle(fontSize: 12, color: color ?? Colors.grey.shade700)),
      const Spacer(),
      Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    ]);
  }

  // ─── Payment ─────────────────────────────────────────────────────────────
  Future<void> _completeSale() async {
    final pos      = context.read<PosProvider>();
    final settings = context.read<SettingsProvider>();
    if (pos.cart.isEmpty) return;

    final totalBefore = pos.total;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _PaymentDialog(
          total: totalBefore,
          sym: settings.currencySymbol,
          method: pos.paymentMethod,
          customerName: pos.customer?['name'] as String?,
          initialAmount: double.tryParse(_amountReceivedCtrl.text)),
    );
    if (result == null || !mounted) return;

    pos.setPaymentMethod(result['method'] as String);
    final double? amountPaid = result['amountPaid'] as double?;

    final saleId = await pos.completeSale(
      context.read<AuthProvider>().user?['id'] as int?,
      amountPaid: amountPaid,
    );

    _amountReceivedCtrl.clear();

    if (mounted) {
      final change = (amountPaid != null && amountPaid > totalBefore)
          ? amountPaid - totalBefore : 0.0;
      _showReceiptDialog(saleId, change);
    }
  }

  // ─── Logo helper (shared by both print methods) ───────────────────────────
  Future<pw.MemoryImage?> _loadLogo(SettingsProvider s) async =>
      loadBusinessLogo(s.logoPath);

  // ─── PDF header (shared by both print methods) ────────────────────────────
  // ─── Print current bill (before payment) ─────────────────────────────────
  Future<void> _printCurrentBill() async {
    final pos      = context.read<PosProvider>();
    final settings = context.read<SettingsProvider>();
    final sym      = settings.currencySymbol;
    final logo     = await _loadLogo(settings);
    final footer   = settings.receiptFooter;

    final now     = DateTime.now();
    final dateStr = DateFormat('dd/MM/yyyy  HH:mm').format(now);

    final doc = buildLetterInvoice(
      title: 'BON DE COMMANDE',
      dateStr: dateStr,
      businessName: settings.businessName,
      businessAddress: settings.businessAddress,
      businessPhone: settings.businessPhone,
      logo: logo,
      customerName: pos.customer?['name'] as String?,
      currency: sym,
      lines: pos.cart
          .map((item) => InvoiceLine(
                name: item.name,
                qty: item.quantity,
                unitPrice: item.price,
                total: item.lineTotal,
                unit: item.unit,
              ))
          .toList(),
      discount: pos.orderDiscount,
      tax: pos.taxRate > 0 ? pos.taxAmount : 0,
      taxRate: pos.taxRate > 0 ? pos.taxRate : null,
      total: pos.total,
      footer: footer,
    );
    await Printing.layoutPdf(onLayout: (_) => doc.save(), name: 'Bon_de_commande');
  }

  // ─── Receipt dialog (after sale) ─────────────────────────────────────────
  void _showReceiptDialog(int saleId, double change) {
    final sym = context.read<SettingsProvider>().currencySymbol;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
        title: const Text('Vente enregistrée !'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('N° de vente : #$saleId', style: const TextStyle(color: Colors.grey)),
          if (change > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
              child: Text('Monnaie à rendre : ${formatCurrency(change, symbol: sym)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.green, fontSize: 16)),
            ),
          ],
        ]),
        actions: [
          TextButton(
            // Fix: use _refreshProducts (skips category re-fetch)
            onPressed: () { Navigator.pop(ctx); _refreshProducts(); },
            child: const Text('Fermer'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _refreshProducts();
              _printReceipt(saleId, change);
            },
            icon: const Icon(Icons.print),
            label: const Text('Imprimer reçu'),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0), foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  // ─── Print receipt (after sale) ──────────────────────────────────────────
  Future<void> _printReceipt(int saleId, double change) async {
    // Fix: use routing-aware getSaleById instead of raw DB access
    final sale  = await DB.instance.getSaleById(saleId);
    if (sale == null || !mounted) return;
    final items = await DB.instance.getSaleItems(saleId);
    if (!mounted) return;

    final settings = context.read<SettingsProvider>();
    final sym      = settings.currencySymbol;
    final showTax  = settings.settingValue('receipt_show_tax', '1') != '0';
    final footer   = settings.receiptFooter;
    final logo     = await _loadLogo(settings);

    final total    = (sale['total'] as num).toDouble();
    final discount = (sale['discount'] as num?)?.toDouble() ?? 0;
    final tax      = (sale['tax'] as num?)?.toDouble() ?? 0;
    final amtPaid  = (sale['amount_paid'] as num?)?.toDouble() ?? 0;
    final method   = sale['payment_method'] as String? ?? 'cash';
    final dateStr  = formatDateTime(sale['created_at'] as String?);
    final due      = (total - amtPaid) > 0 ? total - amtPaid : 0.0;

    // Solde courant du client (négatif = doit), si un client est lié à la vente.
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
      lines: items
          .map((item) => InvoiceLine(
                name: item['product_name'] as String,
                qty: (item['quantity'] as num).toDouble(),
                unitPrice: (item['price'] as num?)?.toDouble() ?? 0,
                total: (item['total'] as num).toDouble(),
              ))
          .toList(),
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
    await Printing.layoutPdf(onLayout: (_) => doc.save(), name: 'Reçu_#$saleId');
  }

  // ─── Hold / Recall ───────────────────────────────────────────────────────
  Future<void> _holdOrder() async {
    final pos = context.read<PosProvider>();
    if (pos.cart.isEmpty) return;
    await pos.holdOrder(
        'Commande ${DateTime.now().toIso8601String().substring(11, 16)}');
    if (mounted) showSuccess(context, 'Commande mise en attente');
  }

  Future<void> _showHeld() async {
    final orders = await DB.instance.getHeldOrders();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Commandes en attente'),
        content: SizedBox(
          width: 400,
          child: orders.isEmpty
              ? const Text('Aucune commande en attente')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: orders.length,
                  itemBuilder: (ctx, i) {
                    final o = orders[i];
                    return ListTile(
                      leading: const Icon(Icons.receipt),
                      title: Text(o['label'] as String? ?? 'Commande'),
                      subtitle: Text(formatDateTime(o['created_at'] as String?)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        TextButton(
                          child: const Text('Reprendre'),
                          onPressed: () async {
                            await context.read<PosProvider>().resumeOrder(o);
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            await DB.instance.deleteHeldOrder(o['id'] as int);
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                        ),
                      ]),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer')),
        ],
      ),
    );
  }

  Future<void> _selectCustomer() async {
    final customers = await DB.instance.getCustomers();
    if (!mounted) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _CustomerPickerDialog(customers: customers),
    );
    if (!mounted) return;
    context.read<PosProvider>().setCustomer(result);
  }
}

// ════════════════════════════════════════════════════════════════════════════
// CART ITEM CARD
// ════════════════════════════════════════════════════════════════════════════
class _CartItemCard extends StatefulWidget {
  final CartItem    item;
  final double      stock;
  final String      sym;
  final void Function(double) onPriceChange;
  final void Function(double) onQtyChange;
  final void Function(double) onDiscountChange;
  final VoidCallback          onDelete;

  const _CartItemCard({
    super.key,
    required this.item,
    required this.stock,
    required this.sym,
    required this.onPriceChange,
    required this.onQtyChange,
    required this.onDiscountChange,
    required this.onDelete,
  });

  @override
  State<_CartItemCard> createState() => _CartItemCardState();
}

class _CartItemCardState extends State<_CartItemCard> {
  late final TextEditingController _priceCtrl;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _amountCtrl;

  @override
  void initState() {
    super.initState();
    _priceCtrl  = TextEditingController(text: widget.item.price.toStringAsFixed(2));
    _qtyCtrl    = TextEditingController(text: widget.item.quantity.toStringAsFixed(0));
    _amountCtrl = TextEditingController(text: widget.item.discount.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _qtyCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final noStock = widget.stock <= 0;
    final sym     = widget.sym;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: noStock ? Colors.red.shade400 : Colors.grey.shade300,
          width: noStock ? 1.5 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Row 1 — name + stock badge
          Row(children: [
            Expanded(
              child: Text(widget.item.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
              child: Text(
                '${widget.stock.toInt()} ${widget.item.unit}',
                style: TextStyle(
                    fontSize: 11,
                    color: noStock ? Colors.red.shade600 : Colors.grey.shade700),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          // Row 2 — Amount | Sale Price | Qty | Total | Delete
          Row(children: [
            Expanded(flex: 3, child: _numField('Amount', _amountCtrl, sym,
                (v) => widget.onDiscountChange(double.tryParse(v) ?? 0))),
            const SizedBox(width: 5),
            Expanded(flex: 4, child: _numField('Sale Price', _priceCtrl, sym,
                (v) => widget.onPriceChange(double.tryParse(v) ?? 0))),
            const SizedBox(width: 5),
            Expanded(
              flex: 3,
              child: TextField(
                controller: _qtyCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Qté',
                  labelStyle: const TextStyle(fontSize: 10),
                  suffixText: widget.item.unit,
                  suffixStyle: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
                  border: const OutlineInputBorder(),
                ),
                style: const TextStyle(fontSize: 12),
                onChanged: (v) => widget.onQtyChange(double.tryParse(v) ?? 1),
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
              decoration: BoxDecoration(
                  color: Colors.green.shade600, borderRadius: BorderRadius.circular(6)),
              child: Text(
                '$sym${widget.item.lineTotal.toStringAsFixed(2)}',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, color: Colors.red.shade400, size: 20),
              onPressed: widget.onDelete,
              padding: const EdgeInsets.only(left: 4),
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _numField(String label, TextEditingController ctrl, String sym,
      void Function(String) onChanged) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 10),
        prefixText: '$sym ',
        prefixStyle: const TextStyle(fontSize: 11),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
        border: const OutlineInputBorder(),
      ),
      style: const TextStyle(fontSize: 12),
      onChanged: onChanged,
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// PAYMENT DIALOG
// ════════════════════════════════════════════════════════════════════════════
class _PaymentDialog extends StatefulWidget {
  final double total;
  final String sym;
  final String method;
  final String? customerName;
  final double? initialAmount;
  const _PaymentDialog(
      {required this.total,
      required this.sym,
      required this.method,
      this.customerName,
      this.initialAmount});

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late String _method;
  final _cashCtrl = TextEditingController();

  double get _paid   => double.tryParse(_cashCtrl.text) ?? 0;
  double get _change => _paid > widget.total ? _paid - widget.total : 0;

  @override
  void initState() {
    super.initState();
    _method = widget.method;
    final a = widget.initialAmount;
    if (a != null && a > 0) {
      _cashCtrl.text =
          a == a.roundToDouble() ? a.toInt().toString() : a.toStringAsFixed(2);
    }
  }

  @override
  void dispose() { _cashCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Paiement'),
      content: SizedBox(
        width: 320,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1565C0).withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(children: [
              const Text('Total à payer',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 4),
              Text(formatCurrency(widget.total, symbol: widget.sym),
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold,
                      color: Color(0xFF1565C0))),
            ]),
          ),
          const SizedBox(height: 16),
          const Align(alignment: Alignment.centerLeft,
              child: Text('Mode de paiement',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _method,
            decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'cash',     child: Text('Espèces')),
              DropdownMenuItem(value: 'card',     child: Text('Carte')),
              DropdownMenuItem(value: 'credit',   child: Text('Crédit')),
              DropdownMenuItem(value: 'transfer', child: Text('Virement')),
            ],
            onChanged: (v) => setState(() => _method = v!),
          ),
          if (_method == 'cash') ...[
            const SizedBox(height: 12),
            const Align(alignment: Alignment.centerLeft,
                child: Text('Montant reçu',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
            const SizedBox(height: 8),
            TextField(
              controller: _cashCtrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(
                prefixText: '${widget.sym} ',
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_change > 0) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  const Icon(Icons.payments_outlined, color: Colors.green, size: 18),
                  const SizedBox(width: 8),
                  Text('Monnaie : ${formatCurrency(_change, symbol: widget.sym)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                ]),
              ),
            ],
            // Paiement partiel : le reste devient une dette du client.
            if (_paid > 0 && _paid < widget.total) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.account_balance_wallet_outlined,
                        color: Colors.deepOrange, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                          'Reste à payer : ${formatCurrency(widget.total - _paid, symbol: widget.sym)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                    ),
                  ]),
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 26),
                    child: (widget.customerName != null &&
                            widget.customerName!.isNotEmpty)
                        ? Text('Ajouté au solde de ${widget.customerName}',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade700))
                        : const Text(
                            '⚠ Aucun client sélectionné : le solde ne sera pas enregistré',
                            style: TextStyle(fontSize: 11, color: Colors.red)),
                  ),
                ]),
              ),
            ],
          ],
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler')),
        FilledButton(
          onPressed: () => Navigator.pop(context, {
            'method': _method,
            'amountPaid': (_method == 'cash' && _cashCtrl.text.isNotEmpty) ? _paid : null,
          }),
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1565C0)),
          child: const Text('Confirmer'),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// CUSTOMER PICKER
// ════════════════════════════════════════════════════════════════════════════
class _CustomerPickerDialog extends StatefulWidget {
  final List<Map<String, dynamic>> customers;
  const _CustomerPickerDialog({required this.customers});

  @override
  State<_CustomerPickerDialog> createState() => _CustomerPickerDialogState();
}

class _CustomerPickerDialogState extends State<_CustomerPickerDialog> {
  List<Map<String, dynamic>> _filtered = [];
  final _ctrl = TextEditingController();

  @override
  void initState() { super.initState(); _filtered = widget.customers; }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _filter(String q) {
    setState(() {
      _filtered = q.isEmpty
          ? widget.customers
          : widget.customers.where((c) =>
              (c['name'] as String).toLowerCase().contains(q.toLowerCase()) ||
              (c['phone'] as String? ?? '').contains(q)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Choisir un client'),
      content: SizedBox(
        width: 400, height: 400,
        child: Column(children: [
          TextField(
            controller: _ctrl,
            decoration: const InputDecoration(
                hintText: 'Rechercher…', prefixIcon: Icon(Icons.search)),
            onChanged: _filter,
          ),
          const SizedBox(height: 8),
          Expanded(child: ListView(children: [
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Client de passage'),
              onTap: () => Navigator.pop(context, null),
            ),
            const Divider(),
            ..._filtered.map((c) => ListTile(
              leading: CircleAvatar(child: Text((c['name'] as String)[0])),
              title: Text(c['name'] as String),
              subtitle: Text(c['phone'] as String? ?? ''),
              trailing: c['type'] == 'wholesale'
                  ? const Chip(label: Text('Gros'), backgroundColor: Colors.blue)
                  : null,
              onTap: () => Navigator.pop(context, c),
            )),
          ])),
        ]),
      ),
    );
  }
}
