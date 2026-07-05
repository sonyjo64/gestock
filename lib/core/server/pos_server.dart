import 'dart:convert';
import 'dart:io';
import 'dart:math';
import '../database/db.dart';
import 'network_crypto.dart';

/// Serveur HTTP intégré au poste principal.
/// Les terminaux se connectent via IP:port + code d'accès.
/// Démarrer depuis Paramètres → Réseau.
///
/// Sécurité : le code d'accès brut n'est jamais envoyé sur le réseau (voir
/// [NetworkCrypto]), le corps des requêtes/réponses est chiffré (AES-GCM),
/// les tentatives d'accès invalides sont limitées (anti brute-force), et la
/// route SQL générique n'accepte que les tables connues de l'application.
class PosServer {
  static const int defaultPort = 4321;
  static final PosServer instance = PosServer._();
  PosServer._();

  HttpServer? _server;
  String  _token    = '';
  String  _authTag  = '';
  int     _port     = defaultPort;

  final Map<String, _AttemptTracker> _attempts = {};

  bool   get isRunning => _server != null;
  int    get port      => _port;
  String get token     => _token;

  /// Tables connues de l'application — toute requête SQL brute référençant
  /// une autre table (ou une instruction DDL/PRAGMA) est rejetée.
  static const _allowedTables = {
    'settings', 'employees', 'categories', 'products', 'customers',
    'suppliers', 'sales', 'sale_items', 'held_orders', 'banks',
    'bank_transactions', 'expense_heads', 'expenses', 'supplier_payments',
    'returns', 'return_items', 'stock_adjustments',
  };

  // ── Démarrage / Arrêt ────────────────────────────────────────────────────

  Future<void> start({int port = defaultPort, String? customToken}) async {
    if (_server != null) return;
    _port  = port;
    _token = (customToken != null && customToken.trim().isNotEmpty)
        ? customToken.trim().toUpperCase()
        : _makeToken();
    _authTag = await NetworkCrypto.authTag(_token);
    _attempts.clear();
    _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
    _server!.listen(_handle, onError: (_) {});
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  // ── Adresses IP locales ──────────────────────────────────────────────────

  static Future<List<String>> getLocalIps() async {
    final ips = <String>[];
    try {
      for (final iface in await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false)) {
        for (final addr in iface.addresses) {
          ips.add(addr.address);
        }
      }
    } catch (_) {}
    if (ips.isEmpty) ips.add('127.0.0.1');
    return ips;
  }

  // ── Génération du code d'accès ───────────────────────────────────────────

