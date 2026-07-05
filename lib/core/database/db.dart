import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../server/pos_client.dart';
import '../utils/password_hasher.dart';

class DB {
  static final DB instance = DB._();
  DB._();
  static Database? _db;

  final _c = PosClient.instance;

  Future<Database> get database async => _db ??= await _init();

  Future<Database> _init() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = Directory(join(Directory.current.path, 'pos_data'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return openDatabase(
        join(dir.path, 'pos.db'),
        version: 7,
        onCreate: _create,
        onUpgrade: _upgradeDB);
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      final rows = await db.query('settings',
          where: 'key=?', whereArgs: ['currency_code']);
      if (rows.isEmpty || rows.first['value'] == 'EUR') {
        await db.insert('settings',
            {'key': 'currency_code', 'value': 'HTG'},
            conflictAlgorithm: ConflictAlgorithm.replace);
        await db.insert('settings',
            {'key': 'currency_symbol', 'value': 'G'},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
    if (oldVersion < 3) {
      await db.insert('settings',
          {'key': 'setup_completed', 'value': '1'},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    if (oldVersion < 4) {
      await db.execute('''CREATE TABLE IF NOT EXISTS supplier_payments(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplier_id INTEGER NOT NULL,
        amount REAL DEFAULT 0,
        payment_method TEXT DEFAULT 'cash',
        note TEXT,
        date TEXT DEFAULT(date('now')),
        created_at TEXT DEFAULT(datetime('now'))
      )''');
      await db.execute('''CREATE TABLE IF NOT EXISTS returns(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        customer_id INTEGER,
        employee_id INTEGER,
        total_amount REAL DEFAULT 0,
        reason TEXT,
        status TEXT DEFAULT 'completed',
        notes TEXT,
        created_at TEXT DEFAULT(datetime('now'))
      )''');
      await db.execute('''CREATE TABLE IF NOT EXISTS return_items(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        return_id INTEGER NOT NULL,
        product_id INTEGER,
        product_name TEXT NOT NULL,
        quantity REAL DEFAULT 1,
        price REAL DEFAULT 0,
        total REAL DEFAULT 0
      )''');
      await db.execute('''CREATE TABLE IF NOT EXISTS stock_adjustments(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        product_name TEXT NOT NULL,
        delta REAL NOT NULL,
        reason TEXT,
        employee_id INTEGER,
        created_at TEXT DEFAULT(datetime('now'))
      )''');
    }
    if (oldVersion < 5) {
      // Catégories par défaut liées à la construction.
      await _seedConstructionCategories(db);
    }
    if (oldVersion < 6) {
      // Prénom du client (formulaire détaillé).
      await db.execute('ALTER TABLE customers ADD COLUMN first_name TEXT');
    }
    if (oldVersion < 7) {
      // Sel par employé pour le hachage de mot de passe (PBKDF2).
      // Les mots de passe existants (ancien SHA-256 sans sel) restent valides
      // et sont migrés en douceur à la prochaine connexion (voir login()).
      await db.execute('ALTER TABLE employees ADD COLUMN salt TEXT');
    }
  }

  Future<void> _create(Database db, int v) async {
    final batch = db.batch();

    batch.execute('CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT)');

    batch.execute('''CREATE TABLE employees(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      username TEXT UNIQUE NOT NULL,
      password TEXT NOT NULL,
      salt TEXT,
      pin TEXT,
      role TEXT NOT NULL DEFAULT 'cashier',
      permissions TEXT DEFAULT '{}',
      is_active INTEGER DEFAULT 1,
      created_at TEXT DEFAULT(datetime('now'))
    )''');

    batch.execute('''CREATE TABLE categories(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      icon TEXT DEFAULT 'category',
      color TEXT DEFAULT '#1565C0',
      sort_order INTEGER DEFAULT 0
    )''');

    batch.execute('''CREATE TABLE products(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      category_id INTEGER,
      price REAL NOT NULL DEFAULT 0,
      cost_price REAL DEFAULT 0,
      stock REAL DEFAULT 0,
      min_stock REAL DEFAULT 5,
      barcode TEXT,
      unit TEXT DEFAULT 'pcs',
      description TEXT,
      image_path TEXT,
      is_active INTEGER DEFAULT 1,
      created_at TEXT DEFAULT(datetime('now'))
    )''');

    batch.execute('''CREATE TABLE customers(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      first_name TEXT,
      phone TEXT,
      email TEXT,
      address TEXT,
      type TEXT DEFAULT 'retail',
      balance REAL DEFAULT 0,
      credit_limit REAL DEFAULT 0,
      notes TEXT,
      is_active INTEGER DEFAULT 1,
      created_at TEXT DEFAULT(datetime('now'))
    )''');

    batch.execute('''CREATE TABLE suppliers(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      phone TEXT,
      email TEXT,
      address TEXT,
      balance REAL DEFAULT 0,
      notes TEXT,
      created_at TEXT DEFAULT(datetime('now'))
    )''');

    batch.execute('''CREATE TABLE sales(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      customer_id INTEGER,
      employee_id INTEGER,
      subtotal REAL DEFAULT 0,
      discount REAL DEFAULT 0,
      tax REAL DEFAULT 0,
      total REAL DEFAULT 0,
      payment_method TEXT DEFAULT 'cash',
      amount_paid REAL DEFAULT 0,
      change_amount REAL DEFAULT 0,
      status TEXT DEFAULT 'completed',
      notes TEXT,
      created_at TEXT DEFAULT(datetime('now'))
    )''');

    batch.execute('''CREATE TABLE sale_items(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sale_id INTEGER NOT NULL,
      product_id INTEGER,
      product_name TEXT NOT NULL,
      quantity REAL DEFAULT 1,
      price REAL DEFAULT 0,
      cost_price REAL DEFAULT 0,
      discount REAL DEFAULT 0,
      total REAL DEFAULT 0
    )''');

    batch.execute('''CREATE TABLE held_orders(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      label TEXT,
      data TEXT NOT NULL,
      created_at TEXT DEFAULT(datetime('now'))
    )''');

    batch.execute('''CREATE TABLE banks(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      account_number TEXT,
      balance REAL DEFAULT 0,
      is_active INTEGER DEFAULT 1,
      created_at TEXT DEFAULT(datetime('now'))
    )''');

    batch.execute('''CREATE TABLE bank_transactions(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      bank_id INTEGER NOT NULL,
      type TEXT NOT NULL,
      amount REAL DEFAULT 0,
      description TEXT,
      reference TEXT,
      cheque_number TEXT,
      status TEXT DEFAULT 'cleared',
      date TEXT DEFAULT(date('now')),
      created_at TEXT DEFAULT(datetime('now'))
    )''');

    batch.execute('''CREATE TABLE expense_heads(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      icon TEXT DEFAULT 'receipt_long'
    )''');

    batch.execute('''CREATE TABLE expenses(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      head_id INTEGER,
      head_name TEXT,
      amount REAL DEFAULT 0,
      payment_method TEXT DEFAULT 'cash',
      bank_id INTEGER,
      description TEXT,
      date TEXT DEFAULT(date('now')),
      created_at TEXT DEFAULT(datetime('now'))
    )''');

    batch.execute('''CREATE TABLE supplier_payments(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      supplier_id INTEGER NOT NULL,
      amount REAL DEFAULT 0,
      payment_method TEXT DEFAULT 'cash',
      note TEXT,
      date TEXT DEFAULT(date('now')),
      created_at TEXT DEFAULT(datetime('now'))
    )''');

    batch.execute('''CREATE TABLE returns(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sale_id INTEGER NOT NULL,
      customer_id INTEGER,
      employee_id INTEGER,
      total_amount REAL DEFAULT 0,
      reason TEXT,
      status TEXT DEFAULT 'completed',
      notes TEXT,
      created_at TEXT DEFAULT(datetime('now'))
    )''');

    batch.execute('''CREATE TABLE return_items(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      return_id INTEGER NOT NULL,
      product_id INTEGER,
      product_name TEXT NOT NULL,
      quantity REAL DEFAULT 1,
      price REAL DEFAULT 0,
      total REAL DEFAULT 0
    )''');

    batch.execute('''CREATE TABLE stock_adjustments(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      product_id INTEGER NOT NULL,
      product_name TEXT NOT NULL,
      delta REAL NOT NULL,
      reason TEXT,
      employee_id INTEGER,
      created_at TEXT DEFAULT(datetime('now'))
    )''');

    await batch.commit(noResult: true);
    await _seed(db);
  }

  Future<void> _seed(Database db) async {
    await db.insert('settings', {'key': 'tax_rate',        'value': '0'});
    await db.insert('settings', {'key': 'receipt_footer',  'value': 'Merci de votre visite !'});
    await db.insert('settings', {'key': 'theme_mode',      'value': 'light'});
    await db.insert('settings', {'key': 'setup_completed', 'value': '0'});
    await _seedConstructionCategories(db);
  }

  /// Catégories par défaut liées à la construction (nom, icône, couleur).
  static const List<Map<String, String>> kDefaultConstructionCategories = [
    {'name': 'Ciment & Béton',         'icon': 'foundation',           'color': '#607D8B'},
    {'name': 'Fer & Acier',            'icon': 'hardware',             'color': '#455A64'},
    {'name': 'Briques & Blocs',        'icon': 'layers',               'color': '#BF360C'},
    {'name': 'Sable & Gravier',        'icon': 'grain',                'color': '#8D6E63'},
    {'name': 'Bois & Charpente',       'icon': 'carpenter',            'color': '#795548'},
    {'name': 'Plomberie',              'icon': 'plumbing',             'color': '#0277BD'},
    {'name': 'Électricité',            'icon': 'electrical_services',  'color': '#F9A825'},
    {'name': 'Peinture',               'icon': 'format_paint',         'color': '#6A1B9A'},
    {'name': 'Carrelage & Revêtement', 'icon': 'grid_view',            'color': '#00838F'},
    {'name': 'Toiture',                'icon': 'roofing',              'color': '#5D4037'},
    {'name': 'Quincaillerie & Outils', 'icon': 'construction',         'color': '#2E7D32'},
  ];

  /// Insère les catégories construction manquantes (idempotent : ignore celles
  /// dont le nom existe déjà). Appelé à la création et lors de la migration v5.
  Future<void> _seedConstructionCategories(Database db) async {
    for (var i = 0; i < kDefaultConstructionCategories.length; i++) {
      final cat = kDefaultConstructionCategories[i];
      final existing = await db.query('categories',
          where: 'name=?', whereArgs: [cat['name']], limit: 1);
      if (existing.isEmpty) {
        await db.insert('categories', {
          'name': cat['name'],
          'icon': cat['icon'],
          'color': cat['color'],
          'sort_order': i,
        });
      }
    }
  }

  // ── Private helpers : local SQLite ↔ HTTP remote ─────────────────────────

  /// rawQuery
  Future<List<Map<String, dynamic>>> _q(String sql, [List? p]) async {
    if (_c.isConnected) return _c.rawQuery(sql, p);
    return (await database).rawQuery(
        sql, p == null ? const [] : List<Object?>.from(p));
  }

  /// rawInsert
  Future<int> _ri(String sql, [List? p]) async {
    if (_c.isConnected) return _c.rawInsert(sql, p);
    return (await database).rawInsert(
        sql, p == null ? const [] : List<Object?>.from(p));
  }

  /// rawUpdate
  Future<int> _ru(String sql, [List? p]) async {
    if (_c.isConnected) return _c.rawUpdate(sql, p);
    return (await database).rawUpdate(
        sql, p == null ? const [] : List<Object?>.from(p));
  }

  /// execute (no return)
  Future<void> _ex(String sql, [List? p]) async {
    if (_c.isConnected) { await _c.execute(sql, p); return; }
    await (await database).execute(
        sql, p == null ? const [] : List<Object?>.from(p));
  }

  /// convenience insert
  Future<int> _ci(String t, Map<String, dynamic> v,
      {ConflictAlgorithm? ca}) async {
    if (_c.isConnected) return _c.insert(t, v, conflictAlgorithm: ca);
    return (await database).insert(t, v, conflictAlgorithm: ca);
  }

  /// convenience update
  Future<int> _cu(String t, Map<String, dynamic> v,
      {String? w, List? wa, ConflictAlgorithm? ca}) async {
    final wa2 = wa == null ? null : List<Object?>.from(wa);
    if (_c.isConnected)
      return _c.update(t, v, where: w, whereArgs: wa2, conflictAlgorithm: ca);
    return (await database)
        .update(t, v, where: w, whereArgs: wa2, conflictAlgorithm: ca);
  }

  /// convenience delete
  Future<int> _cd(String t, {String? w, List? wa}) async {
    final wa2 = wa == null ? null : List<Object?>.from(wa);
    if (_c.isConnected) return _c.delete(t, where: w, whereArgs: wa2);
    return (await database).delete(t, where: w, whereArgs: wa2);
  }

  /// convenience query
  Future<List<Map<String, dynamic>>> _cq(String t, {
    bool? dist, List<String>? col, String? w, List? wa,
    String? gb, String? hv, String? ob, int? lim, int? off,
  }) async {
    final wa2 = wa == null ? null : List<Object?>.from(wa);
    if (_c.isConnected)
      return _c.query(t,
          distinct: dist, columns: col, where: w, whereArgs: wa2,
          groupBy: gb, having: hv, orderBy: ob, limit: lim, offset: off);
    return (await database).query(t,
        distinct: dist, columns: col, where: w, whereArgs: wa2,
        groupBy: gb, having: hv, orderBy: ob, limit: lim, offset: off);
  }

  // ─── FIRST-LAUNCH SETUP (local only) ─────────────────────────────────────

  Future<void> setupBoutique({
    required String businessName,
    required String businessAddress,
    required String businessPhone,
    required String currencyCode,
    required String currencySymbol,
    required String logoPath,
    required String adminName,
    required String adminUsername,
    required String adminPassword,
  }) async {
    final db = await database;
    final Map<String, String> settingsMap = {
      'business_name':    businessName,
      'business_address': businessAddress,
      'business_phone':   businessPhone,
      'currency_code':    currencyCode,
      'currency_symbol':  currencySymbol,
      'setup_completed':  '1',
    };
    if (logoPath.isNotEmpty) settingsMap['logo_path'] = logoPath;
    for (final e in settingsMap.entries) {
      await db.insert('settings', {'key': e.key, 'value': e.value},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await db.delete('employees');
    final salt = PasswordHasher.generateSalt();
    await db.insert('employees', {
      'name':        adminName,
      'username':    adminUsername,
      'password':    PasswordHasher.hash(adminPassword, salt),
      'salt':        salt,
      'pin':         '1234',
      'role':        'admin',
      'permissions': '{"pos":true,"products":true,"categories":true,'
                     '"customers":true,"suppliers":true,"employees":true,'
                     '"reports":true,"banking":true,"settings":true}',
    });
  }

  // ─── AUTH ─────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> login(String username, String password) async {
    final rows = await _cq('employees',
        w: 'username = ? AND is_active = 1', wa: [username]);
    if (rows.isEmpty) return null;
    final user       = rows.first;
    final salt       = user['salt'] as String?;
    final storedHash = user['password'] as String;

    if (salt != null && salt.isNotEmpty) {
      return PasswordHasher.verify(password, salt, storedHash) ? user : null;
    }

    // Compte créé avant l'ajout du sel (ancien SHA-256 simple) : on vérifie
    // avec l'ancien format puis on migre silencieusement vers PBKDF2 salé.
    if (storedHash == PasswordHasher.legacyHash(password)) {
      final newSalt = PasswordHasher.generateSalt();
      final newHash = PasswordHasher.hash(password, newSalt);
      await _cu('employees', {'password': newHash, 'salt': newSalt},
          w: 'id=?', wa: [user['id']]);
      return {...user, 'password': newHash, 'salt': newSalt};
    }
    return null;
  }

  Future<Map<String, dynamic>?> loginPin(String pin) async {
    final rows = await _cq('employees',
        w: 'pin = ? AND is_active = 1', wa: [pin]);
    return rows.isEmpty ? null : rows.first;
  }

  // ─── SETTINGS ─────────────────────────────────────────────────────────────

  Future<Map<String, String>> getSettings() async {
    final rows = await _cq('settings');
    return {for (final r in rows) r['key'] as String: r['value'] as String? ?? ''};
  }

  Future<void> setSetting(String key, String value) async {
    await _ci('settings', {'key': key, 'value': value},
        ca: ConflictAlgorithm.replace);
  }

  // ─── CATEGORIES ───────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getCategories() async =>
      _cq('categories', ob: 'sort_order, name');

  Future<int> upsertCategory(Map<String, dynamic> data) async {
    if (data['id'] != null) {
      await _cu('categories', data, w: 'id=?', wa: [data['id']]);
      return data['id'] as int;
    }
    return _ci('categories', data);
  }

  Future<void> deleteCategory(int id) async =>
      _cd('categories', w: 'id=?', wa: [id]);

  // ─── PRODUCTS ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getProducts(
      {String? q, int? catId, bool lowStock = false}) async {
    final where = <String>['p.is_active=1'];
    final args  = <dynamic>[];
    if (q != null && q.isNotEmpty) {
      where.add('(p.name LIKE ? OR p.barcode LIKE ?)');
      args.addAll(['%$q%', '%$q%']);
    }
    if (catId != null) { where.add('p.category_id=?'); args.add(catId); }
    if (lowStock) where.add('p.stock <= p.min_stock');
    return _q('''
      SELECT p.*, c.name as category_name, c.color as category_color
      FROM products p LEFT JOIN categories c ON p.category_id=c.id
      WHERE ${where.join(' AND ')} ORDER BY p.name
    ''', args);
  }

  Future<int> upsertProduct(Map<String, dynamic> data) async {
    final id = data['id'];
    if (id != null) {
      await _cu('products', data, w: 'id=?', wa: [id]);
      return id as int;
    }
    return _ci('products', data);
  }

  Future<Map<String, int>> bulkImportProducts(
      List<Map<String, dynamic>> rows) async {
    if (_c.isConnected) return _c.bulkImportProducts(rows);
    final db = await database;
    int inserted = 0, updated = 0, errors = 0;
    await db.transaction((txn) async {
      for (final row in rows) {
        try {
          final barcode = row['barcode'] as String?;
          if (barcode != null && barcode.isNotEmpty) {
            final existing = await txn.query('products',
                where: 'barcode=? AND is_active=1',
                whereArgs: [barcode], limit: 1);
            if (existing.isNotEmpty) {
              final existId = existing.first['id'] as int;
              final upd = Map<String, dynamic>.from(row)..remove('id');
              await txn.update('products', upd, where: 'id=?', whereArgs: [existId]);
              updated++;
              continue;
            }
          }
          final ins = Map<String, dynamic>.from(row)..remove('id');
          await txn.insert('products', ins);
          inserted++;
        } catch (_) { errors++; }
      }
    });
    return {'inserted': inserted, 'updated': updated, 'errors': errors};
  }

  Future<void> deleteProduct(int id) async =>
      _cu('products', {'is_active': 0}, w: 'id=?', wa: [id]);

  Future<void> adjustStock(int productId, double delta) async =>
      _ru('UPDATE products SET stock=stock+? WHERE id=?', [delta, productId]);

  // ─── CUSTOMERS ────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getCustomers({String? q}) async {
    if (q != null && q.isNotEmpty) {
      return _cq('customers',
          w:  'is_active=1 AND (name LIKE ? OR phone LIKE ?)',
          wa: ['%$q%', '%$q%'], ob: 'name');
    }
    return _cq('customers', w: 'is_active=1', ob: 'name');
  }

  Future<Map<String, dynamic>?> getCustomerById(int id) async {
    final rows = await _cq('customers', w: 'id=?', wa: [id], lim: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> upsertCustomer(Map<String, dynamic> data) async {
    final id = data['id'];
    if (id != null) {
      await _cu('customers', data, w: 'id=?', wa: [id]);
      return id as int;
    }
    return _ci('customers', data);
  }

  Future<void> deleteCustomer(int id) async =>
      _cu('customers', {'is_active': 0}, w: 'id=?', wa: [id]);

  // ─── SUPPLIERS ────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getSuppliers({String? q}) async {
    if (q != null && q.isNotEmpty) {
      return _cq('suppliers',
          w:  'name LIKE ? OR phone LIKE ?',
          wa: ['%$q%', '%$q%'], ob: 'name');
    }
    return _cq('suppliers', ob: 'name');
  }

  Future<int> upsertSupplier(Map<String, dynamic> data) async {
    final id = data['id'];
    if (id != null) {
      await _cu('suppliers', data, w: 'id=?', wa: [id]);
      return id as int;
    }
    return _ci('suppliers', data);
  }

  Future<void> deleteSupplier(int id) async =>
      _cd('suppliers', w: 'id=?', wa: [id]);

  // ─── EMPLOYEES ────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getEmployees() async =>
      _cq('employees', w: 'is_active=1', ob: 'name');

  Future<int> upsertEmployee(Map<String, dynamic> data,
      {bool hashPwd = false}) async {
    final d = Map<String, dynamic>.from(data);
    if (hashPwd &&
        d['password'] != null &&
        (d['password'] as String).isNotEmpty) {
      final salt = PasswordHasher.generateSalt();
      d['password'] = PasswordHasher.hash(d['password'] as String, salt);
      d['salt']     = salt;
    }
    final id = d['id'];
    if (id != null) {
      await _cu('employees', d, w: 'id=?', wa: [id]);
      return id as int;
    }
    return _ci('employees', d);
  }

  Future<void> deleteEmployee(int id) async =>
      _cu('employees', {'is_active': 0}, w: 'id=?', wa: [id]);

  Future<bool> updatePassword(int id, String oldPwd, String newPwd) async {
    final rows = await _cq('employees', w: 'id=?', wa: [id]);
    if (rows.isEmpty) return false;
    final user       = rows.first;
    final salt       = user['salt'] as String?;
    final storedHash = user['password'] as String;
    final oldOk = (salt != null && salt.isNotEmpty)
        ? PasswordHasher.verify(oldPwd, salt, storedHash)
        : storedHash == PasswordHasher.legacyHash(oldPwd);
    if (!oldOk) return false;

    final newSalt = PasswordHasher.generateSalt();
    await _cu(
        'employees',
        {'password': PasswordHasher.hash(newPwd, newSalt), 'salt': newSalt},
        w: 'id=?', wa: [id]);
    return true;
  }

  // ─── SALES ────────────────────────────────────────────────────────────────

  Future<int> createSale(Map<String, dynamic> sale,
      List<Map<String, dynamic>> items) async {
    if (_c.isConnected) return _c.createSale(sale, items);
    final db = await database;
    return db.transaction((txn) async {
      final saleId = await txn.insert('sales', sale);
      for (final item in items) {
        await txn.insert('sale_items', {...item, 'sale_id': saleId});
        if (item['product_id'] != null) {
          await txn.rawUpdate(
              'UPDATE products SET stock=stock-? WHERE id=?',
              [item['quantity'], item['product_id']]);
        }
      }
      // Tout montant restant dû (total - payé) est ajouté à la dette du client
      // (convention : balance négative = le client doit de l'argent).
      final customerId = sale['customer_id'];
      if (customerId != null) {
        final total = (sale['total'] as num?)?.toDouble() ?? 0;
        final paid  = (sale['amount_paid'] as num?)?.toDouble() ?? 0;
        final due   = total - paid;
        if (due > 0) {
          await txn.rawUpdate(
              'UPDATE customers SET balance=balance-? WHERE id=?',
              [due, customerId]);
        }
      }
      return saleId;
    });
  }

  Future<List<Map<String, dynamic>>> getSales(
      {String? from, String? to, String? method}) async {
    final where = <String>[];
    final args  = <dynamic>[];
    if (from   != null) { where.add('DATE(s.created_at)>=?'); args.add(from); }
    if (to     != null) { where.add('DATE(s.created_at)<=?'); args.add(to); }
    if (method != null) { where.add('s.payment_method=?');    args.add(method); }
    final w = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    return _q('''
      SELECT s.*, c.name as customer_name, e.name as employee_name
      FROM sales s
      LEFT JOIN customers c ON s.customer_id=c.id
      LEFT JOIN employees e ON s.employee_id=e.id
      $w ORDER BY s.created_at DESC
    ''', args);
  }

  Future<Map<String, dynamic>?> getSaleById(int id) async {
    final rows = await _q(
      'SELECT s.*, c.name as customer_name FROM sales s '
      'LEFT JOIN customers c ON s.customer_id=c.id WHERE s.id=?', [id]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, dynamic>>> getSaleItems(int saleId) async =>
      _cq('sale_items', w: 'sale_id=?', wa: [saleId]);

  // ─── HELD ORDERS ──────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getHeldOrders() async =>
      _cq('held_orders', ob: 'created_at DESC');

  Future<int> holdOrder(String label, String data) async =>
      _ci('held_orders', {'label': label, 'data': data});

  Future<void> deleteHeldOrder(int id) async =>
      _cd('held_orders', w: 'id=?', wa: [id]);

  // ─── DASHBOARD ────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getDashboard() async {
    final today = DateTime.now().toIso8601String().substring(0, 10);

    final todaySales = (await _q(
        'SELECT COALESCE(SUM(total),0) as t, COUNT(*) as c FROM sales WHERE DATE(created_at)=?',
        [today])).first;
    final totalProducts = (await _q(
        'SELECT COUNT(*) as c FROM products WHERE is_active=1')).first;
    final totalCustomers = (await _q(
        'SELECT COUNT(*) as c FROM customers WHERE is_active=1')).first;
    final lowStock = (await _q(
        'SELECT COUNT(*) as c FROM products WHERE stock<=min_stock AND is_active=1')).first;
    final weekSales = await _q('''
      SELECT DATE(created_at) as d, SUM(total) as t
      FROM sales WHERE created_at >= datetime('now','-6 days')
      GROUP BY DATE(created_at) ORDER BY d
    ''');
    final topProducts = await _q('''
      SELECT si.product_name, SUM(si.quantity) as qty, SUM(si.total) as rev
      FROM sale_items si JOIN sales s ON si.sale_id=s.id
      WHERE s.created_at >= datetime('now','-30 days')
      GROUP BY si.product_name ORDER BY rev DESC LIMIT 5
    ''');
    final monthRevenue = (await _q('''
      SELECT COALESCE(SUM(total),0) as t FROM sales
      WHERE strftime('%Y-%m',created_at)=strftime('%Y-%m','now')
    ''')).first;
    final monthProfit = (await _q('''
      SELECT COALESCE(SUM(si.total-(si.cost_price*si.quantity)),0) as p
      FROM sale_items si JOIN sales s ON si.sale_id=s.id
      WHERE strftime('%Y-%m',s.created_at)=strftime('%Y-%m','now')
    ''')).first;

    return {
      'today_total':    todaySales['t'],
      'today_orders':   todaySales['c'],
      'total_products': totalProducts['c'],
      'total_customers':totalCustomers['c'],
      'low_stock':      lowStock['c'],
      'week_sales':     weekSales,
      'top_products':   topProducts,
      'month_revenue':  monthRevenue['t'],
      'month_profit':   monthProfit['p'],
    };
  }

  // ─── REPORTS ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getReport(String from, String to) async {
    final summary = (await _q('''
      SELECT COUNT(*) as orders, COALESCE(SUM(total),0) as revenue,
             COALESCE(SUM(discount),0) as discount, COALESCE(SUM(tax),0) as tax,
             COALESCE(SUM(CASE WHEN payment_method='cash' THEN total ELSE 0 END),0) as cash,
             COALESCE(SUM(CASE WHEN payment_method='card' THEN total ELSE 0 END),0) as card,
             COALESCE(SUM(CASE WHEN payment_method='credit' THEN total ELSE 0 END),0) as credit
      FROM sales WHERE DATE(created_at) BETWEEN ? AND ?
    ''', [from, to])).first;

    final profit = (await _q('''
      SELECT COALESCE(SUM(si.total-(si.cost_price*si.quantity)),0) as p
      FROM sale_items si JOIN sales s ON si.sale_id=s.id
      WHERE DATE(s.created_at) BETWEEN ? AND ?
    ''', [from, to])).first;

    final byDay = await _q('''
      SELECT DATE(created_at) as d, SUM(total) as t, COUNT(*) as c
      FROM sales WHERE DATE(created_at) BETWEEN ? AND ?
      GROUP BY DATE(created_at) ORDER BY d
    ''', [from, to]);

    final items = await _q('''
      SELECT si.product_id, si.product_name, SUM(si.quantity) as qty, SUM(si.total) as rev
      FROM sale_items si JOIN sales s ON si.sale_id=s.id
      WHERE DATE(s.created_at) BETWEEN ? AND ?
      GROUP BY si.product_id, si.product_name ORDER BY rev DESC
    ''', [from, to]);

    return {'summary': summary, 'profit': profit['p'], 'by_day': byDay, 'items': items};
  }

  // ─── BANKING ──────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getBanks() async =>
      _cq('banks', w: 'is_active=1', ob: 'name');

  Future<int> upsertBank(Map<String, dynamic> data) async {
    final id = data['id'];
    if (id != null) {
      await _cu('banks', data, w: 'id=?', wa: [id]);
      return id as int;
    }
    return _ci('banks', data);
  }

  Future<List<Map<String, dynamic>>> getBankTransactions(
      {int? bankId, String? from, String? to}) async {
    final where = <String>[];
    final args  = <dynamic>[];
    if (bankId != null) { where.add('bt.bank_id=?'); args.add(bankId); }
    if (from   != null) { where.add('bt.date>=?');   args.add(from); }
    if (to     != null) { where.add('bt.date<=?');   args.add(to); }
    final w = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    return _q('''
      SELECT bt.*, b.name as bank_name
      FROM bank_transactions bt JOIN banks b ON bt.bank_id=b.id
      $w ORDER BY bt.created_at DESC
    ''', args);
  }

  Future<int> addBankTransaction(Map<String, dynamic> data) async {
    if (_c.isConnected) return _c.addBankTransaction(data);
    final db = await database;
    return db.transaction((txn) async {
      final id     = await txn.insert('bank_transactions', data);
      final amount = (data['amount'] as num).toDouble();
      final type   = data['type'] as String;
      final delta  = (type == 'deposit') ? amount : -amount;
      await txn.rawUpdate(
          'UPDATE banks SET balance=balance+? WHERE id=?',
          [delta, data['bank_id']]);
      return id;
    });
  }

  // ─── EXPENSES ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getExpenseHeads() async =>
      _cq('expense_heads', ob: 'name');

  Future<int> upsertExpenseHead(Map<String, dynamic> data) async {
    final id = data['id'];
    if (id != null) {
      await _cu('expense_heads', data, w: 'id=?', wa: [id]);
      return id as int;
    }
    return _ci('expense_heads', data);
  }

  Future<List<Map<String, dynamic>>> getExpenses(
      {String? from, String? to}) async {
    final where = <String>[];
    final args  = <dynamic>[];
    if (from != null) { where.add('date>=?'); args.add(from); }
    if (to   != null) { where.add('date<=?'); args.add(to); }
    final w = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    return _q('SELECT * FROM expenses $w ORDER BY created_at DESC', args);
  }

  Future<int> addExpense(Map<String, dynamic> data) async =>
      _ci('expenses', data);

  Future<void> deleteExpense(int id) async =>
      _cd('expenses', w: 'id=?', wa: [id]);

  // ─── STOCK ────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getStockProducts(
      {String filter = 'all'}) async {
    final String cond;
    switch (filter) {
      case 'low':  cond = 'p.is_active=1 AND p.stock > 0 AND p.stock <= p.min_stock'; break;
      case 'out':  cond = 'p.is_active=1 AND p.stock <= 0'; break;
      case 'ok':   cond = 'p.is_active=1 AND p.stock > p.min_stock'; break;
      default:     cond = 'p.is_active=1';
    }
    return _q('''
      SELECT p.*, c.name as category_name
      FROM products p LEFT JOIN categories c ON p.category_id=c.id
      WHERE $cond ORDER BY p.name
    ''');
  }

  // ─── DASHBOARD MONTH ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getDashboardMonth() async {
    final now       = DateTime.now();
    final thisMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final lastMonthDt = DateTime(now.year, now.month - 1);
    final lastMonth = '${lastMonthDt.year}-${lastMonthDt.month.toString().padLeft(2, '0')}';

    final cur = (await _q('''
      SELECT COALESCE(SUM(total),0) as t, COUNT(*) as c,
        COALESCE(SUM(CASE WHEN payment_method='cash' THEN total ELSE 0 END),0) as cash,
        COALESCE(SUM(CASE WHEN payment_method='card' THEN total ELSE 0 END),0) as card,
        COALESCE(SUM(CASE WHEN payment_method='credit' THEN total ELSE 0 END),0) as credit
      FROM sales WHERE strftime('%Y-%m',created_at)=?
    ''', [thisMonth])).first;

    final prev = (await _q('''
      SELECT COALESCE(SUM(total),0) as t FROM sales WHERE strftime('%Y-%m',created_at)=?
    ''', [lastMonth])).first;

    final profit = (await _q('''
      SELECT COALESCE(SUM(si.total-(si.cost_price*si.quantity)),0) as p
      FROM sale_items si JOIN sales s ON si.sale_id=s.id
      WHERE strftime('%Y-%m',s.created_at)=?
    ''', [thisMonth])).first;

    final expenses = (await _q('''
      SELECT COALESCE(SUM(amount),0) as t FROM expenses WHERE strftime('%Y-%m',date)=?
    ''', [thisMonth])).first;

    final daily = await _q('''
      SELECT strftime('%d',created_at) as day, SUM(total) as t, COUNT(*) as c
      FROM sales WHERE strftime('%Y-%m',created_at)=?
      GROUP BY day ORDER BY day
    ''', [thisMonth]);

    return {
      'revenue': cur['t'], 'orders': cur['c'],
      'cash': cur['cash'], 'card': cur['card'], 'credit': cur['credit'],
      'prev_revenue': prev['t'],
      'profit':   profit['p'],
      'expenses': expenses['t'],
      'daily':    daily,
    };
  }

  // ─── RECENT ACTIVITY ──────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getRecentActivity({int limit = 25}) async =>
      _q('''
        SELECT s.id, s.total, s.payment_method, s.created_at,
               c.name as customer_name, e.name as employee_name,
               (SELECT COUNT(*) FROM sale_items si WHERE si.sale_id=s.id) as item_count
        FROM sales s
        LEFT JOIN customers c ON s.customer_id=c.id
        LEFT JOIN employees e ON s.employee_id=e.id
        ORDER BY s.created_at DESC LIMIT ?
      ''', [limit]);

  // ─── EXPENSE REPORT ───────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getExpenseReport(String from, String to) async {
    final summary = (await _q('''
      SELECT COUNT(*) as count, COALESCE(SUM(amount),0) as total
      FROM expenses WHERE date BETWEEN ? AND ?
    ''', [from, to])).first;

    final byCategory = await _q('''
      SELECT COALESCE(head_name,'Divers') as category, SUM(amount) as total, COUNT(*) as count
      FROM expenses WHERE date BETWEEN ? AND ?
      GROUP BY category ORDER BY total DESC
    ''', [from, to]);

    final byDay = await _q('''
      SELECT date, SUM(amount) as t FROM expenses WHERE date BETWEEN ? AND ?
      GROUP BY date ORDER BY date
    ''', [from, to]);

    return {'summary': summary, 'by_category': byCategory, 'by_day': byDay};
  }

  // ─── BACKUP / RESTORE ─────────────────────────────────────────────────────

  String get dbPath {
    final dir = Directory(join(Directory.current.path, 'pos_data'));
    return join(dir.path, 'pos.db');
  }

  Future<void> closeAndReset() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }

  // ─── DAILY SUMMARY ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getDailySummary(String date) async {
    final summary = (await _q('''
      SELECT COUNT(*) as orders, COALESCE(SUM(total),0) as revenue,
             COALESCE(SUM(CASE WHEN payment_method='cash' THEN total ELSE 0 END),0) as cash,
             COALESCE(SUM(CASE WHEN payment_method='card' THEN total ELSE 0 END),0) as card,
             COALESCE(SUM(CASE WHEN payment_method='credit' THEN total ELSE 0 END),0) as credit
      FROM sales WHERE DATE(created_at)=?
    ''', [date])).first;

    final byHour = await _q('''
      SELECT strftime('%H', created_at) as hour, COUNT(*) as c, SUM(total) as t
      FROM sales WHERE DATE(created_at)=?
      GROUP BY hour ORDER BY hour
    ''', [date]);

    final salesList = await _q('''
      SELECT s.*, c.name as customer_name
      FROM sales s LEFT JOIN customers c ON s.customer_id=c.id
      WHERE DATE(s.created_at)=?
      ORDER BY s.created_at DESC
    ''', [date]);

    final profit = (await _q('''
      SELECT COALESCE(SUM(si.total-(si.cost_price*si.quantity)),0) as p
      FROM sale_items si JOIN sales s ON si.sale_id=s.id
      WHERE DATE(s.created_at)=?
    ''', [date])).first;

    return {
      'summary': summary, 'by_hour': byHour,
      'sales':   salesList, 'profit': profit['p'] ?? 0,
    };
  }

