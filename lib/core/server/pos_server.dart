import 'dart:convert';
import 'dart:io';
import 'dart:math';
import '../database/db.dart';

/// Serveur HTTP intégré au poste principal.
/// Les terminaux se connectent via IP:port + code d'accès.
/// Démarrer depuis Paramètres → Réseau.
class PosServer {
  static const int defaultPort = 4321;
  static final PosServer instance = PosServer._();
  PosServer._();

  HttpServer? _server;
  String  _token = '';
  int     _port  = defaultPort;

  bool   get isRunning => _server != null;
  int    get port      => _port;
  String get token     => _token;

  // ── Démarrage / Arrêt ────────────────────────────────────────────────────

  Future<void> start({int port = defaultPort, String? customToken}) async {
    if (_server != null) return;
    _port  = port;
    _token = (customToken != null && customToken.trim().isNotEmpty)
        ? customToken.trim().toUpperCase()
        : _makeToken();
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
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  // ── Routeur principal ────────────────────────────────────────────────────

  Future<void> _handle(HttpRequest req) async {
    req.response.headers
      ..contentType = ContentType.json
      ..add('Access-Control-Allow-Origin', '*');

    // Vérification du code d'accès
    final tok = req.headers.value('x-pos-token') ?? '';
    if (tok != _token) {
      req.response.statusCode = 401;
      req.response.write(jsonEncode({'error': 'Code d\'accès incorrect'}));
      await req.response.close();
      return;
    }

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
          req.response.write(jsonEncode({'id': id}));
          break;

        case 'POST /api/void-sale':
          final b  = await _body(req);
          final ok = await DB.instance.voidSale(b['id'] as int);
          req.response.write(jsonEncode({'ok': ok}));
          break;

        case 'POST /api/add-bank-transaction':
          final b  = await _body(req);
          final id = await DB.instance.addBankTransaction(_map(b));
          req.response.write(jsonEncode({'id': id}));
          break;

        case 'POST /api/bulk-import':
          final b      = await _body(req);
          final result = await DB.instance.bulkImportProducts(_list(b['rows']));
          req.response.write(jsonEncode(result));
          break;

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

  // ── Proxy SQL générique ──────────────────────────────────────────────────

  Future<void> _handleSql(HttpRequest req) async {
    try {
      final b      = await _body(req);
      final type   = b['type']   as String? ?? 'query';
      final sql    = b['sql']    as String;
      final params = (b['params'] as List?)?.toList() ?? <dynamic>[];
      final db     = await DB.instance.database;

      switch (type) {
        case 'query':
          req.response.write(jsonEncode({'rows': await db.rawQuery(sql, params)}));
          break;
        case 'insert':
          req.response.write(jsonEncode({'id': await db.rawInsert(sql, params)}));
          break;
        case 'update':
          req.response.write(jsonEncode({'changes': await db.rawUpdate(sql, params)}));
          break;
        case 'delete':
          req.response.write(jsonEncode({'changes': await db.rawDelete(sql, params)}));
          break;
        case 'execute':
          await db.execute(sql, params);
          req.response.write(jsonEncode({'ok': true}));
          break;
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

  // ── Helpers ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _body(HttpRequest req) async =>
      jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;

  Map<String, dynamic> _map(dynamic v) =>
      Map<String, dynamic>.from(v as Map);

  List<Map<String, dynamic>> _list(dynamic v) =>
      (v as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
}
