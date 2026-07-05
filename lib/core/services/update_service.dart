import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../app_version.dart';

class UpdateInfo {
  final String version;
  final String downloadUrl;
  final String notes;
  const UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.notes,
  });
}

/// Vérifie et installe les mises à jour via les Releases GitHub du dépôt
/// public `sonyjo64/gestock`. L'API GitHub Releases est publique et ne
/// nécessite aucun jeton embarqué dans l'application.
class UpdateService {
  static const _repo = 'sonyjo64/gestock';

  /// Retourne les informations de mise à jour si une version plus récente
  /// existe, sinon null (y compris en cas d'erreur réseau — jamais bloquant).
  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      final res = await http
          .get(
            Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final tag = (data['tag_name'] as String? ?? '').replaceFirst(RegExp('^v'), '');
      if (tag.isEmpty || !_isNewer(tag, kAppVersion)) return null;

      final assets = (data['assets'] as List?) ?? [];
      Map<String, dynamic>? exeAsset;
      for (final a in assets) {
        final asset = a as Map<String, dynamic>;
        if ((asset['name'] as String? ?? '').toLowerCase().endsWith('.exe')) {
          exeAsset = asset;
          break;
        }
      }
      final url = exeAsset?['browser_download_url'] as String?;
      if (url == null) return null;

      return UpdateInfo(
        version: tag,
        downloadUrl: url,
        notes: (data['body'] as String? ?? '').trim(),
      );
    } catch (_) {
      return null;
    }
  }

  static bool _isNewer(String remote, String local) {
    List<int> parse(String v) =>
        v.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    final r = parse(remote), l = parse(local);
    for (var i = 0; i < 3; i++) {
      final rv = i < r.length ? r[i] : 0;
      final lv = i < l.length ? l[i] : 0;
      if (rv != lv) return rv > lv;
    }
    return false;
  }

  /// Télécharge l'installateur vers un dossier temporaire et retourne son chemin.
  static Future<String> downloadInstaller(
    String url, {
    void Function(double progress)? onProgress,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final dest = p.join(tempDir.path, 'Gestock_Update.exe');

    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url));
      final res = await client.send(req);
      final total = res.contentLength ?? 0;
      var received = 0;
      final sink = File(dest).openWrite();
      await for (final chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.close();
      return dest;
    } finally {
      client.close();
    }
  }

  /// Lance l'installateur téléchargé puis ferme l'application actuelle
  /// (nécessaire : Windows ne permet pas d'écraser un .exe en cours d'exécution).
  static Future<void> launchInstallerAndExit(String installerPath) async {
    await Process.start(installerPath, [], mode: ProcessStartMode.detached);
    exit(0);
  }
}
