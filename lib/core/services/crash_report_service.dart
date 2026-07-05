import 'dart:io';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import '../app_version.dart';
import '../database/db.dart';

/// Envoie un rapport d'erreur/plantage par email au développeur, en
/// réutilisant la configuration SMTP de la sauvegarde cloud (Settings →
/// Sécurité postes → Sauvegarde cloud par email).
///
/// Ne fonctionne que si le commerçant a déjà configuré cette section (mêmes
/// identifiants, pas de compte supplémentaire à créer). Limité à un envoi
/// toutes les 15 minutes pour éviter de spammer en cas d'erreur répétée.
class CrashReportService {
  static final CrashReportService instance = CrashReportService._();
  CrashReportService._();

  static const _minInterval = Duration(minutes: 15);
  static const _supportEmail = 'josony1994@gmail.com';

  DateTime? _lastSent;

  Future<void> report(Object error, StackTrace stack, {String? context}) async {
    try {
      final now = DateTime.now();
      if (_lastSent != null && now.difference(_lastSent!) < _minInterval) return;

      final settings = await DB.instance.getSettings();
      if (settings['crash_reporting_enabled'] == '0') return;

      final host = settings['cloud_backup_smtp_host'] ?? '';
      final user = settings['cloud_backup_username'] ?? '';
      final pass = settings['cloud_backup_password'] ?? '';
      if (host.isEmpty || user.isEmpty || pass.isEmpty) return; // SMTP non configuré

      _lastSent = now; // marqué avant l'envoi pour éviter les doublons concurrents

      final port      = int.tryParse(settings['cloud_backup_smtp_port'] ?? '587') ?? 587;
      final secure    = settings['cloud_backup_smtp_secure'] == '1';
      final business  = settings['business_name'] ?? 'Boutique inconnue';

      final smtpServer = SmtpServer(host, port: port, ssl: secure, username: user, password: pass);
      final message = Message()
        ..from = Address(user, 'Gestock POS')
        ..recipients.add(_supportEmail)
        ..subject = 'Erreur Gestock — $business — ${now.toLocal()}'
        ..text = '''
Boutique : $business
Version  : $kAppVersion
Système  : ${Platform.operatingSystem} ${Platform.operatingSystemVersion}
Date     : ${now.toLocal()}
${context != null ? 'Contexte : $context\n' : ''}
Erreur   : $error

Trace :
$stack
''';
      await send(message, smtpServer);
    } catch (_) {
      // Un échec d'envoi de rapport ne doit jamais faire planter l'app.
    }
  }
}
