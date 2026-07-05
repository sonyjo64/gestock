import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import 'dashboard_screen.dart';
import 'pos/pos_screen.dart';
import 'proforma/proforma_screen.dart';
import 'products/products_screen.dart';
import 'categories/categories_screen.dart';
import 'customers/customers_screen.dart';
import 'suppliers/suppliers_screen.dart';
import 'employees/employees_screen.dart';
import 'reports/reports_screen.dart';
import 'banking/banking_screen.dart';
import 'expenses/expenses_screen.dart';
import 'returns/returns_screen.dart';
import 'multipc/multipc_screen.dart';
import 'settings/settings_screen.dart';
import 'stock/stock_screen.dart';
import 'update/update_dialog.dart';

class _NavDest {
  final IconData icon;
  final String label;
  final String module;
  const _NavDest(this.icon, this.label, this.module);
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _idx = 0;

  @override
  void initState() {
    super.initState();
    // Vérification silencieuse au démarrage, différée pour ne pas retarder
    // l'affichage de l'app.
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) checkForUpdatesAndPrompt(context, silent: true);
    });
  }

  static const _destinations = [
    _NavDest(Icons.dashboard_rounded,           'Tableau de bord', 'dashboard'),
    _NavDest(Icons.point_of_sale_rounded,       'Caisse POS',      'pos'),
    _NavDest(Icons.request_quote_rounded,       'Proforma',        'pos'),
    _NavDest(Icons.inventory_2_rounded,         'Produits',        'products'),
    _NavDest(Icons.warehouse_rounded,           'Gestion stock',   'stock'),
    _NavDest(Icons.grid_view_rounded,           'Catégories',      'categories'),
    _NavDest(Icons.people_rounded,              'Clients',         'customers'),
    _NavDest(Icons.local_shipping_rounded,      'Fournisseurs',    'suppliers'),
    _NavDest(Icons.assignment_return_outlined,  'Retours',         'returns'),
    _NavDest(Icons.receipt_long_outlined,       'Dépenses',        'expenses'),
    _NavDest(Icons.badge_rounded,               'Employés',        'employees'),
    _NavDest(Icons.bar_chart_rounded,           'Rapports',        'reports'),
    _NavDest(Icons.account_balance_rounded,     'Banque',          'banking'),
    _NavDest(Icons.lan_rounded,                 'Multi-PC',        'multipc'),
    _NavDest(Icons.settings_rounded,            'Paramètres',      'settings'),
  ];

  static const _screens = [
    DashboardScreen(),
    PosScreen(),
    ProformaScreen(),
    ProductsScreen(),
    StockScreen(),
    CategoriesScreen(),
    CustomersScreen(),
    SuppliersScreen(),
    ReturnsScreen(),
    ExpensesScreen(),
    EmployeesScreen(),
    ReportsScreen(),
    BankingScreen(),
    MultiPcScreen(),
    SettingsScreen(),
  ];

  Color _navBackground(BuildContext context, SettingsProvider settings) {
    final style = settings.settingValue('nav_bg_style', 'theme');
    switch (style) {
      case 'dark_blue': return const Color(0xFF0D47A1);
      case 'black':     return const Color(0xFF212121);
      case 'slate':     return const Color(0xFF455A64);
      case 'bordeaux':  return const Color(0xFF880E4F);
      case 'forest':    return const Color(0xFF1B5E20);
      default:          return Theme.of(context).appBarTheme.backgroundColor
                            ?? Theme.of(context).colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final settings = context.watch<SettingsProvider>();
    final isWide = MediaQuery.of(context).size.width > 900;

    final navBg   = _navBackground(context, settings);
    final navWidth = isWide ? 200.0 : 64.0;

    // Logo de la boutique (si défini), sinon icône par défaut.
    Widget brandLogo(double size) {
      final path = settings.logoPath;
      if (path.isNotEmpty && File(path).existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(File(path),
              width: size, height: size, fit: BoxFit.cover),
        );
      }
      return Icon(Icons.store_rounded, color: Colors.white, size: size);
    }

    return Scaffold(
      body: Row(
        children: [
          // ── Barre de navigation scrollable ──────────────────────────────
          SizedBox(
            width: navWidth,
            child: Material(
              color: navBg,
              child: Column(children: [
                // En-tête boutique
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: isWide
                      ? Column(children: [
                          brandLogo(44),
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(settings.businessName,
                                style: const TextStyle(color: Colors.white,
                                    fontWeight: FontWeight.bold, fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center),
                          ),
                        ])
                      : brandLogo(32),
                ),
                const Divider(color: Colors.white24, height: 1),
                // Items scrollables
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: List.generate(_destinations.length, (i) {
                        final d        = _destinations[i];
                        final selected = _idx == i;
                        final allowed  = auth.isAdmin || auth.can(d.module) || d.module == 'dashboard';
                        return Tooltip(
                          message: isWide ? '' : d.label,
                          child: InkWell(
                            onTap: () {
                              if (!allowed) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Accès refusé'),
                                        backgroundColor: Colors.red,
                                        behavior: SnackBarBehavior.floating));
                                return;
                              }
                              setState(() => _idx = i);
                            },
                            child: Container(
                              width: double.infinity,
                              padding: EdgeInsets.symmetric(
                                  vertical: 10, horizontal: isWide ? 16 : 0),
                              decoration: BoxDecoration(
                                color: selected
                                    ? Colors.white.withOpacity(.18)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              child: isWide
                                  ? Row(children: [
                                      Icon(d.icon, size: 20,
                                          color: selected
                                              ? Colors.white
                                              : allowed
                                                  ? Colors.white70
                                                  : Colors.white30),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(d.label,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: selected
                                                  ? Colors.white
                                                  : allowed
                                                      ? Colors.white70
                                                      : Colors.white30,
                                              fontWeight: selected
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                            ),
                                            overflow: TextOverflow.ellipsis),
                                      ),
                                    ])
                                  : Icon(d.icon, size: 22,
                                      color: selected
                                          ? Colors.white
                                          : allowed
                                              ? Colors.white70
                                              : Colors.white30),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
                // Pied : utilisateur + déconnexion
                const Divider(color: Colors.white24, height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(children: [
                    if (isWide)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(auth.userName,
                            style: const TextStyle(color: Colors.white60, fontSize: 11),
                            overflow: TextOverflow.ellipsis),
                      ),
                    IconButton(
                      icon: const Icon(Icons.logout_rounded, color: Colors.white60),
                      tooltip: 'Déconnexion',
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Déconnexion'),
                            content: const Text('Voulez-vous vraiment vous déconnecter ?'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text('Annuler')),
                              ElevatedButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Déconnexion')),
                            ],
                          ),
                        );
                        if (ok == true && context.mounted) {
                          context.read<AuthProvider>().logout();
                        }
                      },
                    ),
                  ]),
                ),
              ]),
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: _screens[_idx]),
        ],
      ),
    );
  }
}
