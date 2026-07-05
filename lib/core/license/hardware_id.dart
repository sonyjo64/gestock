import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

/// Identifiant de machine stable, dérivé du MachineGuid Windows.
/// Utilisé pour lier une licence à un nombre précis de postes.
class HardwareId {
  static String? _cached;

  /// Identifiant de 16 caractères hexadécimaux (dérivé, pas le GUID brut).
  static Future<String> get() async {
    final cached = _cached;
    if (cached != null) return cached;
    final guid = await _readMachineGuid();
    final digest = sha256.convert(utf8.encode(guid)).toString().toUpperCase();
    final id = digest.substring(0, 16);
    _cached = id;
    return id;
  }

  /// Formate pour affichage : XXXX-XXXX-XXXX-XXXX
  static String format(String id) {
    final buf = StringBuffer();
    for (var i = 0; i < id.length; i++) {
      if (i > 0 && i % 4 == 0) buf.write('-');
      buf.write(id[i]);
    }
    return buf.toString();
  }

  static Future<String> _readMachineGuid() async {
    try {
      final result = await Process.run('reg', [
        'query',
        r'HKLM\SOFTWARE\Microsoft\Cryptography',
        '/v',
        'MachineGuid',
      ]);
      if (result.exitCode == 0) {
        final out = result.stdout as String;
        final match = RegExp(r'MachineGuid\s+REG_SZ\s+([0-9a-fA-F-]+)')
            .firstMatch(out);
        if (match != null) return match.group(1)!;
      }
    } catch (_) {}
    // Repli si la lecture du registre échoue (permissions, environnement
    // non-Windows en dev…) : identifiant moins stable mais fonctionnel.
    return 'fallback-${Platform.localHostname}-${Platform.numberOfProcessors}';
  }
}
