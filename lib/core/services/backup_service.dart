import 'dart:io';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../database/db.dart';

/// Opérations de sauvegarde locale et d'envoi par email, utilisées à la fois
/// par les boutons manuels de Settings et par [AutoBackupScheduler].
class BackupService {
  /// Dossier de sauvegarde : [customDir] si fourni, sinon Documents\posbackup.
  static Future<Directory> backupDirectory([String? customDir]) async {
    if (customDir != null && customDir.isNotEmpty) return Directory(customDir);
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'posbackup'));
  }

  /// Crée une copie horodatée de la base de données et retourne le fichier créé.
  static Future<File> createLocalBackup({String? customDir}) async {
    final src = File(DB.instance.dbPath);
    if (!src.existsSync()) {
      throw Exception('Base de données introuvable.');
    }
    final dir = await backupDirectory(customDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
    final dest = p.join(dir.path, 'pos_backup_$ts.db');
    return src.copy(dest);
  }

  /// Supprime les sauvegardes les plus anciennes au-delà de [keep] fichiers.
  static Future<void> pruneOldBackups(Directory dir, int keep) async {
    if (!dir.existsSync()) return;
    final files = dir.listSync().whereType<File>()
        .where((f) => f.path.endsWith('.db')).toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    for (final f in files.skip(keep)) {
      try {
        f.deleteSync();
      } catch (_) {}
    }
  }

  /// Envoie un fichier de sauvegarde par email via SMTP (configuration propre
  /// au commerçant — aucun identifiant n'est partagé entre installations).
  static Future<void> sendBackupEmail({
    required File backupFile,
    required String host,
    required int port,
    required bool secure,
    required String username,
    required String password,
    required String recipient,
  }) async {
    final smtpServer = SmtpServer(
      host,
      port: port,
      ssl: secure,
      username: username,
      password: password,
    );
    final message = Message()
      ..from = Address(username, 'Gestock POS')
      ..recipients.add(recipient)
      ..subject = 'Sauvegarde Gestock — ${DateTime.now().toLocal()}'
      ..text = 'Sauvegarde automatique de la base de données en pièce jointe.'
      ..attachments.add(FileAttachment(backupFile));
    await send(message, smtpServer);
  }
}
