import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart';

/// Paramètres locaux stockés dans [exe_dir]/pos_config.json.
/// Chargés AVANT l'ouverture de la base SQLite (dans main()).
class LocalSettings {
  LocalSettings._();

  static const _filename = 'pos_config.json';

  static bool   _serverMode  = false;
  static String _serverIp    = '';
  static int    _serverPort  = 4321;
  static String _serverToken = '';
  static String _serverLabel = '';

  /// True si ce poste est configuré en mode terminal (connexion serveur).
  static bool   get isServerMode  => _serverMode;
  static String get serverIp      => _serverIp;
  static int    get serverPort    => _serverPort;
  static String get serverToken   => _serverToken;

  /// Libellé affiché dans l'interface (ex : "Serveur principal").
  static String get serverLabel =>
      _serverLabel.isNotEmpty ? _serverLabel : '$_serverIp:$_serverPort';

  static String get _configPath =>
      join(Directory.current.path, _filename);

  // ── Initialisation (appelée dans main() avant runApp) ──────────────────────

  static Future<void> initialize() async {
    try {
      final file = File(_configPath);
      if (!file.existsSync()) return;
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      _serverMode  = json['server_mode']  as bool?   ?? false;
      _serverIp    = json['server_ip']    as String? ?? '';
      _serverPort  = json['server_port']  as int?    ?? 4321;
      _serverToken = json['server_token'] as String? ?? '';
      _serverLabel = json['server_label'] as String? ?? '';
    } catch (_) {
      _serverMode = false;
      _serverIp   = '';
    }
  }

  // ── Persistence ────────────────────────────────────────────────────────────

  static Future<void> enableServerMode(
      String ip, int port, String token, {String label = ''}) async {
    _serverMode  = true;
    _serverIp    = ip;
    _serverPort  = port;
    _serverToken = token;
    _serverLabel = label;
    await _save();
  }

  static Future<void> disableServerMode() async {
    _serverMode  = false;
    _serverIp    = '';
    _serverPort  = 4321;
    _serverToken = '';
    _serverLabel = '';
    await _save();
  }

  static Future<void> _save() async {
    try {
      final map = <String, dynamic>{'server_mode': _serverMode};
      if (_serverIp.isNotEmpty)    map['server_ip']    = _serverIp;
      if (_serverPort > 0)         map['server_port']  = _serverPort;
      if (_serverToken.isNotEmpty) map['server_token'] = _serverToken;
      if (_serverLabel.isNotEmpty) map['server_label'] = _serverLabel;
      File(_configPath).writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(map));
    } catch (_) {}
  }
}
