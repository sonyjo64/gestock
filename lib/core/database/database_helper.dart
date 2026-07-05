import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final dbPath = join(Directory.current.path, 'pos_data.db');
    return await openDatabase(dbPath, version: 1, onCreate: _createTables);
  }

  Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        category_id INTEGER,
        price REAL NOT NULL DEFAULT 0,
        cost_price REAL NOT NULL DEFAULT 0,
        stock REAL NOT NULL DEFAULT 0,
        barcode TEXT,
        unit TEXT DEFAULT 'pcs',
        description TEXT,
        created_at TEXT DEFAULT (datetime('now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        email TEXT,
        address TEXT,
        type TEXT DEFAULT 'retail',
        balance REAL DEFAULT 0,
        created_at TEXT DEFAULT (datetime('now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE suppliers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        email TEXT,
        address TEXT,
        balance REAL DEFAULT 0,
        created_at TEXT DEFAULT (datetime('now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER,
        subtotal REAL NOT NULL DEFAULT 0,
        discount REAL DEFAULT 0,
        tax REAL DEFAULT 0,
        total REAL NOT NULL DEFAULT 0,
        payment_method TEXT DEFAULT 'cash',
        amount_paid REAL DEFAULT 0,
        notes TEXT,
        created_at TEXT DEFAULT (datetime('now'))
      )
    ''');

    await db.execute('''
      CREATE TABLE sale_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        product_name TEXT NOT NULL,
        quantity REAL NOT NULL DEFAULT 1,
        price REAL NOT NULL DEFAULT 0,
        discount REAL DEFAULT 0,
        total REAL NOT NULL DEFAULT 0,
        FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE expense_heads (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        head_id INTEGER,
        head_name TEXT,
        amount REAL NOT NULL DEFAULT 0,
        description TEXT,
        date TEXT DEFAULT (date('now')),
        created_at TEXT DEFAULT (datetime('now'))
      )
    ''');

    // Données de démonstration
    await _insertDemoData(db);
  }

  Future<void> _insertDemoData(Database db) async {
    await db.insert('categories', {'name': 'Électronique'});
    await db.insert('categories', {'name': 'Alimentaire'});
    await db.insert('categories', {'name': 'Vêtements'});
    await db.insert('categories', {'name': 'Maison'});

    await db.insert('products', {
      'name': 'Écran 24"',
      'category_id': 1,
      'price': 250.0,
      'cost_price': 180.0,
      'stock': 15,
      'barcode': '1234567890',
      'unit': 'pcs',
    });
    await db.insert('products', {
      'name': 'Clavier sans fil',
      'category_id': 1,
      'price': 45.0,
      'cost_price': 28.0,
      'stock': 30,
      'barcode': '1234567891',
      'unit': 'pcs',
    });
    await db.insert('products', {
      'name': 'Souris optique',
      'category_id': 1,
      'price': 25.0,
      'cost_price': 12.0,
      'stock': 50,
      'unit': 'pcs',
    });
    await db.insert('products', {
      'name': 'Café 500g',
      'category_id': 2,
      'price': 8.5,
      'cost_price': 5.0,
      'stock': 100,
      'unit': 'kg',
    });
    await db.insert('products', {
      'name': 'T-Shirt XL',
      'category_id': 3,
      'price': 20.0,
      'cost_price': 10.0,
      'stock': 25,
      'unit': 'pcs',
    });
    await db.insert('products', {
      'name': 'Casque audio',
      'category_id': 1,
      'price': 75.0,
      'cost_price': 45.0,
      'stock': 8,
      'unit': 'pcs',
    });

    await db.insert('customers', {
      'name': 'Ahmed Benali',
      'phone': '0612345678',
      'email': 'ahmed@email.com',
      'type': 'retail',
      'balance': 0,
    });
    await db.insert('customers', {
      'name': 'Société Dupont',
      'phone': '0123456789',
      'email': 'contact@dupont.com',
      'type': 'wholesale',
      'balance': -500,
    });
    await db.insert('customers', {
      'name': 'Marie Martin',
      'phone': '0687654321',
      'type': 'retail',
      'balance': 0,
    });

    await db.insert('suppliers', {
      'name': 'TechDistrib',
      'phone': '0145678901',
      'email': 'orders@techdistrib.com',
    });
    await db.insert('suppliers', {
      'name': 'FoodSupply SA',
      'phone': '0256789012',
      'email': 'supply@foodsupply.com',
    });

    await db.insert('expense_heads', {'name': 'Loyer'});
    await db.insert('expense_heads', {'name': 'Électricité'});
    await db.insert('expense_heads', {'name': 'Transport'});
    await db.insert('expense_heads', {'name': 'Salaires'});
  }

  // PRODUCTS
  Future<List<Map<String, dynamic>>> getProducts({String? search, int? categoryId}) async {
    final db = await database;
    String where = '';
    List<dynamic> args = [];
    if (search != null && search.isNotEmpty) {
      where += 'p.name LIKE ? OR p.barcode LIKE ?';
      args.addAll(['%$search%', '%$search%']);
    }
    if (categoryId != null) {
      if (where.isNotEmpty) where += ' AND ';
      where += 'p.category_id = ?';
      args.add(categoryId);
    }
    final whereClause = where.isEmpty ? '' : 'WHERE $where';
    return await db.rawQuery('''
      SELECT p.*, c.name as category_name
      FROM products p
      LEFT JOIN categories c ON p.category_id = c.id
      $whereClause
      ORDER BY p.name
    ''', args);
  }

  Future<int> insertProduct(Map<String, dynamic> product) async {
    final db = await database;
    return await db.insert('products', product);
  }

  Future<int> updateProduct(int id, Map<String, dynamic> product) async {
    final db = await database;
    return await db.update('products', product, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteProduct(int id) async {
    final db = await database;
    return await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateStock(int productId, double quantity) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE products SET stock = stock - ? WHERE id = ?',
      [quantity, productId],
    );
  }

  // CATEGORIES
  Future<List<Map<String, dynamic>>> getCategories() async {
    final db = await database;
    return await db.query('categories', orderBy: 'name');
  }

  Future<int> insertCategory(String name) async {
    final db = await database;
    return await db.insert('categories', {'name': name});
  }

  Future<int> deleteCategory(int id) async {
    final db = await database;
    return await db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }

  // CUSTOMERS
  Future<List<Map<String, dynamic>>> getCustomers({String? search}) async {
    final db = await database;
    if (search != null && search.isNotEmpty) {
      return await db.query(
        'customers',
        where: 'name LIKE ? OR phone LIKE ?',
        whereArgs: ['%$search%', '%$search%'],
        orderBy: 'name',
      );
    }
    return await db.query('customers', orderBy: 'name');
  }

  Future<int> insertCustomer(Map<String, dynamic> customer) async {
    final db = await database;
    return await db.insert('customers', customer);
  }

  Future<int> updateCustomer(int id, Map<String, dynamic> customer) async {
    final db = await database;
    return await db.update('customers', customer, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteCustomer(int id) async {
    final db = await database;
    return await db.delete('customers', where: 'id = ?', whereArgs: [id]);
  }

  // SUPPLIERS
  Future<List<Map<String, dynamic>>> getSuppliers({String? search}) async {
    final db = await database;
    if (search != null && search.isNotEmpty) {
      return await db.query(
        'suppliers',
        where: 'name LIKE ? OR phone LIKE ?',
        whereArgs: ['%$search%', '%$search%'],
        orderBy: 'name',
      );
    }
    return await db.query('suppliers', orderBy: 'name');
  }

  Future<int> insertSupplier(Map<String, dynamic> supplier) async {
    final db = await database;
    return await db.insert('suppliers', supplier);
  }

  Future<int> updateSupplier(int id, Map<String, dynamic> supplier) async {
    final db = await database;
    return await db.update('suppliers', supplier, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteSupplier(int id) async {
    final db = await database;
    return await db.delete('suppliers', where: 'id = ?', whereArgs: [id]);
  }

  // SALES
  Future<int> insertSale(Map<String, dynamic> sale, List<Map<String, dynamic>> items) async {
    final db = await database;
    return await db.transaction((txn) async {
      final saleId = await txn.insert('sales', sale);
      for (final item in items) {
        await txn.insert('sale_items', {...item, 'sale_id': saleId});
        await txn.rawUpdate(
          'UPDATE products SET stock = stock - ? WHERE id = ?',
          [item['quantity'], item['product_id']],
        );
      }
      return saleId;
    });
  }

  Future<List<Map<String, dynamic>>> getSales({String? startDate, String? endDate}) async {
    final db = await database;
    String where = '';
    List<dynamic> args = [];
    if (startDate != null) {
      where += 'DATE(s.created_at) >= ?';
      args.add(startDate);
    }
    if (endDate != null) {
      if (where.isNotEmpty) where += ' AND ';
      where += 'DATE(s.created_at) <= ?';
      args.add(endDate);
    }
    final whereClause = where.isEmpty ? '' : 'WHERE $where';
    return await db.rawQuery('''
      SELECT s.*, c.name as customer_name
      FROM sales s
      LEFT JOIN customers c ON s.customer_id = c.id
      $whereClause
      ORDER BY s.created_at DESC
    ''', args);
  }

  Future<List<Map<String, dynamic>>> getSaleItems(int saleId) async {
    final db = await database;
    return await db.query('sale_items', where: 'sale_id = ?', whereArgs: [saleId]);
  }

  // DASHBOARD STATS
  Future<Map<String, dynamic>> getDashboardStats() async {
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);

    final todaySales = await db.rawQuery(
      'SELECT SUM(total) as total, COUNT(*) as count FROM sales WHERE DATE(created_at) = ?',
      [today],
    );
    final totalProducts = await db.rawQuery('SELECT COUNT(*) as count FROM products');
    final totalCustomers = await db.rawQuery('SELECT COUNT(*) as count FROM customers');
    final lowStock = await db.rawQuery(
      'SELECT COUNT(*) as count FROM products WHERE stock < 5',
    );
    final weekSales = await db.rawQuery('''
      SELECT DATE(created_at) as date, SUM(total) as total
      FROM sales
      WHERE created_at >= datetime('now', '-7 days')
      GROUP BY DATE(created_at)
      ORDER BY date
    ''');
    final topProducts = await db.rawQuery('''
      SELECT si.product_name, SUM(si.quantity) as qty, SUM(si.total) as revenue
      FROM sale_items si
      JOIN sales s ON si.sale_id = s.id
      WHERE s.created_at >= datetime('now', '-30 days')
      GROUP BY si.product_name
      ORDER BY revenue DESC
      LIMIT 5
    ''');

    return {
      'today_total': (todaySales.first['total'] as num?)?.toDouble() ?? 0.0,
      'today_orders': todaySales.first['count'] as int? ?? 0,
      'total_products': totalProducts.first['count'] as int? ?? 0,
      'total_customers': totalCustomers.first['count'] as int? ?? 0,
      'low_stock': lowStock.first['count'] as int? ?? 0,
      'week_sales': weekSales,
      'top_products': topProducts,
    };
  }

  // REPORTS
  Future<Map<String, dynamic>> getSalesReport(String startDate, String endDate) async {
    final db = await database;
    final summary = await db.rawQuery('''
      SELECT
        COUNT(*) as total_orders,
        SUM(total) as total_revenue,
        SUM(subtotal) as subtotal,
        SUM(discount) as total_discount,
        SUM(tax) as total_tax,
        AVG(total) as avg_order,
        SUM(CASE WHEN payment_method='cash' THEN total ELSE 0 END) as cash_sales,
        SUM(CASE WHEN payment_method='card' THEN total ELSE 0 END) as card_sales,
        SUM(CASE WHEN payment_method='credit' THEN total ELSE 0 END) as credit_sales
      FROM sales
      WHERE DATE(created_at) BETWEEN ? AND ?
    ''', [startDate, endDate]);

    final profit = await db.rawQuery('''
      SELECT SUM(si.total - (p.cost_price * si.quantity)) as profit
      FROM sale_items si
      JOIN sales s ON si.sale_id = s.id
      JOIN products p ON si.product_id = p.id
      WHERE DATE(s.created_at) BETWEEN ? AND ?
    ''', [startDate, endDate]);

    final itemReport = await db.rawQuery('''
      SELECT si.product_name, SUM(si.quantity) as qty, SUM(si.total) as revenue
      FROM sale_items si
      JOIN sales s ON si.sale_id = s.id
      WHERE DATE(s.created_at) BETWEEN ? AND ?
      GROUP BY si.product_name
      ORDER BY revenue DESC
    ''', [startDate, endDate]);

    return {
      'summary': summary.first,
      'profit': (profit.first['profit'] as num?)?.toDouble() ?? 0.0,
      'items': itemReport,
    };
  }

  // EXPENSES
  Future<List<Map<String, dynamic>>> getExpenseHeads() async {
    final db = await database;
    return await db.query('expense_heads', orderBy: 'name');
  }

  Future<int> insertExpenseHead(String name) async {
    final db = await database;
    return await db.insert('expense_heads', {'name': name});
  }

  Future<List<Map<String, dynamic>>> getExpenses({String? startDate, String? endDate}) async {
    final db = await database;
    String where = '';
    List<dynamic> args = [];
    if (startDate != null) {
      where += 'date >= ?';
      args.add(startDate);
    }
    if (endDate != null) {
      if (where.isNotEmpty) where += ' AND ';
      where += 'date <= ?';
      args.add(endDate);
    }
    final whereClause = where.isEmpty ? '' : 'WHERE $where';
    return await db.rawQuery(
      'SELECT * FROM expenses $whereClause ORDER BY created_at DESC',
      args,
    );
  }

  Future<int> insertExpense(Map<String, dynamic> expense) async {
    final db = await database;
    return await db.insert('expenses', expense);
  }
}
