import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Client HTTP pour le mode terminal.
/// Connecte ce poste au serveur POS via IP:port + code d'accès.
class PosClient {
  static final PosClient instance = PosClient._();
  PosClient._();

  String? _url;
  String? _token;

  bool   get isConnected  => _url != null && _token != null;
  String get displayLabel => _url?.replaceFirst('http://', '') ?? '';

  // ── Configuration ────────────────────────────────────────────────────────

  void configure(String ip, int port, String token) {
    _url   = 'http://$ip:$port';
    _token = token;
  }

  void disconnect() {
    _url   = null;
    _token = null;
  }

  // ── Test de connexion (statique) ─────────────────────────────────────────

  /// Retourne null si la connexion réussit, ou un message d'erreur.
  static Future<String?> ping(String ip, int port, String token) async {
    try {
      final res = await http.get(
        Uri.parse('http://$ip:$port/ping'),
        headers: {'x-pos-token': token},
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map;
        return data['status'] == 'ok' ? null : 'Réponse inattendue du serveur';
      }
      if (res.statusCode == 401) return 'Code d\'accès incorrect';
      return 'Erreur HTTP ${res.statusCode}';
    } on Exception catch (e) {
      final msg = e.toString();
      if (msg.contains('Connection refused') || msg.contains('refused')) {
        return 'Connexion refusée — vérifiez l\'IP et le port';
      }
      if (msg.contains('timeout') || msg.contains('TimeoutException')) {
        return 'Délai dépassé — hôte inaccessible';
      }
      return 'Erreur : $msg';
    }
  }

  // ── SQL proxy bas niveau ─────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> rawQuery(String sql, [List? p]) async {
    final d = await _sql({'type': 'query',  'sql': sql, 'params': p ?? const []});
    return (d['rows'] as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
  }

  Future<int> rawInsert(String sql, [List? p]) async {
    final d = await _sql({'type': 'insert', 'sql': sql, 'params': p ?? const []});
    return d['id'] as int? ?? 0;
  }

  Future<int> rawUpdate(String sql, [List? p]) async {
    final d = await _sql({'type': 'update', 'sql': sql, 'params': p ?? const []});
    return d['changes'] as int? ?? 0;
  }

  Future<int> rawDelete(String sql, [List? p]) async {
    final d = await _sql({'type': 'delete', 'sql': sql, 'params': p ?? const []});
    return d['changes'] as int? ?? 0;
  }

  Future<void> execute(String sql, [List? p]) async {
    await _sql({'type': 'execute', 'sql': sql, 'params': p ?? const []});
  }

  // ── Méthodes de commodité (construisent le SQL) ──────────────────────────

  Future<int> insert(String t, Map<String, dynamic> v,
      {ConflictAlgorithm? conflictAlgorithm}) async {
    final keys = v.keys.toList();
    final ph   = List.filled(keys.length, '?').join(', ');
    final conf = _conflictClause(conflictAlgorithm);
    return rawInsert(
        'INSERT$conf INTO $t (${keys.join(', ')}) VALUES ($ph)',
        keys.map((k) => v[k]).toList());
  }

  Future<int> update(String t, Map<String, dynamic> v, {
    String? where, List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    final conf = _conflictClause(conflictAlgorithm);
    final set  = v.keys.map((k) => '$k = ?').join(', ');
    var   sql  = 'UPDATE$conf $t SET $set';
    if (where != null) sql += ' WHERE $where';
    return rawUpdate(sql, [...v.values, ...?whereArgs]);
  }

  Future<int> delete(String t,
      {String? where, List<Object?>? whereArgs}) async {
    var sql = 'DELETE FROM $t';
    if (where != null) sql += ' WHERE $where';
    return rawDelete(sql, whereArgs);
  }

  Future<List<Map<String, dynamic>>> query(String t, {
    bool? distinct, List<String>? columns,
    String? where, List<Object?>? whereArgs,
    String? groupBy, String? having,
    String? orderBy, int? limit, int? offset,
  }) async {
    final cols = columns?.join(', ') ?? '*';
    var sql = 'SELECT ${distinct == true ? 'DISTINCT ' : ''}$cols FROM $t';
    if (where   != null) sql += ' WHERE $where';
    if (groupBy != null) sql += ' GROUP BY $groupBy';
    if (having  != null) sql += ' HAVING $having';
    if (orderBy != null) sql += ' ORDER BY $orderBy';
    if (limit   != null) sql += ' LIMIT $limit';
    if (offset  != null) sql += ' OFFSET $offset';
    return rawQuery(sql, whereArgs);
  }

  // ── Opérations atomiques (endpoints dédiés) ──────────────────────────────

  Future<int> createSale(
      Map<String, dynamic> sale, List<Map<String, dynamic>> items) async {
    final d = await _post('/api/create-sale', {'sale': sale, 'items': items});
    return d['id'] as int? ?? 0;
  }

  Future<bool> voidSale(int saleId) async {
    final d = await _post('/api/void-sale', {'id': saleId});
    return d['ok'] == true;
  }

  Future<int> addBankTransaction(Map<String, dynamic> data) async {
    final d = await _post('/api/add-bank-transaction', data);
    return d['id'] as int? ?? 0;
  }

  Future<Map<String, int>> bulkImportProducts(
      List<Map<String, dynamic>> rows) async {
    final d = await _post('/api/bulk-import', {'rows': rows});
    return {
      'inserted': d['inserted'] as int? ?? 0,
      'updated':  d['updated']  as int? ?? 0,
      'errors':   d['errors']   as int? ?? 0,
    };
  }

  // ── Helpers HTTP internes ────────────────────────────────────────────────

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'x-pos-token':  _token!,
  };

  Future<Map<String, dynamic>> _sql(Map<String, dynamic> body) =>
      _post('/sql', body);

  Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> body) async {
    final res = await http.post(
      Uri.parse('$_url$path'),
      headers: _headers,
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 15));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (data.containsKey('error')) throw Exception(data['error'] as String);
    return data;
  }

  String _conflictClause(ConflictAlgorithm? a) => switch (a) {
    ConflictAlgorithm.replace  => ' OR REPLACE',
    ConflictAlgorithm.ignore   => ' OR IGNORE',
    ConflictAlgorithm.abort    => ' OR ABORT',
    ConflictAlgorithm.fail     => ' OR FAIL',
    ConflictAlgorithm.rollback => ' OR ROLLBACK',
    _                          => '',
  };
}
