import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:file_selector/file_selector.dart';
import '../../core/database/db.dart';
import '../../core/utils/invoice_pdf.dart';
import '../../providers/settings_provider.dart';
import '../sales/sales_screen.dart';
import '../products/products_screen.dart';
import '../stock/stock_screen.dart';
import '../employees/employees_screen.dart';
import '../products/product_form_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// REPORTS SCREEN  –  6 tabs
// ─────────────────────────────────────────────────────────────────────────────
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with TickerProviderStateMixin {
  late TabController _tab;

  // ── date state ──────────────────────────────────────────────────────────────
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to   = DateTime.now();
  DateTime _dailyDate = DateTime.now();

  // ── sub-report selection (tab 6) ────────────────────────────────────────────
  int _subIdx = 0;

  // ── PDF report state (tab 7) ─────────────────────────────────────────────
  String _pdfPeriod = 'monthly';
  DateTime _pdfDate = DateTime.now();
  bool _pdfGenerating = false;
  Map<String, bool> _pdfSections = {
    'sales': true,
    'products': true,
    'payments': true,
    'employees': true,
    'stock': true,
  };

  // ── data ────────────────────────────────────────────────────────────────────
  bool _loading = true;
  Map<String, dynamic> _overview  = {};
  Map<String, dynamic> _daily     = {};
  Map<String, dynamic> _report    = {};
  Map<String, dynamic> _analysis  = {};
  List<Map<String, dynamic>> _movements = [];
  List<Map<String, dynamic>> _stockLow   = [];
  List<Map<String, dynamic>> _stockOut   = [];
  List<Map<String, dynamic>> _categories = [];

  // ── article filter ──────────────────────────────────────────────────────────
  String _articleSearch = '';
  String _articleSort   = 'rev'; // 'rev' | 'qty' | 'name'
  final _articleSearchCtrl = TextEditingController();

  // ── helpers ─────────────────────────────────────────────────────────────────
  String get _fromStr => DateFormat('yyyy-MM-dd').format(_from);
  String get _toStr   => DateFormat('yyyy-MM-dd').format(_to);
  String get _dayStr  => DateFormat('yyyy-MM-dd').format(_dailyDate);

  String _fmt(double v) => NumberFormat('#,##0.##', 'fr_FR').format(v);
  String _cur(double v, String sym) =>
      '$sym ${NumberFormat('#,##0.00', 'fr_FR').format(v)}';

  // ── lifecycle ───────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 7, vsync: this);
    _tab.addListener(() {
      if (!_tab.indexIsChanging) {
        setState(() {});          // refresh AppBar actions
        _loadForTab(_tab.index);
      }
    });
    _loadAll();
  }

  @override
  void dispose() {
    _tab.dispose();
    _articleSearchCtrl.dispose();
    super.dispose();
  }

  // ── loaders ─────────────────────────────────────────────────────────────────
  Future<void> _loadAll() async {
    if (!mounted) return;
    setState(() => _loading = true);
    await _loadOverview();
    await _loadDaily();
    await _loadRange();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadForTab(int idx) async {
    if (idx == 0) {
      await _loadOverview();
    } else if (idx == 1) {
      await _loadDaily();
    } else {
      await _loadRange();
    }
  }

  Future<void> _loadOverview() async {
    final d = await DB.instance.getDashboard();
    if (mounted) setState(() => _overview = d);
  }

  Future<void> _loadDaily() async {
    final d = await DB.instance.getDailySummary(_dayStr);
    if (mounted) setState(() => _daily = d);
  }

  Future<void> _loadRange() async {
    final r    = await DB.instance.getReport(_fromStr, _toStr);
    final a    = await DB.instance.getSalesAnalysis(_fromStr, _toStr);
    final mv   = await DB.instance.getStockMovements(_fromStr, _toStr);
    final sl   = await DB.instance.getStockProducts(filter: 'low');
    final so   = await DB.instance.getStockProducts(filter: 'out');
    final cats = await DB.instance.getCategories();
    if (mounted) setState(() {
      _report     = r;
      _analysis   = a;
      _movements  = mv;
      _stockLow   = sl;
      _stockOut   = so;
      _categories = cats;
    });
  }

  // ── navigation ───────────────────────────────────────────────────────────────
  void _push(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen))
        .then((_) => _loadAll());
  }

  /// Open the ProductFormScreen for a specific product
  Future<void> _editProduct(int productId) async {
    // Use cached categories list; fetch only if not yet loaded
    final cats  = _categories.isNotEmpty
        ? _categories
        : await DB.instance.getCategories();
    final prods = await DB.instance.getProducts();
    if (!mounted) return;
    final List<Map<String, dynamic>> matches =
        prods.where((p) => p['id'] == productId).toList();
    if (matches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Produit introuvable')));
      return;
    }
    await Navigator.push(context, MaterialPageRoute(
        builder: (_) => ProductFormScreen(
            product: matches.first, categories: cats)));
    if (mounted) _loadAll();
  }

  /// Inline stock-adjustment dialog for a product map (must have 'id','name','stock')
  Future<void> _adjustStockDialog(Map<String, dynamic> product) async {
    final name    = product['name']?.toString() ??
                    product['product_name']?.toString() ?? '';
    final current = (product['stock'] as num?)?.toDouble() ?? 0;
    final ctrl    = TextEditingController(text: current.toStringAsFixed(0));
    final result  = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ajuster le stock'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 4),
            Text('Stock actuel : ${current.toStringAsFixed(0)} unités',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Nouveau stock',
                border: OutlineInputBorder(),
                suffixText: 'unités',
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () {
                final v = double.tryParse(
                    ctrl.text.replaceAll(',', '.').trim());
                Navigator.pop(ctx, v);
              },
              child: const Text('Enregistrer')),
        ],
      ),
    );
    if (result != null && mounted) {
      await DB.instance.adjustStock(product['id'] as int, result - current);
      _loadAll();
    }
  }

  // ── article filter helpers ───────────────────────────────────────────────────
  List<Map<String, dynamic>> _applyArticleFilter(List rawItems) {
    var list = rawItems.cast<Map<String, dynamic>>().toList();
    if (_articleSearch.isNotEmpty) {
      final q = _articleSearch.toLowerCase();
      list = list
          .where((m) =>
              (m['product_name'] as String? ?? '').toLowerCase().contains(q))
          .toList();
    }
    if (_articleSort == 'rev') {
      list.sort((a, b) =>
          ((b['rev'] as num?) ?? 0).compareTo((a['rev'] as num?) ?? 0));
    } else if (_articleSort == 'qty') {
      list.sort((a, b) =>
          ((b['qty'] as num?) ?? 0).compareTo((a['qty'] as num?) ?? 0));
    } else {
      list.sort((a, b) =>
          (a['product_name'] as String? ?? '')
              .compareTo(b['product_name'] as String? ?? ''));
    }
    return list;
  }

  Widget _articleFilterBar() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 240,
            child: TextField(
              controller: _articleSearchCtrl,
              decoration: InputDecoration(
                hintText: 'Rechercher un article...',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _articleSearch.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _articleSearchCtrl.clear();
                          setState(() => _articleSearch = '');
                        })
                    : null,
                isDense: true,
                border: const OutlineInputBorder(),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              ),
              onChanged: (v) => setState(() => _articleSearch = v),
            ),
          ),
          const Text('Trier :', style: TextStyle(fontSize: 13)),
          ChoiceChip(
            label: const Text('Meilleur CA', style: TextStyle(fontSize: 12)),
            selected: _articleSort == 'rev',
            onSelected: (s) { if (s) setState(() => _articleSort = 'rev'); },
          ),
          ChoiceChip(
            label: const Text('Quantité', style: TextStyle(fontSize: 12)),
            selected: _articleSort == 'qty',
            onSelected: (s) { if (s) setState(() => _articleSort = 'qty'); },
          ),
          ChoiceChip(
            label: const Text('Nom A→Z', style: TextStyle(fontSize: 12)),
            selected: _articleSort == 'name',
            onSelected: (s) { if (s) setState(() => _articleSort = 'name'); },
          ),
        ],
      ),
    );
  }

  // ── date pickers ─────────────────────────────────────────────────────────────

  Future<void> _pickRange() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (r != null) {
      setState(() { _from = r.start; _to = r.end; });
      await _loadRange();
    }
  }

  Future<void> _pickDay() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _dailyDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (d != null) {
      setState(() => _dailyDate = d);
      await _loadDaily();
    }
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final sym = context.watch<SettingsProvider>().currencySymbol;
    return Scaffold(
      floatingActionButton: _tab.index >= 1 && _tab.index <= 5
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.list_alt_rounded),
              label: const Text('Toutes les ventes'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SalesListScreen(
                    initialFrom: _tab.index == 1
                        ? _dayStr
                        : _fromStr,
                    initialTo: _tab.index == 1
                        ? _dayStr
                        : _toStr,
                    title: 'Ventes',
                  ),
                ),
              ).then((_) => _loadAll()),
            )
          : null,
      appBar: AppBar(
        title: const Text('Rapports'),
        actions: [
          if (_tab.index == 1)
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.white.withAlpha(30),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(DateFormat('dd/MM/yyyy').format(_dailyDate)),
              onPressed: _pickDay,
            ),
          if (_tab.index >= 2 && _tab.index <= 5)
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
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
            onPressed: _loadAll,
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: "Vue d'ensemble"),
            Tab(text: 'Quotidien'),
            Tab(text: 'Aperçu'),
            Tab(text: 'Par article'),
            Tab(text: 'Caisse'),
            Tab(text: 'Tous les rapports'),
            Tab(icon: Icon(Icons.picture_as_pdf_rounded), text: 'Rapport PDF'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tab,
              children: [
                _tabOverview(sym),
                _tabDaily(sym),
                _tabApercu(sym),
                _tabParArticle(sym),
                _tabCaisse(sym),
                _tabTousLesRapports(sym),
                _tabPdfReport(sym),
              ],
            ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // TAB 1 – Vue d'ensemble
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _tabOverview(String sym) {
    if (_overview.isEmpty) return const Center(child: CircularProgressIndicator());
    final todayTotal    = (_overview['today_total']    as num?)?.toDouble() ?? 0;
    final todayOrders   = (_overview['today_orders']   as num?)?.toInt()   ?? 0;
    final totalProducts = (_overview['total_products'] as num?)?.toInt()   ?? 0;
    final totalCustomers= (_overview['total_customers']as num?)?.toInt()   ?? 0;
    final lowStock      = (_overview['low_stock']      as num?)?.toInt()   ?? 0;
    final monthRevenue  = (_overview['month_revenue']  as num?)?.toDouble()  ?? 0;
    final monthProfit   = (_overview['month_profit']   as num?)?.toDouble()  ?? 0;
    final weekSales     = (_overview['week_sales']     as List?) ?? [];
    final topProducts   = (_overview['top_products']   as List?) ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── KPI row 1
          Row(children: [
            _kpiExpanded("Ventes auj.", _cur(todayTotal, sym), Icons.today,           Colors.blue),
            const SizedBox(width: 10),
            _kpiExpanded('Commandes',  '$todayOrders',          Icons.receipt_long,    Colors.green),
            const SizedBox(width: 10),
            _kpiExpanded('Stock faible','$lowStock',            Icons.warning_amber,
                lowStock > 0 ? Colors.orange : Colors.grey),
            const SizedBox(width: 10),
            _kpiExpanded('Clients',    '$totalCustomers',       Icons.people,          Colors.purple),
          ]),
          const SizedBox(height: 10),
          // ── KPI row 2
          Row(children: [
            _kpiExpanded('CA ce mois',     _cur(monthRevenue, sym), Icons.bar_chart,    Colors.teal),
            const SizedBox(width: 10),
            _kpiExpanded('Bénéfice mois',  _cur(monthProfit,  sym), Icons.trending_up,  Colors.indigo),
            const SizedBox(width: 10),
            _kpiExpanded('Total produits', '$totalProducts',         Icons.inventory_2,  Colors.brown),
            const SizedBox(width: 10),
            const Expanded(child: SizedBox()),
          ]),
          const SizedBox(height: 24),
          _secTitle('Ventes – 7 derniers jours'),
          const SizedBox(height: 8),
          SizedBox(
            height: 200,
            child: weekSales.isEmpty
                ? _empty('Aucune vente cette semaine')
                : LineChart(_weekChart(weekSales)),
          ),
          const SizedBox(height: 24),
          _secTitle('Top 5 produits (30 jours)'),
          const SizedBox(height: 6),
          if (topProducts.isEmpty)
            _empty('Aucune vente')
          else
            ...topProducts.asMap().entries.map((e) {
              final p   = e.value as Map;
              final rev = (p['rev'] as num?)?.toDouble() ?? 0;
              final qty = (p['qty'] as num?)?.toDouble() ?? 0;
              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  backgroundColor: Colors.blue.shade100,
                  child: Text('${e.key + 1}',
                      style: TextStyle(color: Colors.blue.shade800, fontWeight: FontWeight.bold)),
                ),
                title: Text(p['product_name']?.toString() ?? ''),
                subtitle: Text('${_fmt(qty)} unités vendues'),
                trailing: Text(_cur(rev, sym),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              );
            }),
        ],
      ),
    );
  }

  LineChartData _weekChart(List data) {
    final spots = <FlSpot>[
      for (int i = 0; i < data.length; i++)
        FlSpot(i.toDouble(), (data[i]['t'] as num?)?.toDouble() ?? 0),
    ];
    if (spots.isEmpty) return LineChartData();
    return LineChartData(
      gridData: const FlGridData(show: true, drawVerticalLine: false),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles:  const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 56)),
        bottomTitles: AxisTitles(sideTitles: SideTitles(
          showTitles: true,
          getTitlesWidget: (v, _) {
            final i = v.toInt();
            if (i < 0 || i >= data.length) return const SizedBox();
            final d = data[i]['d']?.toString() ?? '';
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(d.length >= 10 ? d.substring(5) : d,
                  style: const TextStyle(fontSize: 10)),
            );
          },
        )),
      ),
      lineBarsData: [LineChartBarData(
        spots: spots, isCurved: true, color: Colors.blue, barWidth: 3,
        dotData: const FlDotData(show: true),
        belowBarData: BarAreaData(show: true,
            color: Colors.blue.withValues(alpha: 0.1)),
      )],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // TAB 2 – Quotidien
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _tabDaily(String sym) {
    if (_daily.isEmpty) return const Center(child: CircularProgressIndicator());
    final sum    = _daily['summary'] as Map? ?? {};
    final byHour = (_daily['by_hour'] as List?) ?? [];
    final sales  = (_daily['sales']   as List?) ?? [];
    final profit = (_daily['profit']  as num?)?.toDouble() ?? 0;
    final revenue = (sum['revenue']   as num?)?.toDouble() ?? 0;
    final orders  = (sum['orders']    as num?)?.toInt()   ?? 0;
    final cash    = (sum['cash']      as num?)?.toDouble() ?? 0;
    final card    = (sum['card']      as num?)?.toDouble() ?? 0;
    final credit  = (sum['credit']    as num?)?.toDouble() ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _kpiExpanded('Total',      _cur(revenue, sym), Icons.point_of_sale, Colors.blue),
          const SizedBox(width: 10),
          _kpiExpanded('Commandes',  '$orders',           Icons.receipt,       Colors.green),
          const SizedBox(width: 10),
          _kpiExpanded('Bénéfice',   _cur(profit, sym),  Icons.trending_up,   Colors.teal),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _kpiExpanded('Espèces', _cur(cash,   sym), Icons.money,                   Colors.orange),
          const SizedBox(width: 10),
          _kpiExpanded('Carte',   _cur(card,   sym), Icons.credit_card,             Colors.indigo),
          const SizedBox(width: 10),
          _kpiExpanded('Crédit',  _cur(credit, sym), Icons.account_balance_wallet,  Colors.red),
        ]),
        const SizedBox(height: 24),
        _secTitle('Ventes par heure'),
        const SizedBox(height: 8),
        if (byHour.isEmpty)
          _empty('Aucune vente ce jour')
        else
          SizedBox(height: 180, child: BarChart(_hourChart(byHour))),
        const SizedBox(height: 24),
        _secTitle('Liste des ventes (${sales.length})'),
        const SizedBox(height: 6),
        if (sales.isEmpty)
          _empty('Aucune vente')
        else
          ...sales.map((s) {
            final sm = s as Map;
            final t  = (sm['total'] as num?)?.toDouble() ?? 0;
            final at = sm['created_at']?.toString() ?? '';
            return Card(
              margin: const EdgeInsets.only(bottom: 6),
              clipBehavior: Clip.hardEdge,
              child: ListTile(
                dense: true,
                leading: CircleAvatar(child: Text('#${sm['id']}')),
                title: Text(sm['customer_name']?.toString() ?? 'Client comptant'),
                subtitle: Text(
                  '${at.length >= 16 ? at.substring(11, 16) : ''}'
                  '  •  ${sm['payment_method'] ?? ''}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(_cur(t, sym),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                ]),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => SalesListScreen(
                    initialFrom: _dayStr,
                    initialTo: _dayStr,
                    title: 'Ventes du ${DateFormat('dd/MM/yyyy').format(_dailyDate)}',
                  )),
                ).then((_) => _loadDaily()),
              ),
            );
          }),
      ]),
    );
  }

  BarChartData _hourChart(List data) {
    final groups = data.map((h) {
      final hour = int.tryParse(h['hour']?.toString() ?? '0') ?? 0;
      final t    = (h['t'] as num?)?.toDouble() ?? 0;
      return BarChartGroupData(x: hour, barRods: [
        BarChartRodData(toY: t, color: Colors.blue, width: 12,
            borderRadius: BorderRadius.circular(3)),
      ]);
    }).toList();
    return BarChartData(
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles:  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(sideTitles: SideTitles(
          showTitles: true,
          getTitlesWidget: (v, _) =>
              Text('${v.toInt()}h', style: const TextStyle(fontSize: 9)),
        )),
      ),
      barGroups: groups,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // TAB 3 – Aperçu (date range)
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _tabApercu(String sym) {
    if (_report.isEmpty) return const Center(child: CircularProgressIndicator());
    final sum    = _report['summary'] as Map? ?? {};
    final byDay  = (_report['by_day'] as List?) ?? [];
    final rev    = (sum['revenue']  as num?)?.toDouble() ?? 0;
    final orders = (sum['orders']   as num?)?.toInt()   ?? 0;
    final disc   = (sum['discount'] as num?)?.toDouble() ?? 0;
    final tax    = (sum['tax']      as num?)?.toDouble() ?? 0;
    final profit = (_report['profit'] as num?)?.toDouble() ?? 0;
    final cash   = (sum['cash']    as num?)?.toDouble() ?? 0;
    final card   = (sum['card']    as num?)?.toDouble() ?? 0;
    final credit = (sum['credit']  as num?)?.toDouble() ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _kpiExpanded("Chiffre d'aff.", _cur(rev,    sym), Icons.bar_chart,     Colors.blue),
          const SizedBox(width: 10),
          _kpiExpanded('Commandes',      '$orders',          Icons.receipt,       Colors.green),
          const SizedBox(width: 10),
          _kpiExpanded('Bénéfice',       _cur(profit, sym), Icons.trending_up,   Colors.teal),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _kpiExpanded('Remises', _cur(disc, sym), Icons.percent,        Colors.orange),
          const SizedBox(width: 10),
          _kpiExpanded('Taxes',   _cur(tax,  sym), Icons.account_balance,Colors.purple),
          const SizedBox(width: 10),
          _kpiExpanded('Panier moy.',
              orders > 0 ? _cur(rev / orders, sym) : '-',
              Icons.shopping_basket, Colors.indigo),
        ]),
        const SizedBox(height: 24),
        _secTitle('Évolution des ventes'),
        const SizedBox(height: 8),
        SizedBox(
          height: 200,
          child: byDay.isEmpty
              ? _empty('Aucune donnée')
              : LineChart(_dayChart(byDay)),
        ),
        const SizedBox(height: 24),
        _secTitle('Modes de paiement'),
        const SizedBox(height: 6),
        _pmtRow('Espèces', cash,   rev, Colors.green,  sym),
        _pmtRow('Carte',   card,   rev, Colors.blue,   sym),
        _pmtRow('Crédit',  credit, rev, Colors.orange, sym),
      ]),
    );
  }

  LineChartData _dayChart(List data) {
    final spots = <FlSpot>[
      for (int i = 0; i < data.length; i++)
        FlSpot(i.toDouble(), (data[i]['t'] as num?)?.toDouble() ?? 0),
    ];
    if (spots.isEmpty) return LineChartData();
    return LineChartData(
      gridData: const FlGridData(show: true, drawVerticalLine: false),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles:  const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 56)),
        bottomTitles: AxisTitles(sideTitles: SideTitles(
          showTitles: data.length <= 20,
          getTitlesWidget: (v, _) {
            final i = v.toInt();
            if (i < 0 || i >= data.length) return const SizedBox();
            final d = data[i]['d']?.toString() ?? '';
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(d.length >= 10 ? d.substring(5) : d,
                  style: const TextStyle(fontSize: 9)),
            );
          },
        )),
      ),
      lineBarsData: [LineChartBarData(
        spots: spots, isCurved: true, color: Colors.teal, barWidth: 3,
        dotData: FlDotData(show: data.length <= 20),
        belowBarData: BarAreaData(show: true,
            color: Colors.teal.withValues(alpha: 0.1)),
      )],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // TAB 4 – Par article
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _tabParArticle(String sym) {
    final rawItems = (_report['items'] as List?) ?? [];
    if (rawItems.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
        const SizedBox(height: 12),
        const Text('Aucune vente sur cette période',
            style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 8),
        TextButton.icon(
          icon: const Icon(Icons.date_range),
          label: const Text('Changer la période'),
          onPressed: _pickRange,
        ),
      ]));
    }

    final allTotal = rawItems.fold<double>(
        0, (s, x) => s + (((x as Map)['rev'] as num?)?.toDouble() ?? 0));
    final items = _applyArticleFilter(rawItems);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── filter bar
        _articleFilterBar(),
        // ── summary + manage button
        Row(children: [
          Wrap(spacing: 8, children: [
            Chip(label: Text(
                items.length == rawItems.length
                    ? '${rawItems.length} articles'
                    : '${items.length} / ${rawItems.length} articles')),
            Chip(label: Text('CA total : ${_cur(allTotal, sym)}')),
          ]),
          const Spacer(),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.edit_note, size: 16),
            label: const Text('Gérer les produits'),
            onPressed: () => _push(const ProductsScreen()),
          ),
        ]),
        const SizedBox(height: 16),
        if (items.isEmpty)
          _empty('Aucun article correspondant à la recherche')
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 20,
              headingRowColor: WidgetStateProperty.all(
                  Theme.of(context).colorScheme.surfaceContainerHighest),
              columns: const [
                DataColumn(label: Text('#')),
                DataColumn(label: Text('Produit')),
                DataColumn(label: Text('Qté'),      numeric: true),
                DataColumn(label: Text('CA'),        numeric: true),
                DataColumn(label: Text('% CA'),      numeric: true),
                DataColumn(label: Text('Modifier')),
              ],
              rows: items.asMap().entries.map((e) {
                final m      = e.value as Map;
                final qty    = (m['qty']    as num?)?.toDouble() ?? 0;
                final rev    = (m['rev']    as num?)?.toDouble() ?? 0;
                final pct    = allTotal > 0 ? (rev / allTotal * 100) : 0.0;
                final prodId = m['product_id'] as int?;
                return DataRow(cells: [
                  DataCell(Text('${e.key + 1}')),
                  DataCell(Text(m['product_name']?.toString() ?? '')),
                  DataCell(Text(_fmt(qty))),
                  DataCell(Text(_cur(rev, sym))),
                  DataCell(Text('${pct.toStringAsFixed(1)}%')),
                  DataCell(
                    prodId != null
                        ? ElevatedButton.icon(
                            icon: const Icon(Icons.edit, size: 13),
                            label: const Text('Modifier',
                                style: TextStyle(fontSize: 11)),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () => _editProduct(prodId),
                          )
                        : const SizedBox(),
                  ),
                ]);
              }).toList(),
            ),
          ),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // TAB 5 – Caisse
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _tabCaisse(String sym) {
    if (_report.isEmpty) return const Center(child: CircularProgressIndicator());
    final sum    = _report['summary'] as Map? ?? {};
    final rev    = (sum['revenue']  as num?)?.toDouble() ?? 0;
    final orders = (sum['orders']   as num?)?.toInt()   ?? 0;
    final cash   = (sum['cash']    as num?)?.toDouble() ?? 0;
    final card   = (sum['card']    as num?)?.toDouble() ?? 0;
    final credit = (sum['credit']  as num?)?.toDouble() ?? 0;

    final byEmp  = (_analysis['by_employee'] as List?) ?? [];
    final avg    = (_analysis['avg_basket']  as num?)?.toDouble() ?? 0;
    final maxS   = (_analysis['max_sale']    as num?)?.toDouble() ?? 0;
    final minS   = (_analysis['min_sale']    as num?)?.toDouble() ?? 0;
    final byHour = (_analysis['by_hour']     as List?) ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _kpiExpanded('Encaissé',       _cur(rev,  sym),  Icons.point_of_sale,   Colors.blue),
          const SizedBox(width: 10),
          _kpiExpanded('Panier moyen',   _cur(avg,  sym),  Icons.shopping_basket, Colors.teal),
          const SizedBox(width: 10),
          _kpiExpanded('Transactions',   '$orders',         Icons.receipt,         Colors.green),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _kpiExpanded('Espèces',  _cur(cash,   sym), Icons.money,                  Colors.orange),
          const SizedBox(width: 10),
          _kpiExpanded('Carte',    _cur(card,   sym), Icons.credit_card,            Colors.indigo),
          const SizedBox(width: 10),
          _kpiExpanded('Crédit',   _cur(credit, sym), Icons.account_balance_wallet, Colors.red),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _kpiExpanded('+ grande vente', _cur(maxS, sym), Icons.arrow_upward,   Colors.green),
          const SizedBox(width: 10),
          _kpiExpanded('+ petite vente', _cur(minS, sym), Icons.arrow_downward, Colors.orange),
          const SizedBox(width: 10),
          const Expanded(child: SizedBox()),
        ]),
        const SizedBox(height: 24),
        _secTitle('Répartition paiements'),
        const SizedBox(height: 6),
        _pmtRow('Espèces', cash,   rev, Colors.green,  sym),
        _pmtRow('Carte',   card,   rev, Colors.blue,   sym),
        _pmtRow('Crédit',  credit, rev, Colors.orange, sym),
        const SizedBox(height: 24),
        Row(children: [
          _secTitle('Performance par employé'),
          const Spacer(),
          TextButton.icon(
            icon: const Icon(Icons.badge_rounded, size: 16),
            label: const Text('Gérer les employés'),
            onPressed: () => _push(const EmployeesScreen()),
          ),
        ]),
        const SizedBox(height: 6),
        if (byEmp.isEmpty)
          _empty('Aucune donnée')
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 24,
              columns: const [
                DataColumn(label: Text('Employé')),
                DataColumn(label: Text('Ventes'), numeric: true),
                DataColumn(label: Text('CA'),     numeric: true),
                DataColumn(label: Text('Action')),
              ],
              rows: byEmp.map((e) {
                final m = e as Map;
                return DataRow(cells: [
                  DataCell(Text(m['employee_name']?.toString() ?? 'Inconnu')),
                  DataCell(Text('${m['orders'] ?? 0}')),
                  DataCell(Text(_cur((m['revenue'] as num?)?.toDouble() ?? 0, sym))),
                  DataCell(ElevatedButton.icon(
                    icon: const Icon(Icons.edit, size: 13),
                    label: const Text('Modifier',
                        style: TextStyle(fontSize: 11)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => _push(const EmployeesScreen()),
                  )),
                ]);
              }).toList(),
            ),
          ),
        if (byHour.isNotEmpty) ...[
          const SizedBox(height: 24),
          _secTitle('Ventes par heure'),
          const SizedBox(height: 8),
          SizedBox(height: 180, child: BarChart(_hourChart(byHour))),
        ],
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // TAB 6 – Tous les rapports  (master-detail)
  // ══════════════════════════════════════════════════════════════════════════════
  static const _subLabels = [
    (Icons.summarize,    'Aperçu général'),
    (Icons.analytics,    'Analyse des ventes'),
    (Icons.list_alt,     "Liste d'articles"),
    (Icons.warning_amber,'Stock faible'),
    (Icons.payment,      'Paiements'),
    (Icons.move_down,    'Mouvement de stock'),
  ];

  Widget _tabTousLesRapports(String sym) {
    final cs = Theme.of(context).colorScheme;
    return Row(children: [
      // ── left nav panel
      SizedBox(
        width: 210,
        child: Card(
          margin: const EdgeInsets.all(8),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: _subLabels.length,
            itemBuilder: (_, i) {
              final (icon, label) = _subLabels[i];
              final sel = i == _subIdx;
              return ListTile(
                selected: sel,
                selectedTileColor: cs.primaryContainer,
                leading: Icon(icon, color: sel ? cs.primary : null, size: 20),
                title: Text(label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                      color: sel ? cs.primary : null,
                    )),
                onTap: () => setState(() => _subIdx = i),
              );
            },
          ),
        ),
      ),
      // ── right content panel
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 16, 16, 16),
          child: _buildSub(_subIdx, sym),
        ),
      ),
    ]);
  }

  Widget _buildSub(int idx, String sym) {
    return switch (idx) {
      0 => _subApercuGeneral(sym),
      1 => _subAnalyse(sym),
      2 => _subListeArticles(sym),
      3 => _subStockFaible(sym),
      4 => _subPaiements(sym),
      5 => _subMouvement(sym),
      _ => const SizedBox(),
    };
  }

  // ── sub 0 – Aperçu général ──────────────────────────────────────────────────
  Widget _subApercuGeneral(String sym) {
    if (_report.isEmpty) return const Center(child: CircularProgressIndicator());
    final sum    = _report['summary'] as Map? ?? {};
    final rev    = (sum['revenue']  as num?)?.toDouble() ?? 0;
    final orders = (sum['orders']   as num?)?.toInt()   ?? 0;
    final disc   = (sum['discount'] as num?)?.toDouble() ?? 0;
    final tax    = (sum['tax']      as num?)?.toDouble() ?? 0;
    final profit = (_report['profit'] as num?)?.toDouble() ?? 0;
    final cash   = (sum['cash']    as num?)?.toDouble() ?? 0;
    final card   = (sum['card']    as num?)?.toDouble() ?? 0;
    final credit = (sum['credit']  as num?)?.toDouble() ?? 0;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _subHeader("Aperçu général"),
      _periodChip(),
      const SizedBox(height: 16),
      Wrap(spacing: 10, runSpacing: 10, children: [
        _kpiFixed("Chiffre d'aff.", _cur(rev,    sym), Icons.bar_chart,     Colors.blue),
        _kpiFixed('Bénéfice',       _cur(profit, sym), Icons.trending_up,   Colors.teal),
        _kpiFixed('Commandes',      '$orders',          Icons.receipt,       Colors.green),
        _kpiFixed('Remises',        _cur(disc,   sym), Icons.percent,        Colors.orange),
        _kpiFixed('Taxes',          _cur(tax,    sym), Icons.account_balance,Colors.purple),
        _kpiFixed('Panier moy.',
            orders > 0 ? _cur(rev / orders, sym) : '-',
            Icons.shopping_basket, Colors.indigo),
      ]),
      const SizedBox(height: 24),
      _secTitle('Paiements'),
      const SizedBox(height: 6),
      _pmtRow('Espèces', cash,   rev, Colors.green,  sym),
      _pmtRow('Carte',   card,   rev, Colors.blue,   sym),
      _pmtRow('Crédit',  credit, rev, Colors.orange, sym),
    ]);
  }

  // ── sub 1 – Analyse des ventes ──────────────────────────────────────────────
  Widget _subAnalyse(String sym) {
    final byEmp  = (_analysis['by_employee'] as List?) ?? [];
    final avg    = (_analysis['avg_basket']  as num?)?.toDouble() ?? 0;
    final maxS   = (_analysis['max_sale']    as num?)?.toDouble() ?? 0;
    final minS   = (_analysis['min_sale']    as num?)?.toDouble() ?? 0;
    final byHour = (_analysis['by_hour']     as List?) ?? [];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _subHeader('Analyse des ventes'),
      _periodChip(),
      const SizedBox(height: 16),
      Wrap(spacing: 10, runSpacing: 10, children: [
        _kpiFixed('Panier moyen',    _cur(avg,  sym), Icons.shopping_basket, Colors.blue),
        _kpiFixed('Vente maximale',  _cur(maxS, sym), Icons.arrow_upward,   Colors.green),
        _kpiFixed('Vente minimale',  _cur(minS, sym), Icons.arrow_downward, Colors.orange),
      ]),
      const SizedBox(height: 24),
      _secTitle('Performance par employé'),
      const SizedBox(height: 6),
      if (byEmp.isEmpty)
        _empty('Aucune donnée')
      else
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 24,
            headingRowColor: WidgetStateProperty.all(
                Theme.of(context).colorScheme.surfaceContainerHighest),
            columns: const [
              DataColumn(label: Text('Employé')),
              DataColumn(label: Text('Ventes'), numeric: true),
              DataColumn(label: Text('CA'),     numeric: true),
              DataColumn(label: Text('Modifier')),
            ],
            rows: byEmp.map((e) {
              final m = e as Map;
              return DataRow(cells: [
                DataCell(Text(m['employee_name']?.toString() ?? 'Inconnu')),
                DataCell(Text('${m['orders'] ?? 0}')),
                DataCell(Text(_cur((m['revenue'] as num?)?.toDouble() ?? 0, sym))),
                DataCell(ElevatedButton.icon(
                  icon: const Icon(Icons.edit, size: 13),
                  label: const Text('Modifier',
                      style: TextStyle(fontSize: 11)),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => _push(const EmployeesScreen()),
                )),
              ]);
            }).toList(),
          ),
        ),
      if (byHour.isNotEmpty) ...[
        const SizedBox(height: 24),
        _secTitle('Activité par heure'),
        const SizedBox(height: 8),
        SizedBox(height: 180, child: BarChart(_hourChart(byHour))),
      ],
    ]);
  }

  // ── sub 2 – Liste d'articles ────────────────────────────────────────────────
  Widget _subListeArticles(String sym) {
    final rawItems = (_report['items'] as List?) ?? [];
    final allTotal = rawItems.fold<double>(
        0, (s, x) => s + (((x as Map)['rev'] as num?)?.toDouble() ?? 0));
    final items = _applyArticleFilter(rawItems);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _subHeader("Liste d'articles"),
      _periodChip(),
      const SizedBox(height: 16),
      // ── filter bar
      _articleFilterBar(),
      if (rawItems.isEmpty)
        _empty('Aucun article vendu sur cette période')
      else ...[
        Chip(label: Text(
            items.length == rawItems.length
                ? '${rawItems.length} articles  •  CA : ${_cur(allTotal, sym)}'
                : '${items.length} / ${rawItems.length}  •  CA total : ${_cur(allTotal, sym)}')),
        const SizedBox(height: 12),
        if (items.isEmpty)
          _empty('Aucun article correspondant à la recherche')
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 20,
              headingRowColor: WidgetStateProperty.all(
                  Theme.of(context).colorScheme.surfaceContainerHighest),
              columns: const [
                DataColumn(label: Text('#')),
                DataColumn(label: Text('Article')),
                DataColumn(label: Text('Qté'),      numeric: true),
                DataColumn(label: Text('CA'),        numeric: true),
                DataColumn(label: Text('% CA'),      numeric: true),
                DataColumn(label: Text('Modifier')),
              ],
              rows: items.asMap().entries.map((e) {
                final m      = e.value as Map;
                final qty    = (m['qty']    as num?)?.toDouble() ?? 0;
                final rev    = (m['rev']    as num?)?.toDouble() ?? 0;
                final pct    = allTotal > 0 ? (rev / allTotal * 100) : 0.0;
                final prodId = m['product_id'] as int?;
                return DataRow(cells: [
                  DataCell(Text('${e.key + 1}')),
                  DataCell(Text(m['product_name']?.toString() ?? '')),
                  DataCell(Text(_fmt(qty))),
                  DataCell(Text(_cur(rev, sym))),
                  DataCell(Text('${pct.toStringAsFixed(1)}%')),
                  DataCell(
                    prodId != null
                        ? ElevatedButton.icon(
                            icon: const Icon(Icons.edit, size: 13),
                            label: const Text('Modifier',
                                style: TextStyle(fontSize: 11)),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () => _editProduct(prodId),
                          )
                        : const SizedBox(),
                  ),
                ]);
              }).toList(),
            ),
          ),
      ],
    ]);
  }

  // ── sub 3 – Stock faible ────────────────────────────────────────────────────
  Widget _subStockFaible(String sym) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        _subHeader('Stock faible'),
        const Spacer(),
        FilledButton.tonalIcon(
          icon: const Icon(Icons.warehouse_rounded, size: 16),
          label: const Text('Gérer les stocks'),
          onPressed: () => _push(const StockScreen()),
        ),
      ]),
      const SizedBox(height: 16),
      Wrap(spacing: 10, runSpacing: 10, children: [
        _kpiFixed('En rupture', '${_stockOut.length}', Icons.block,        Colors.red),
        _kpiFixed('Stock faible','${_stockLow.length}', Icons.warning_amber,Colors.orange),
      ]),
      const SizedBox(height: 20),
      if (_stockOut.isNotEmpty) ...[
        _secTitle('🔴  Rupture de stock'),
        const SizedBox(height: 6),
        _stockTable(_stockOut, Colors.red),
        const SizedBox(height: 20),
      ],
      if (_stockLow.isNotEmpty) ...[
        _secTitle('🟠  Stock faible'),
        const SizedBox(height: 6),
        _stockTable(_stockLow, Colors.orange),
      ],
      if (_stockOut.isEmpty && _stockLow.isEmpty)
        Padding(
          padding: const EdgeInsets.all(40),
          child: Column(children: const [
            Icon(Icons.check_circle_outline, size: 60, color: Colors.green),
            SizedBox(height: 12),
            Text('Tous les stocks sont OK',
                style: TextStyle(fontSize: 16, color: Colors.green)),
          ]),
        ),
    ]);
  }

  Widget _stockTable(List<Map<String, dynamic>> rows, Color color) =>
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 16,
          headingRowColor: WidgetStateProperty.all(
              Theme.of(context).colorScheme.surfaceContainerHighest),
          columns: const [
            DataColumn(label: Text('Produit')),
            DataColumn(label: Text('Catégorie')),
            DataColumn(label: Text('Stock'),   numeric: true),
            DataColumn(label: Text('Min'),     numeric: true),
            DataColumn(label: Text('Actions')),
          ],
          rows: rows.map((m) {
            final prodId = m['id'] as int?;
            return DataRow(cells: [
              DataCell(Text(m['name']?.toString() ?? '')),
              DataCell(Text(m['category_name']?.toString() ?? '-')),
              DataCell(Text(_fmt((m['stock'] as num?)?.toDouble() ?? 0),
                  style:
                      TextStyle(color: color, fontWeight: FontWeight.bold))),
              DataCell(Text(_fmt((m['min_stock'] as num?)?.toDouble() ?? 0))),
              DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.tune, size: 13),
                  label: const Text('Ajuster',
                      style: TextStyle(fontSize: 11)),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: color.withValues(alpha: 0.15),
                    foregroundColor: color,
                  ),
                  onPressed: () => _adjustStockDialog(m),
                ),
                const SizedBox(width: 6),
                if (prodId != null)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.edit, size: 13),
                    label: const Text('Modifier',
                        style: TextStyle(fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => _editProduct(prodId),
                  ),
              ])),
            ]);
          }).toList(),
        ),
      );

  // ── sub 4 – Paiements ───────────────────────────────────────────────────────
  Widget _subPaiements(String sym) {
    if (_report.isEmpty) return const Center(child: CircularProgressIndicator());
    final sum    = _report['summary'] as Map? ?? {};
    final rev    = (sum['revenue']  as num?)?.toDouble() ?? 0;
    final orders = (sum['orders']   as num?)?.toInt()   ?? 0;
    final cash   = (sum['cash']    as num?)?.toDouble() ?? 0;
    final card   = (sum['card']    as num?)?.toDouble() ?? 0;
    final credit = (sum['credit']  as num?)?.toDouble() ?? 0;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _subHeader('Paiements'),
      _periodChip(),
      const SizedBox(height: 16),
      Wrap(spacing: 10, runSpacing: 10, children: [
        _kpiFixed('Total encaissé', _cur(rev,  sym), Icons.point_of_sale, Colors.blue),
        _kpiFixed('Transactions',   '$orders',        Icons.receipt,       Colors.green),
      ]),
      const SizedBox(height: 24),
      _secTitle('Détail par mode'),
      const SizedBox(height: 8),
      _pmtCard('Espèces',         cash,   rev, Colors.green,  sym, Icons.money),
      _pmtCard('Carte bancaire',  card,   rev, Colors.blue,   sym, Icons.credit_card),
      _pmtCard('Crédit / ardoise',credit, rev, Colors.orange, sym,
          Icons.account_balance_wallet),
    ]);
  }

  Widget _pmtCard(String label, double val, double total,
      Color color, String sym, IconData icon) {
    final pct = total > 0 ? val / total : 0.0;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            Text(_cur(val, sym),
                style: TextStyle(fontWeight: FontWeight.bold,
                    color: color, fontSize: 16)),
          ]),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: pct,
            backgroundColor: color.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 4),
          Text('${(pct * 100).toStringAsFixed(1)} % du total',
              style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }

  // ── sub 5 – Mouvement de stock ──────────────────────────────────────────────
  Widget _subMouvement(String sym) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        _subHeader('Mouvement de stock'),
        const Spacer(),
        FilledButton.tonalIcon(
          icon: const Icon(Icons.warehouse_rounded, size: 16),
          label: const Text('Gérer les stocks'),
          onPressed: () => _push(const StockScreen()),
        ),
      ]),
      _periodChip(),
      const SizedBox(height: 16),
      if (_movements.isEmpty)
        _empty('Aucun mouvement sur cette période')
      else
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 16,
            headingRowColor: WidgetStateProperty.all(
                Theme.of(context).colorScheme.surfaceContainerHighest),
            columns: const [
              DataColumn(label: Text('Produit')),
              DataColumn(label: Text('Unité')),
              DataColumn(label: Text('Vendu'),     numeric: true),
              DataColumn(label: Text('Stock act.'), numeric: true),
              DataColumn(label: Text('CA'),         numeric: true),
              DataColumn(label: Text('Action')),
            ],
            rows: _movements.map((m) {
              final sold    = (m['qty_sold']      as num?)?.toDouble() ?? 0;
              final current = (m['current_stock'] as num?)?.toDouble() ?? 0;
              final rev     = (m['revenue']       as num?)?.toDouble() ?? 0;
              final prodId  = m['id'] as int?;
              final stockColor = current <= 0
                  ? Colors.red
                  : current <= 5 ? Colors.orange : Colors.green;
              return DataRow(cells: [
                DataCell(Text(m['product_name']?.toString() ?? '')),
                DataCell(Text(m['unit']?.toString() ?? 'pcs')),
                DataCell(Text(_fmt(sold))),
                DataCell(Text(_fmt(current),
                    style: TextStyle(
                        color: stockColor, fontWeight: FontWeight.bold))),
                DataCell(Text(_cur(rev, sym))),
                DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.tune, size: 13),
                    label: const Text('Ajuster',
                        style: TextStyle(fontSize: 11)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      visualDensity: VisualDensity.compact,
                      backgroundColor:
                          stockColor.withValues(alpha: 0.15),
                      foregroundColor: stockColor,
                    ),
                    onPressed: () => _adjustStockDialog({
                      'id':    m['id'],
                      'name':  m['product_name'],
                      'stock': m['current_stock'],
                    }),
                  ),
                  const SizedBox(width: 6),
                  if (prodId != null)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.edit, size: 13),
                      label: const Text('Modifier',
                          style: TextStyle(fontSize: 11)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => _editProduct(prodId),
                    ),
                ])),
              ]);
            }).toList(),
          ),
        ),
    ]);
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // SHARED WIDGETS
  // ══════════════════════════════════════════════════════════════════════════════

  /// Full-width KPI card inside a Row (uses Expanded)
  Widget _kpiExpanded(String label, String value, IconData icon, Color color) =>
      Expanded(child: _kpiInner(label, value, icon, color, 18));

  /// Fixed-width KPI card for Wrap layouts
  Widget _kpiFixed(String label, String value, IconData icon, Color color) =>
      SizedBox(width: 160, child: _kpiInner(label, value, icon, color, 16));

  Widget _kpiInner(String label, String value, IconData icon,
      Color color, double fontSize) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(fontWeight: FontWeight.bold,
                  fontSize: fontSize, color: color)),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall,
              maxLines: 2, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }

  /// Horizontal payment progress row
  Widget _pmtRow(String label, double value, double total,
      Color color, String sym) {
    final pct = total > 0 ? (value / total) : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 13))),
        Expanded(child: LinearProgressIndicator(
          value: pct,
          backgroundColor: color.withValues(alpha: 0.15),
          valueColor: AlwaysStoppedAnimation(color),
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
        )),
        const SizedBox(width: 10),
        SizedBox(
          width: 110,
          child: Text(_cur(value, sym),
              textAlign: TextAlign.right, style: const TextStyle(fontSize: 12)),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 44,
          child: Text('${(pct * 100).toStringAsFixed(0)}%',
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        ),
      ]),
    );
  }

  Widget _secTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(t,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
      );

  Widget _subHeader(String t) => Text(t,
      style: Theme.of(context)
          .textTheme
          .headlineSmall
          ?.copyWith(fontWeight: FontWeight.bold));

  Widget _periodChip() => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Chip(
          avatar: const Icon(Icons.date_range, size: 16),
          label: Text(
            '${DateFormat('dd/MM/yyyy').format(_from)} – ${DateFormat('dd/MM/yyyy').format(_to)}',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      );

  Widget _empty(String msg) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text(msg, style: const TextStyle(color: Colors.grey)),
      );

  // ══════════════════════════════════════════════════════════════════════════════
  // TAB 7 – Rapport PDF
  // ══════════════════════════════════════════════════════════════════════════════
  Widget _tabPdfReport(String sym) {
    final periodLabels = {
      'daily': 'Journalier',
      'weekly': 'Hebdomadaire',
      'monthly': 'Mensuel',
      'yearly': 'Annuel',
    };

    String _dateRangeLabel() {
      final from = _pdfFromTo().$1;
      final to   = _pdfFromTo().$2;
      return '${DateFormat('dd/MM/yyyy').format(from)} – ${DateFormat('dd/MM/yyyy').format(to)}';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Title
              Row(children: [
                const Icon(Icons.picture_as_pdf_rounded, color: Colors.red, size: 28),
                const SizedBox(width: 10),
                Text('Générer un rapport PDF',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 4),
              const Text('Sélectionnez la période et les sections à inclure dans le rapport.',
                  style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 24),

              // ── Period selector
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Période', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: ['daily', 'weekly', 'monthly', 'yearly'].map((p) {
                          return ChoiceChip(
                            label: Text(periodLabels[p]!),
                            selected: _pdfPeriod == p,
                            onSelected: (s) { if (s) setState(() => _pdfPeriod = p); },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(_dateRangeLabel()),
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _pdfDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (d != null) setState(() => _pdfDate = d);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Sections
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Sections à inclure',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 8),
                      ..._pdfSections.entries.map((e) {
                        final labels = {
                          'sales': 'Résumé des ventes',
                          'products': 'Top 10 produits',
                          'payments': 'Répartition des paiements',
                          'employees': 'Performance des employés',
                          'stock': 'Alertes de stock',
                        };
                        return CheckboxListTile(
                          dense: true,
                          title: Text(labels[e.key] ?? e.key),
                          value: e.value,
                          onChanged: (v) =>
                              setState(() => _pdfSections[e.key] = v ?? false),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ── Buttons
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _pdfGenerating ? null : () => _generatePdf(sym),
                    icon: _pdfGenerating
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.print_rounded),
                    label: Text(_pdfGenerating ? 'Génération...' : 'Générer & Imprimer'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pdfGenerating ? null : () => _savePdf(sym),
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Télécharger PDF'),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  // ── PDF date helpers ──────────────────────────────────────────────────────
  (DateTime, DateTime) _pdfFromTo() {
    final d = _pdfDate;
    return switch (_pdfPeriod) {
      'daily'   => (DateTime(d.year, d.month, d.day),
                    DateTime(d.year, d.month, d.day)),
      'weekly'  => (d.subtract(Duration(days: d.weekday - 1)),
                    d.subtract(Duration(days: d.weekday - 1)).add(const Duration(days: 6))),
      'yearly'  => (DateTime(d.year, 1, 1), DateTime(d.year, 12, 31)),
      _         => (DateTime(d.year, d.month, 1),
                    DateTime(d.year, d.month + 1, 0)),
    };
  }

  // ── Build PDF document ────────────────────────────────────────────────────
  Future<pw.Document> _buildPdfDoc(String sym) async {
    final sp   = context.read<SettingsProvider>();
    final logo = loadBusinessLogo(sp.logoPath);
    final (from, to) = _pdfFromTo();
    final fromStr = DateFormat('yyyy-MM-dd').format(from);
    final toStr   = DateFormat('yyyy-MM-dd').format(to);
    final fmtCur = NumberFormat('#,##0.00', 'fr_FR');

    // Fetch data
    final report   = await DB.instance.getReport(fromStr, toStr);
    final analysis = await DB.instance.getSalesAnalysis(fromStr, toStr);
    final stockLow = await DB.instance.getStockProducts(filter: 'low');
    final stockOut = await DB.instance.getStockProducts(filter: 'out');

    final sum       = report['summary'] as Map? ?? {};
    final rev       = (sum['revenue']  as num?)?.toDouble() ?? 0;
    final count     = (sum['orders']   as num?)?.toInt()   ?? 0;
    final cash      = (sum['cash']     as num?)?.toDouble() ?? 0;
    final card      = (sum['card']     as num?)?.toDouble() ?? 0;
    final credit    = (sum['credit']   as num?)?.toDouble() ?? 0;
    final avgBasket = (analysis['avg_basket'] as num?)?.toDouble() ?? 0;
    final byEmp     = (analysis['by_employee'] as List?) ?? [];
    final items     = (report['items'] as List?) ?? [];
    final generatedAt = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    // Sort top 10 products by revenue
    final top10 = List<Map<String, dynamic>>.from(items.cast<Map<String, dynamic>>())
      ..sort((a, b) =>
          ((b['rev'] as num?) ?? 0).compareTo((a['rev'] as num?) ?? 0));
    final top10slice = top10.take(10).toList();

    final doc = pw.Document();

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(32),
      header: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                if (logo != null) ...[
                  pw.Image(logo, height: 48, width: 48, fit: pw.BoxFit.contain),
                  pw.SizedBox(width: 10),
                ],
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text(sp.businessName,
                      style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  if (sp.businessAddress.isNotEmpty)
                    pw.Text(sp.businessAddress,
                        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                  if (sp.businessPhone.isNotEmpty)
                    pw.Text('Tél : ${sp.businessPhone}',
                        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                ]),
              ]),
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Text('RAPPORT DE VENTES',
                    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blueGrey800)),
                pw.Text('$fromStr  →  $toStr',
                    style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
              ]),
            ],
          ),
          pw.Divider(thickness: 1.5, color: PdfColors.blueGrey300),
          pw.SizedBox(height: 4),
        ],
      ),
      footer: (_) => pw.Column(
        children: [
          pw.Divider(color: PdfColors.grey400),
          pw.Text('Généré le $generatedAt',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
        ],
      ),
      build: (_) {
        final widgets = <pw.Widget>[];

        // ── Summary
        if (_pdfSections['sales'] == true) {
          widgets.addAll([
            pw.Text('Résumé des ventes',
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              children: [
                _pdfHeaderRow(['Indicateur', 'Valeur']),
                _pdfRow(['Total ventes', '$sym ${fmtCur.format(rev)}']),
                _pdfRow(['Nb transactions', '$count']),
                _pdfRow(['Panier moyen', '$sym ${fmtCur.format(avgBasket)}']),
              ],
            ),
            pw.SizedBox(height: 16),
          ]);
        }

        // ── Top 10 products
        if (_pdfSections['products'] == true && top10slice.isNotEmpty) {
          widgets.addAll([
            pw.Text('Top 10 Produits',
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(0.5),
                1: const pw.FlexColumnWidth(3),
                2: const pw.FlexColumnWidth(1.2),
                3: const pw.FlexColumnWidth(1.8),
              },
              children: [
                _pdfHeaderRow(['#', 'Produit', 'Quantité', 'CA']),
                ...top10slice.asMap().entries.map((e) {
                  final m   = e.value;
                  final qty = (m['qty'] as num?)?.toDouble() ?? 0;
                  final r   = (m['rev'] as num?)?.toDouble() ?? 0;
                  return _pdfRow([
                    '${e.key + 1}',
                    m['product_name']?.toString() ?? '',
                    NumberFormat('#,##0.##', 'fr_FR').format(qty),
                    '$sym ${fmtCur.format(r)}',
                  ]);
                }),
              ],
            ),
            pw.SizedBox(height: 16),
          ]);
        }

        // ── Payments
        if (_pdfSections['payments'] == true) {
          widgets.addAll([
            pw.Text('Répartition des paiements',
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              children: [
                _pdfHeaderRow(['Mode', 'Montant', '% du total']),
                _pdfRow(['Espèces', '$sym ${fmtCur.format(cash)}',
                    rev > 0 ? '${(cash / rev * 100).toStringAsFixed(1)}%' : '-']),
                _pdfRow(['Carte bancaire', '$sym ${fmtCur.format(card)}',
                    rev > 0 ? '${(card / rev * 100).toStringAsFixed(1)}%' : '-']),
                _pdfRow(['Crédit / ardoise', '$sym ${fmtCur.format(credit)}',
                    rev > 0 ? '${(credit / rev * 100).toStringAsFixed(1)}%' : '-']),
              ],
            ),
            pw.SizedBox(height: 16),
          ]);
        }

        // ── Employees
        if (_pdfSections['employees'] == true && byEmp.isNotEmpty) {
          widgets.addAll([
            pw.Text('Performance des employés',
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              children: [
                _pdfHeaderRow(['Employé', 'Nb ventes', 'CA']),
                ...byEmp.map((e) {
                  final m = e as Map;
                  return _pdfRow([
                    m['employee_name']?.toString() ?? 'Inconnu',
                    '${m['orders'] ?? 0}',
                    '$sym ${fmtCur.format((m['revenue'] as num?)?.toDouble() ?? 0)}',
                  ]);
                }),
              ],
            ),
            pw.SizedBox(height: 16),
          ]);
        }

        // ── Stock alerts
        if (_pdfSections['stock'] == true &&
            (stockOut.isNotEmpty || stockLow.isNotEmpty)) {
          widgets.add(pw.Text('Alertes de stock',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)));
          widgets.add(pw.SizedBox(height: 8));
          if (stockOut.isNotEmpty) {
            widgets.add(pw.Text('Rupture de stock',
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold,
                    color: PdfColors.red700)));
            widgets.add(pw.SizedBox(height: 4));
            widgets.add(pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              children: [
                _pdfHeaderRow(['Produit', 'Stock', 'Stock min.']),
                ...stockOut.map((m) => _pdfRow([
                      m['name']?.toString() ?? '',
                      '${(m['stock'] as num?)?.toStringAsFixed(0) ?? '0'}',
                      '${(m['min_stock'] as num?)?.toStringAsFixed(0) ?? '0'}',
                    ])),
              ],
            ));
            widgets.add(pw.SizedBox(height: 10));
          }
          if (stockLow.isNotEmpty) {
            widgets.add(pw.Text('Stock faible',
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold,
                    color: PdfColors.orange700)));
            widgets.add(pw.SizedBox(height: 4));
            widgets.add(pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              children: [
                _pdfHeaderRow(['Produit', 'Stock', 'Stock min.']),
                ...stockLow.map((m) => _pdfRow([
                      m['name']?.toString() ?? '',
                      '${(m['stock'] as num?)?.toStringAsFixed(0) ?? '0'}',
                      '${(m['min_stock'] as num?)?.toStringAsFixed(0) ?? '0'}',
                    ])),
              ],
            ));
          }
        }

        return widgets;
      },
    ));

    return doc;
  }

  pw.TableRow _pdfHeaderRow(List<String> cells) => pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.blueGrey100),
        children: cells
            .map((c) => pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: pw.Text(c,
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 10)),
                ))
            .toList(),
      );

  pw.TableRow _pdfRow(List<String> cells) => pw.TableRow(
        children: cells
            .map((c) => pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: pw.Text(c, style: const pw.TextStyle(fontSize: 10)),
                ))
            .toList(),
      );

  Future<void> _generatePdf(String sym) async {
    if (_pdfGenerating) return;
    setState(() => _pdfGenerating = true);
    try {
      final doc  = await _buildPdfDoc(sym);
      final (from, to) = _pdfFromTo();
      final name =
          'Rapport_${DateFormat('yyyy-MM-dd').format(from)}_${DateFormat('yyyy-MM-dd').format(to)}';
      await Printing.layoutPdf(
        onLayout: (_) => doc.save(),
        name: name,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _pdfGenerating = false);
    }
  }

  Future<void> _savePdf(String sym) async {
    if (_pdfGenerating) return;
    setState(() => _pdfGenerating = true);
    try {
      final doc  = await _buildPdfDoc(sym);
      final (from, to) = _pdfFromTo();
      final name =
          'Rapport_${DateFormat('yyyy-MM-dd').format(from)}_${DateFormat('yyyy-MM-dd').format(to)}.pdf';

      final location = await getSaveLocation(
        suggestedName: name,
        acceptedTypeGroups: [
          const XTypeGroup(label: 'PDF', extensions: ['pdf']),
        ],
      );
      if (location == null) return;

      final bytes = await doc.save();
      final file = File(location.path);
      await file.writeAsBytes(bytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF enregistré : ${location.path}'),
            action: SnackBarAction(
              label: 'OK',
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _pdfGenerating = false);
    }
  }
}