  String _makeToken() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(10, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  // ── Anti brute-force ─────────────────────────────────────────────────────

  bool _isLocked(String ip) {
    final t = _attempts[ip];
    if (t?.lockedUntil == null) return false;
    if (DateTime.now().isAfter(t!.lockedUntil!)) {
      t.lockedUntil = null;
      t.count = 0;
      return false;
    }
    return true;
  }

  void _registerFailure(String ip) {
    final t = _attempts.putIfAbsent(ip, () => _AttemptTracker());
    t.count++;
    if (t.count >= 5) {
      final extra = (t.count - 5).clamp(0, 4);
      t.lockedUntil = DateTime.now().add(Duration(seconds: 30 * (1 << extra)));
    }
  }

  void _registerSuccess(String ip) {
    _attempts.remove(ip);
  }

  // ── Routeur principal ────────────────────────────────────────────────────

  Future<void> _handle(HttpRequest req) async {
    req.response.headers
      ..contentType = ContentType.json
      ..add('Access-Control-Allow-Origin', '*');

    final ip = req.connectionInfo?.remoteAddress.address ?? 'unknown';
    if (_isLocked(ip)) {
      req.response.statusCode = 429;
      req.response.write(jsonEncode({'error': 'Trop de tentatives — réessayez plus tard'}));
      await req.response.close();
      return;
    }

    // Vérification du jeton d'authentification (dérivé du code d'accès,
    // jamais le code brut — voir NetworkCrypto).
    final tok = req.headers.value('x-pos-token') ?? '';
    if (tok != _authTag) {
      _registerFailure(ip);
      req.response.statusCode = 401;
      req.response.write(jsonEncode({'error': 'Code d\'accès incorrect'}));
      await req.response.close();
      return;
    }
    _registerSuccess(ip);

    try {
      final route = '${req.method} ${req.uri.path}';
      switch (route) {

        case 'GET /ping':
          req.response.write(jsonEncode({'status': 'ok', 'version': '1.0.0'}));
          break;

        case 'POST /sql':
          await _handleSql(req);
          return; // réponse fermée dans _handleSql

        case 'POST /api/create-sale':
          final b  = await _body(req);
          final id = await DB.instance.createSale(_map(b['sale']), _list(b['items']));
          await _respond(req, {'id': id});
          return;

        case 'POST /api/void-sale':
          final b  = await _body(req);
          final ok = await DB.instance.voidSale(b['id'] as int);
          await _respond(req, {'ok': ok});
          return;

        case 'POST /api/add-bank-transaction':
          final b  = await _body(req);
          final id = await DB.instance.addBankTransaction(_map(b));
          await _respond(req, {'id': id});
          return;

        case 'POST /api/bulk-import':
          final b      = await _body(req);
          final result = await DB.instance.bulkImportProducts(_list(b['rows']));
          await _respond(req, result);
          return;

        default:
          req.response.statusCode = 404;
          req.response.write(jsonEncode({'error': 'Route inconnue: $route'}));
      }
    } catch (e) {
      req.response.statusCode = 500;
      req.response.write(jsonEncode({'error': e.toString()}));
    }
    await req.response.close();
  }

  // ── Proxy SQL générique (liste blanche de tables) ────────────────────────

  Future<void> _handleSql(HttpRequest req) async {
    try {
      final b      = await _body(req);
      final type   = b['type']   as String? ?? 'query';
      final sql    = b['sql']    as String;
      final params = (b['params'] as List?)?.toList() ?? <dynamic>[];

      if (!_isSqlAllowed(sql)) {
        req.response.statusCode = 403;
        req.response.write(jsonEncode({'error': 'Requête non autorisée'}));
        await req.response.close();
        return;
      }

      final db = await DB.instance.database;
      switch (type) {
        case 'query':
          await _respond(req, {'rows': await db.rawQuery(sql, params)});
          return;
        case 'insert':
          await _respond(req, {'id': await db.rawInsert(sql, params)});
          return;
        case 'update':
          await _respond(req, {'changes': await db.rawUpdate(sql, params)});
          return;
        case 'delete':
          await _respond(req, {'changes': await db.rawDelete(sql, params)});
          return;
        default:
          req.response.statusCode = 400;
          req.response.write(jsonEncode({'error': 'Type SQL inconnu: $type'}));
      }
    } catch (e) {
      req.response.statusCode = 500;
      req.response.write(jsonEncode({'error': e.toString()}));
    }
    await req.response.close();
  }

  /// Défense en profondeur : rejette les instructions multiples, le DDL et
  /// les tables hors du schéma connu de l'application.
  bool _isSqlAllowed(String sql) {
    final lower = sql.toLowerCase();
    if (lower.contains(';')) return false;
    const forbidden = [
      'pragma', 'attach', 'detach', 'drop ', 'alter ', 'create ',
      'vacuum', 'sqlite_master', 'sqlite_schema',
    ];
    for (final f in forbidden) {
      if (lower.contains(f)) return false;
    }
    final tables = RegExp(r'\b(?:from|into|update|join)\s+([a-zA-Z_][a-zA-Z0-9_]*)')
        .allMatches(lower)
        .map((m) => m.group(1)!)
        .toSet();
    if (tables.isEmpty) return false;
    return tables.every(_allowedTables.contains);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Déchiffre le corps de la requête (AES-GCM) puis décode le JSON.
  Future<Map<String, dynamic>> _body(HttpRequest req) async {
    final raw = await utf8.decoder.bind(req).join();
    final plain = await NetworkCrypto.decrypt(_token, raw);
    return jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
  }

  /// Chiffre puis envoie une réponse de succès (statut 200).
  Future<void> _respond(HttpRequest req, Map<String, dynamic> data) async {
    final encrypted = await NetworkCrypto.encrypt(_token, utf8.encode(jsonEncode(data)));
    req.response.write(encrypted);
    await req.response.close();
  }

  Map<String, dynamic> _map(dynamic v) =>
      Map<String, dynamic>.from(v as Map);

  List<Map<String, dynamic>> _list(dynamic v) =>
      (v as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
}

class _AttemptTracker {
  int count = 0;
  DateTime? lockedUntil;
}
