import 'dart:async';
import '../database/db.dart';
import '../server/pos_client.dart';
import 'backup_service.dart';

/// Sauvegarde automatique locale (toutes les heures) + envoi cloud par email
/// (une fois par jour), tant que l'application reste ouverte.
///
/// L'app ne tournant pas en arrière-plan une fois fermée, ceci n'est PAS une
/// vraie tâche planifiée système : c'est une vérification périodique pendant
/// l'utilisation, avec rattrapage immédiat au démarrage si l'intervalle est
/// déjà dépassé (ex : app restée fermée plus d'un jour).
class AutoBackupScheduler {
  static final AutoBackupScheduler instance = AutoBackupScheduler._();
  AutoBackupScheduler._();

  static const _localInterval = Duration(hours: 1);
  static const _cloudInterval = Duration(days: 1);
  static const _keepLocal = 48; // ~2 jours de recul à raison d'1/heure

  Timer? _timer;
  bool _running = false;

  void start() {
    if (_timer != null) return;
    // Un terminal connecté à un serveur distant n'a pas de base locale
    // exploitable — rien à sauvegarder de ce côté.
    if (PosClient.instance.isConnected) return;
    unawaited(_tick());
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    if (_running) return;
    _running = true;
    try {
      final settings = await DB.instance.getSettings();
      if (settings['auto_backup_enabled'] != '0') {
        await _maybeRunLocal(settings);
      }
      if (settings['cloud_backup_enabled'] == '1') {
        await _maybeRunCloud(settings);
      }
    } catch (_) {
      // Une sauvegarde silencieuse qui échoue ne doit jamais interrompre l'app.
    } finally {
      _running = false;
    }
  }

  Future<void> _maybeRunLocal(Map<String, String> settings) async {
    final last = DateTime.tryParse(settings['auto_backup_last_local'] ?? '');
    if (last != null && DateTime.now().difference(last) < _localInterval) return;

    final dir = settings['auto_backup_dir'] ?? '';
    final file = await BackupService.createLocalBackup(
        customDir: dir.isEmpty ? null : dir);
    await BackupService.pruneOldBackups(file.parent, _keepLocal);
    await DB.instance.setSetting(
        'auto_backup_last_local', DateTime.now().toIso8601String());
  }

  Future<void> _maybeRunCloud(Map<String, String> settings) async {
    final last = DateTime.tryParse(settings['cloud_backup_last_sent'] ?? '');
    if (last != null && DateTime.now().difference(last) < _cloudInterval) return;

    final host = settings['cloud_backup_smtp_host'] ?? '';
    final user = settings['cloud_backup_username'] ?? '';
    final pass = settings['cloud_backup_password'] ?? '';
    final dest = settings['cloud_backup_recipient'] ?? '';
    if (host.isEmpty || user.isEmpty || pass.isEmpty || dest.isEmpty) return;

    final port = int.tryParse(settings['cloud_backup_smtp_port'] ?? '587') ?? 587;
    final secure = settings['cloud_backup_smtp_secure'] == '1';
    final dir = settings['auto_backup_dir'] ?? '';

    final file = await BackupService.createLocalBackup(
        customDir: dir.isEmpty ? null : dir);
    await BackupService.sendBackupEmail(
      backupFile: file,
      host: host,
      port: port,
      secure: secure,
      username: user,
      password: pass,
      recipient: dest,
    );
    await DB.instance.setSetting(
        'cloud_backup_last_sent', DateTime.now().toIso8601String());
  }
}