  // ─── VOID SALE ────────────────────────────────────────────────────────────

  Future<bool> voidSale(int saleId) async {
    if (_c.isConnected) return _c.voidSale(saleId);
    final db = await database;
    try {
      await db.transaction((txn) async {
        final sales = await txn.query('sales', where: 'id=?', whereArgs: [saleId]);
        if (sales.isEmpty) throw Exception('not found');
        final sale = sales.first;
        if (sale['status'] == 'voided') throw Exception('already voided');

        final items = await txn.query('sale_items',
            where: 'sale_id=?', whereArgs: [saleId]);
        for (final item in items) {
          if (item['product_id'] != null) {
            await txn.rawUpdate(
                'UPDATE products SET stock=stock+? WHERE id=?',
                [item['quantity'], item['product_id']]);
          }
        }
        // Annulation : on restitue le montant qui avait été ajouté à la dette.
        if (sale['customer_id'] != null) {
          final total = (sale['total'] as num?)?.toDouble() ?? 0;
          final paid  = (sale['amount_paid'] as num?)?.toDouble() ?? 0;
          final due   = total - paid;
          if (due > 0) {
            await txn.rawUpdate(
                'UPDATE customers SET balance=balance+? WHERE id=?',
                [due, sale['customer_id']]);
          }
        }
        await txn.update('sales', {'status': 'voided'},
            where: 'id=?', whereArgs: [saleId]);
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  // ─── STOCK MOVEMENTS ──────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getStockMovements(
      String from, String to) async => _q('''
    SELECT p.id, p.name as product_name, p.unit, p.stock as current_stock,
           COALESCE(SUM(si.quantity), 0) as qty_sold,
           COALESCE(SUM(si.total), 0) as revenue
    FROM products p
    LEFT JOIN (
      SELECT si2.product_id, si2.quantity, si2.total
      FROM sale_items si2
      JOIN sales s2 ON si2.sale_id=s2.id
      WHERE DATE(s2.created_at) BETWEEN ? AND ?
    ) si ON si.product_id = p.id
    WHERE p.is_active = 1
    GROUP BY p.id ORDER BY qty_sold DESC
  ''', [from, to]);

  // ─── SALES ANALYSIS ───────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getSalesAnalysis(String from, String to) async {
    final byEmployee = await _q('''
      SELECT COALESCE(e.name, 'Inconnu') as employee_name,
             COUNT(*) as orders, COALESCE(SUM(s.total), 0) as revenue
      FROM sales s LEFT JOIN employees e ON s.employee_id=e.id
      WHERE DATE(s.created_at) BETWEEN ? AND ?
      GROUP BY s.employee_id ORDER BY revenue DESC
    ''', [from, to]);

    final stats = (await _q('''
      SELECT COALESCE(AVG(total),0) as avg,
             COALESCE(MAX(total),0) as max_sale,
             COALESCE(MIN(total),0) as min_sale
      FROM sales WHERE DATE(created_at) BETWEEN ? AND ?
    ''', [from, to])).first;

    final byHour = await _q('''
      SELECT strftime('%H', created_at) as hour, COUNT(*) as c, SUM(total) as t
      FROM sales WHERE DATE(created_at) BETWEEN ? AND ?
      GROUP BY hour ORDER BY hour
    ''', [from, to]);

    return {
      'by_employee': byEmployee,
      'avg_basket':  stats['avg']      ?? 0,
      'max_sale':    stats['max_sale'] ?? 0,
      'min_sale':    stats['min_sale'] ?? 0,
      'by_hour':     byHour,
    };
  }

  // ─── SUPPLIER PAYMENTS ────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getSupplierPayments(int supplierId) async =>
      _cq('supplier_payments', w: 'supplier_id=?', wa: [supplierId], ob: 'created_at DESC');

  Future<void> addSupplierPayment(Map<String, dynamic> data) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert('supplier_payments', data);
      final amount = (data['amount'] as num).toDouble();
      await txn.rawUpdate(
          'UPDATE suppliers SET balance=balance-? WHERE id=?',
          [amount, data['supplier_id']]);
    });
  }

  // ─── RETURNS ──────────────────────────────────────────────────────────────

  Future<int> createReturn(Map<String, dynamic> ret,
      List<Map<String, dynamic>> items) async {
    final db = await database;
    return db.transaction((txn) async {
      final retId = await txn.insert('returns', ret);
      for (final item in items) {
        await txn.insert('return_items', {...item, 'return_id': retId});
        if (item['product_id'] != null) {
          await txn.rawUpdate(
              'UPDATE products SET stock=stock+? WHERE id=?',
              [item['quantity'], item['product_id']]);
        }
      }
      if (ret['customer_id'] != null) {
        await txn.rawUpdate(
            'UPDATE customers SET balance=balance+? WHERE id=?',
            [ret['total_amount'], ret['customer_id']]);
      }
      return retId;
    });
  }

  Future<List<Map<String, dynamic>>> getReturns(
      {String? from, String? to}) async {
    final where = <String>[];
    final args  = <dynamic>[];
    if (from != null) { where.add('DATE(r.created_at)>=?'); args.add(from); }
    if (to   != null) { where.add('DATE(r.created_at)<=?'); args.add(to); }
    final w = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    return _q('''
      SELECT r.*, c.name as customer_name, e.name as employee_name
      FROM returns r
      LEFT JOIN customers c ON r.customer_id=c.id
      LEFT JOIN employees e ON r.employee_id=e.id
      $w ORDER BY r.created_at DESC
    ''', args);
  }

  Future<List<Map<String, dynamic>>> getReturnItems(int returnId) async =>
      _cq('return_items', w: 'return_id=?', wa: [returnId]);

  // ─── STOCK ADJUSTMENTS ────────────────────────────────────────────────────

  Future<void> adjustStockWithLog(int productId, String productName,
      double delta, String reason, int? employeeId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.rawUpdate(
          'UPDATE products SET stock=stock+? WHERE id=?', [delta, productId]);
      await txn.insert('stock_adjustments', {
        'product_id':   productId,
        'product_name': productName,
        'delta':        delta,
        'reason':       reason,
        'employee_id':  employeeId,
      });
    });
  }

  Future<List<Map<String, dynamic>>> getStockAdjustments(
      {int? productId, String? from, String? to}) async {
    final where = <String>[];
    final args  = <dynamic>[];
    if (productId != null) { where.add('sa.product_id=?');       args.add(productId); }
    if (from      != null) { where.add('DATE(sa.created_at)>=?'); args.add(from); }
    if (to        != null) { where.add('DATE(sa.created_at)<=?'); args.add(to); }
    final w = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    return _q('''
      SELECT sa.*, e.name as employee_name
      FROM stock_adjustments sa
      LEFT JOIN employees e ON sa.employee_id=e.id
      $w ORDER BY sa.created_at DESC
    ''', args);
  }

  // ─── EXPENSE HEAD DELETE ──────────────────────────────────────────────────

  Future<void> deleteExpenseHead(int id) async =>
      _cd('expense_heads', w: 'id=?', wa: [id]);

  Future<int> updateExpense(Map<String, dynamic> data) async {
    await _cu('expenses', data, w: 'id=?', wa: [data['id']]);
    return data['id'] as int;
  }
}
