import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../core/database/db.dart';
import '../core/utils/helpers.dart';
import '../providers/settings_provider.dart';
import 'sales/sales_screen.dart';
import 'products/products_screen.dart';
import 'customers/customers_screen.dart';
import 'stock/stock_screen.dart';
import 'reports/reports_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  Map<String, dynamic> _overview = {};
  Map<String, dynamic> _monthly = {};
  List<Map<String, dynamic>> _stockAlerts = [];
  List<Map<String, dynamic>> _activity = [];
  bool _loading = true;
  int _categoryCount    = 0;
  int _employeeCount    = 0;
  int _heldOrdersCount  = 0;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final overview   = await DB.instance.getDashboard();
    final monthly    = await DB.instance.getDashboardMonth();
    final stocks     = await DB.instance.getStockProducts(filter: 'low');
    final outStocks  = await DB.instance.getStockProducts(filter: 'out');
    final activity   = await DB.instance.getRecentActivity();
    final categories = await DB.instance.getCategories();
    final employees  = await DB.instance.getEmployees();
    final heldOrders = await DB.instance.getHeldOrders();
    if (mounted) setState(() {
      _overview        = overview;
      _monthly         = monthly;
      _stockAlerts     = [...outStocks, ...stocks];
      _activity        = activity;
      _categoryCount   = categories.length;
      _employeeCount   = employees.length;
      _heldOrdersCount = heldOrders.length;
      _loading         = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // watch so dashboard rebuilds when KPI colors or currency change
    final sp  = context.watch<SettingsProvider>();
    final sym = sp.currencySymbol;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tableau de bord'),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_rounded), text: 'Vue d\'ensemble'),
            Tab(icon: Icon(Icons.calendar_month_rounded), text: 'Ce mois'),
            Tab(icon: Icon(Icons.inventory_2_rounded), text: 'Stocks'),
            Tab(icon: Icon(Icons.history_rounded), text: 'Activité'),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _buildOverview(sym, sp),
                _buildMonthly(sym),
                _buildStocks(sym),
                _buildActivity(sym),
              ],
            ),
    );
  }

  // ── Vue d'ensemble ────────────────────────────────────────────────────────

  Widget _buildOverview(String sym, SettingsProvider sp) {
    final todayTotal    = (_overview['today_total']    as num?)?.toDouble() ?? 0;
    final todayOrders   = (_overview['today_orders']   as num?)?.toInt()    ?? 0;
    final totalProducts = (_overview['total_products'] as num?)?.toInt()    ?? 0;
    final totalCustomers= (_overview['total_customers']as num?)?.toInt()    ?? 0;
    final monthRevenue  = (_overview['month_revenue']  as num?)?.toDouble() ?? 0;
    final monthProfit   = (_overview['month_profit']   as num?)?.toDouble() ?? 0;

    // Format today's sales compactly: G 1 500 → G1500  (just int for tile)
    final valeursStr = '$sym${todayTotal.toInt()}';

    final tiles = [
      _TileData('PDV',              '$todayOrders',   Icons.point_of_sale_rounded,  const Color(0xFFEF5350),
          onTap: () => _goToSales(title: "Ventes d'aujourd'hui")),
      _TileData('Produits',         '$totalProducts', Icons.inventory_2_rounded,    const Color(0xFFBF360C),
          onTap: () => _push(const ProductsScreen())),
      _TileData('Ventes',           valeursStr,       Icons.shopping_cart_rounded,  const Color(0xFFFFA000),
          onTap: () => _goToSales(title: "Ventes d'aujourd'hui")),
      _TileData('Factures ouvertes','$_heldOrdersCount',Icons.notifications_rounded,const Color(0xFF43A047)),
      _TileData('Catégories',       '$_categoryCount', Icons.folder_rounded,        const Color(0xFF1E88E5),
          onTap: () => _push(const ProductsScreen())),
      _TileData('Clients',          '$totalCustomers', Icons.people_rounded,        const Color(0xFFEF5350),
          onTap: () => _push(const CustomersScreen())),
      _TileData('Utilisateurs',     '$_employeeCount', Icons.groups_rounded,        const Color(0xFF1976D2)),
      _TileData('Rapports',         '0',               Icons.bar_chart_rounded,     const Color(0xFF78909C),
          onTap: () => _push(const ReportsScreen())),
    ];

    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Raccourcis grid ─────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text('Raccourcis',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  letterSpacing: 0.2)),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4, crossAxisSpacing: 10, mainAxisSpacing: 10,
            childAspectRatio: 1.65,
          ),
          itemCount: tiles.length,
          itemBuilder: (_, i) => _shortcutTile(tiles[i]),
        ),

        // ── Analytics section ───────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
          child: Text('Analytiques',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  letterSpacing: 0.2)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: _weekChart()),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: _topProducts(sym)),
          ]),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(children: [
            Expanded(child: _infoCard('Revenus du mois',
                formatCurrency(monthRevenue, symbol: sym),
                Icons.trending_up_rounded, Colors.green,
                onTap: () => _goToSales(from: firstDayOfMonth(), to: today(), title: 'Ventes du mois'))),
            const SizedBox(width: 10),
            Expanded(child: _infoCard('Bénéfice du mois',
                formatCurrency(monthProfit, symbol: sym),
                Icons.savings_rounded, Colors.teal,
                onTap: () => _goToSales(from: firstDayOfMonth(), to: today(), title: 'Ventes du mois'))),
            const SizedBox(width: 10),
            Expanded(child: _infoCard('Stock faible',
                '${_overview['low_stock'] ?? 0} articles',
                Icons.warning_amber_rounded, Colors.orange,
                onTap: () => _push(const StockScreen()))),
            const SizedBox(width: 10),
            Expanded(child: _infoCard('Clients',
                '$totalCustomers',
                Icons.people_rounded, Colors.purple,
                onTap: () => _push(const CustomersScreen()))),
          ]),
        ),
        const SizedBox(height: 20),
      ]),
    );
  }

  // ── Shortcut tile ──────────────────────────────────────────────────────────
  Widget _shortcutTile(_TileData t) {
    return Material(
      color: t.color,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: t.onTap,
        splashColor: Colors.white.withOpacity(0.15),
        highlightColor: Colors.white.withOpacity(0.08),
        child: Stack(children: [
          // Decorative large icon — bottom-right, semi-transparent
          Positioned(
            right: -6, bottom: -6,
            child: Icon(t.icon, size: 75, color: Colors.white.withOpacity(0.22)),
          ),
          // Value + label
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.value,
                  style: const TextStyle(
                    color: Colors.white, fontSize: 26,
                    fontWeight: FontWeight.bold, letterSpacing: -0.5,
                    height: 1.1,
                  ),
                  overflow: TextOverflow.ellipsis),
              const Spacer(),
              Text(t.label,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.88),
                    fontSize: 13, fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      ),
    );
  }

  void _goToSales({String? from, String? to, String? title}) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => SalesListScreen(
          initialFrom: from ?? today(),
          initialTo: to ?? today(),
          title: title ?? 'Ventes'),
    )).then((_) => _load());
  }

  void _push(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen))
        .then((_) => _load());
  }


  Widget _weekChart() {
    final data = (_overview['week_sales'] as List?) ?? [];
    final spots = <FlSpot>[];
    final labels = <String>[];
    for (var i = 0; i < data.length; i++) {
      spots.add(FlSpot(i.toDouble(), (data[i]['t'] as num?)?.toDouble() ?? 0));
      labels.add((data[i]['d'] as String).substring(5));
    }
    return Card(child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Ventes — 7 derniers jours', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 16),
        SizedBox(height: 200, child: spots.isEmpty
            ? const Center(child: Text('Aucune vente cette semaine'))
            : LineChart(LineChartData(
                gridData: const FlGridData(show: true, drawVerticalLine: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, m) {
                      final i = v.toInt();
                      if (i < 0 || i >= labels.length) return const SizedBox();
                      return Text(labels[i], style: const TextStyle(fontSize: 10));
                    },
                  )),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                lineBarsData: [LineChartBarData(
                  spots: spots, isCurved: true,
                  color: const Color(0xFF1565C0), barWidth: 3,
                  dotData: const FlDotData(show: true),
                  belowBarData: BarAreaData(show: true, color: const Color(0xFF1565C0).withOpacity(0.12)),
                )],
              ))),
      ]),
    ));
  }

  Widget _topProducts(String sym) {
    final products = (_overview['top_products'] as List?) ?? [];
    return Card(child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Top produits (30 jours)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const Spacer(),
          TextButton.icon(
            icon: const Icon(Icons.edit_note, size: 16),
            label: const Text('Gérer'),
            onPressed: () => _push(const ProductsScreen()),
          ),
        ]),
        const SizedBox(height: 12),
        if (products.isEmpty)
          const Text('Aucune donnée', style: TextStyle(color: Colors.grey))
        else
          ...products.asMap().entries.map((e) {
            final p = e.value;
            return InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => _push(const ProductsScreen()),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Row(children: [
                  CircleAvatar(radius: 12,
                      backgroundColor: const Color(0xFF1565C0).withValues(alpha: 0.1),
                      child: Text('${e.key + 1}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF1565C0)))),
                  const SizedBox(width: 10),
                  Expanded(child: Text(p['product_name'] as String,
                      style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
                  Text(formatCurrency((p['rev'] as num?)?.toDouble() ?? 0, symbol: sym),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.green)),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 14, color: Colors.grey),
                ]),
              ),
            );
          }),
      ]),
    ));
  }

  Widget _infoCard(String label, String value, IconData icon, Color color,
      {VoidCallback? onTap}) {
    return Card(
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
            ])),
            if (onTap != null)
              Icon(Icons.chevron_right, size: 16,
                  color: color.withValues(alpha: 0.4)),
          ]),
        ),
      ),
    );
  }

  // ── Ce mois ───────────────────────────────────────────────────────────────

  Widget _buildMonthly(String sym) {
    final revenue    = (_monthly['revenue'] as num?)?.toDouble() ?? 0;
    final prevRev    = (_monthly['prev_revenue'] as num?)?.toDouble() ?? 0;
    final profit     = (_monthly['profit'] as num?)?.toDouble() ?? 0;
    final expenses   = (_monthly['expenses'] as num?)?.toDouble() ?? 0;
    final orders     = (_monthly['orders'] as num?)?.toInt() ?? 0;
    final cash       = (_monthly['cash'] as num?)?.toDouble() ?? 0;
    final card       = (_monthly['card'] as num?)?.toDouble() ?? 0;
    final credit     = (_monthly['credit'] as num?)?.toDouble() ?? 0;
    final daily      = (_monthly['daily'] as List?) ?? [];
    final evolution  = prevRev > 0 ? ((revenue - prevRev) / prevRev * 100) : null;

    final now = DateTime.now();
    final monthName = _monthName(now.month);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        // KPI row
        Row(children: [
          Expanded(child: _monthKpi('CA $monthName', formatCurrency(revenue, symbol: sym),
              Icons.euro_rounded, const Color(0xFF1565C0),
              badge: evolution != null ? '${evolution >= 0 ? '+' : ''}${evolution.toStringAsFixed(1)}%' : null,
              badgeOk: (evolution ?? 0) >= 0,
              onTap: () => _goToSales(from: firstDayOfMonth(), to: today(), title: 'Ventes du mois'))),
          const SizedBox(width: 12),
          Expanded(child: _monthKpi('Bénéfice net', formatCurrency(profit, symbol: sym),
              Icons.savings_rounded, Colors.green,
              onTap: () => _goToSales(from: firstDayOfMonth(), to: today(), title: 'Ventes du mois'))),
          const SizedBox(width: 12),
          Expanded(child: _monthKpi('Dépenses', formatCurrency(expenses, symbol: sym),
              Icons.receipt_long_rounded, Colors.red)),
          const SizedBox(width: 12),
          Expanded(child: _monthKpi('Commandes', '$orders',
              Icons.shopping_cart_rounded, Colors.purple,
              onTap: () => _goToSales(from: firstDayOfMonth(), to: today(), title: 'Commandes du mois'))),
        ]),
        const SizedBox(height: 20),

        // Daily chart
        Card(child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Ventes journalières — $monthName ${now.year}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 16),
            SizedBox(height: 220, child: _buildDailyChart(daily)),
          ]),
        )),
        const SizedBox(height: 16),

        // Payment breakdown
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Modes de paiement', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 16),
              _payRow('Espèces', cash, Colors.green, revenue, sym),
              const SizedBox(height: 10),
              _payRow('Carte', card, Colors.blue, revenue, sym),
              const SizedBox(height: 10),
              _payRow('Crédit', credit, Colors.orange, revenue, sym),
            ]),
          ))),
          const SizedBox(width: 16),
          Expanded(child: Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Résumé financier', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 16),
              _summaryRow('Chiffre d\'affaires', formatCurrency(revenue, symbol: sym), Colors.blue),
              const Divider(height: 16),
              _summaryRow('Bénéfice brut', formatCurrency(profit, symbol: sym), Colors.green),
              const Divider(height: 16),
              _summaryRow('Dépenses', '- ${formatCurrency(expenses, symbol: sym)}', Colors.red),
              const Divider(height: 16),
              _summaryRow('Mois précédent', formatCurrency(prevRev, symbol: sym), Colors.grey),
            ]),
          ))),
        ]),
      ]),
    );
  }

  Widget _buildDailyChart(List<dynamic> daily) {
    if (daily.isEmpty) return const Center(child: Text('Aucune vente ce mois'));
    final spots = <FlSpot>[];
    final labels = <String>[];
    for (var i = 0; i < daily.length; i++) {
      spots.add(FlSpot(i.toDouble(), (daily[i]['t'] as num?)?.toDouble() ?? 0));
      labels.add(daily[i]['day'] as String? ?? '');
    }
    return BarChart(BarChartData(
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(sideTitles: SideTitles(
          showTitles: true,
          getTitlesWidget: (v, m) {
            final i = v.toInt();
            if (i < 0 || i >= labels.length || i % 3 != 0) return const SizedBox();
            return Text(labels[i], style: const TextStyle(fontSize: 9));
          },
        )),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      barGroups: spots.asMap().entries.map((e) => BarChartGroupData(
        x: e.key,
        barRods: [BarChartRodData(
          toY: e.value.y,
          color: const Color(0xFF1565C0),
          width: 10,
          borderRadius: BorderRadius.circular(3),
        )],
      )).toList(),
    ));
  }

  Widget _payRow(String label, double amount, Color color, double total, String sym) {
    final pct = total > 0 ? (amount / total) : 0.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
        Text(formatCurrency(amount, symbol: sym), style: TextStyle(fontWeight: FontWeight.bold, color: color)),
      ]),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(value: pct.toDouble(), backgroundColor: Colors.grey.shade200, color: color, minHeight: 6),
      ),
    ]);
  }

  Widget _summaryRow(String label, String value, Color color) {
    return Row(children: [
      Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
      Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
    ]);
  }

  Widget _monthKpi(String label, String value, IconData icon, Color color,
      {String? badge, bool badgeOk = true, VoidCallback? onTap}) {
    return Card(
      elevation: 2,
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                  overflow: TextOverflow.ellipsis),
              Text(value,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color),
                  overflow: TextOverflow.ellipsis),
              if (badge != null)
                Container(
                  margin: const EdgeInsets.only(top: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeOk ? Colors.green.shade50 : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(badge,
                      style: TextStyle(
                          fontSize: 10,
                          color: badgeOk ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold)),
                ),
            ])),
            if (onTap != null)
              Icon(Icons.chevron_right,
                  size: 16, color: color.withValues(alpha: 0.5)),
          ]),
        ),
      ),
    );
  }

  // ── Stocks ────────────────────────────────────────────────────────────────

  Widget _buildStocks(String sym) {
    final outProducts = _stockAlerts.where((p) => (p['stock'] as num).toDouble() <= 0).toList();
    final lowProducts = _stockAlerts.where((p) {
      final s = (p['stock'] as num).toDouble();
      final m = (p['min_stock'] as num).toDouble();
      return s > 0 && s <= m;
    }).toList();

    if (_stockAlerts.isEmpty) {
      return Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
          const SizedBox(height: 16),
          const Text('Tous les stocks sont au niveau !',
              style: TextStyle(fontSize: 16, color: Colors.green)),
          const SizedBox(height: 8),
          TextButton.icon(
            icon: const Icon(Icons.warehouse_rounded),
            label: const Text('Gérer les stocks'),
            onPressed: () => _push(const StockScreen()),
          ),
        ],
      ));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: _stockStatCard('Rupture de stock', '${outProducts.length}', Colors.red, Icons.remove_shopping_cart,
              onTap: () => _push(const StockScreen()))),
          const SizedBox(width: 12),
          Expanded(child: _stockStatCard('Stock faible', '${lowProducts.length}', Colors.orange, Icons.warning_amber_rounded,
              onTap: () => _push(const StockScreen()))),
          const SizedBox(width: 12),
          Expanded(child: _stockStatCard('Total alertes', '${_stockAlerts.length}', Colors.blue, Icons.notifications_active,
              onTap: () => _push(const StockScreen()))),
        ]),
        const SizedBox(height: 20),
        if (outProducts.isNotEmpty) ...[
          _alertHeader('Rupture de stock', Colors.red),
          const SizedBox(height: 8),
          ..._buildAlertItems(outProducts, Colors.red, sym),
          const SizedBox(height: 20),
        ],
        if (lowProducts.isNotEmpty) ...[
          _alertHeader('Stock faible', Colors.orange),
          const SizedBox(height: 8),
          ..._buildAlertItems(lowProducts, Colors.orange, sym),
        ],
      ]),
    );
  }

  Widget _stockStatCard(String label, String count, Color color, IconData icon,
      {VoidCallback? onTap}) {
    return Card(
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(count,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ])),
            if (onTap != null)
              Icon(Icons.chevron_right, color: color.withValues(alpha: 0.5), size: 18),
          ]),
        ),
      ),
    );
  }

  Widget _alertHeader(String label, Color color) {
    return Row(children: [
      Container(width: 4, height: 18, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 10),
      Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: color)),
    ]);
  }

  List<Widget> _buildAlertItems(List<Map<String, dynamic>> products, Color color, String sym) {
    return products.map((p) {
      final stock    = (p['stock']     as num).toDouble();
      final minStock = (p['min_stock'] as num).toDouble();
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        clipBehavior: Clip.hardEdge,
        child: ListTile(
          leading: Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.inventory_2_rounded, color: color, size: 20),
          ),
          title: Text(p['name'] as String,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
              '${p['category_name'] ?? 'Sans catégorie'}  •  Unité: ${p['unit'] ?? 'pcs'}'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Column(mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('Stock: ${stock.toStringAsFixed(0)}',
                  style: TextStyle(color: color, fontWeight: FontWeight.bold)),
              Text('Min: ${minStock.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ]),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
          ]),
          onTap: () => _push(const StockScreen()),
        ),
      );
    }).toList();
  }

  // ── Activité ──────────────────────────────────────────────────────────────

  Widget _buildActivity(String sym) {
    if (_activity.isEmpty) {
      return const Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text('Aucune vente enregistrée', style: TextStyle(fontSize: 16, color: Colors.grey)),
        ],
      ));
    }

    return Column(children: [
      // header row with "Voir toutes" button
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(children: [
          const Text('Activité récente',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const Spacer(),
          TextButton.icon(
            icon: const Icon(Icons.open_in_new, size: 15),
            label: const Text('Voir toutes les ventes'),
            onPressed: () => _goToSales(
                from: firstDayOfMonth(), to: today(),
                title: 'Toutes les ventes'),
          ),
        ]),
      ),
      Expanded(
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemCount: _activity.length,
          itemBuilder: (_, i) {
            final s       = _activity[i];
            final method  = s['payment_method'] as String? ?? 'cash';
            final itemCount = (s['item_count'] as num?)?.toInt() ?? 0;
            final dateStr = s['created_at']?.toString().substring(0, 10) ?? today();
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: _methodColor(method).withValues(alpha: 0.15),
                child: Icon(_methodIcon(method),
                    color: _methodColor(method), size: 18),
              ),
              title: Text(s['customer_name'] as String? ?? 'Client de passage',
                  style: const TextStyle(fontWeight: FontWeight.w500)),
              subtitle: Row(children: [
                Text(formatDateTime(s['created_at'] as String?)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(4)),
                  child: Text('$itemCount article${itemCount > 1 ? 's' : ''}',
                      style: TextStyle(fontSize: 10, color: Colors.blue.shade700)),
                ),
              ]),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(formatCurrency((s['total'] as num).toDouble(), symbol: sym),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14,
                            color: Color(0xFF1565C0))),
                    Text(_methodLabel(method),
                        style: TextStyle(fontSize: 11, color: _methodColor(method))),
                  ],
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
              ]),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => SalesListScreen(
                  initialFrom: dateStr,
                  initialTo: dateStr,
                  title: 'Vente #${s['id']}',
                )),
              ).then((_) => _load()),
            );
          },
        ),
      ),
    ]);
  }

  Color _methodColor(String m) {
    switch (m) { case 'cash': return Colors.green; case 'card': return Colors.blue;
      case 'credit': return Colors.orange; default: return Colors.grey; }
  }
  IconData _methodIcon(String m) {
    switch (m) { case 'cash': return Icons.payments; case 'card': return Icons.credit_card;
      case 'credit': return Icons.account_balance_wallet; default: return Icons.swap_horiz; }
  }
  String _methodLabel(String m) {
    switch (m) { case 'cash': return 'Espèces'; case 'card': return 'Carte';
      case 'credit': return 'Crédit'; default: return 'Virement'; }
  }

  String _monthName(int month) {
    const names = ['', 'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
        'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre'];
    return names[month];
  }
}

class _TileData {
  final String label, value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  const _TileData(this.label, this.value, this.icon, this.color, {this.onTap});
}
