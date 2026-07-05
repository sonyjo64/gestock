import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import '../../core/utils/invoice_pdf.dart';
import 'package:provider/provider.dart';
import '../../core/database/db.dart';
import '../../core/server/pos_server.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../core/license/hardware_id.dart';
import '../../core/license/license_service.dart';
import '../../core/services/backup_service.dart';
import '../../core/app_version.dart';
import '../update/update_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres'),
        bottom: TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.store_rounded),    text: 'Boutique'),
            Tab(icon: Icon(Icons.security_rounded), text: 'Sécurité postes'),
            Tab(icon: Icon(Icons.palette_rounded),  text: 'Apparence'),
            Tab(icon: Icon(Icons.print_rounded),    text: 'Imprimante'),
            Tab(icon: Icon(Icons.vpn_key_rounded),  text: 'Licence'),
            Tab(icon: Icon(Icons.wifi_rounded),      text: 'Réseau'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: const [
          _BusinessTab(),
          _SecurityPostesTab(),
          _AppearanceTab(),
          _PrinterTab(),
          const _LicenseTab(),
          const _NetworkTab(),
        ],
      ),
    );
  }
}

// ─── BOUTIQUE ─────────────────────────────────────────────────────────────────

class _BusinessTab extends StatefulWidget {
  const _BusinessTab();
  @override State<_BusinessTab> createState() => _BusinessTabState();
}

class _BusinessTabState extends State<_BusinessTab> {
  final _nameCtrl  = TextEditingController();
  final _addrCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsProvider>();
    _nameCtrl.text  = s.businessName;
    _addrCtrl.text  = s.businessAddress;
    _phoneCtrl.text = s.businessPhone;
  }

  @override
  void dispose() { _nameCtrl.dispose(); _addrCtrl.dispose(); _phoneCtrl.dispose(); super.dispose(); }

  Future<void> _pickLogo() async {
    const tg = XTypeGroup(label: 'Images', extensions: ['jpg', 'jpeg', 'png', 'gif', 'webp']);
    final file = await openFile(acceptedTypeGroups: [tg]);
    if (file != null && mounted) await context.read<SettingsProvider>().set('logo_path', file.path);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final logoPath = settings.logoPath;
    final hasLogo  = logoPath.isNotEmpty && File(logoPath).existsSync();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Form ──
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _sectionLabel('Informations générales'),
            const SizedBox(height: 16),
            TextField(controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Nom de la boutique', prefixIcon: Icon(Icons.store))),
            const SizedBox(height: 14),
            TextField(controller: _addrCtrl,
                decoration: const InputDecoration(labelText: 'Adresse', prefixIcon: Icon(Icons.location_on)),
                maxLines: 2),
            const SizedBox(height: 14),
            TextField(controller: _phoneCtrl,
                decoration: const InputDecoration(labelText: 'Téléphone', prefixIcon: Icon(Icons.phone)),
                keyboardType: TextInputType.phone),
            const SizedBox(height: 24),
            _sectionLabel('Devise & TVA'),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: settings.currencyCode,
              decoration: const InputDecoration(labelText: 'Devise'),
              items: const [
                DropdownMenuItem(value: 'HTG', child: Text('G  Gourde haïtienne (HTG)')),
                DropdownMenuItem(value: 'USD', child: Text('\$  Dollar américain (USD)')),
                DropdownMenuItem(value: 'EUR', child: Text('€  Euro (EUR)')),
                DropdownMenuItem(value: 'GBP', child: Text('£  Livre sterling (GBP)')),
                DropdownMenuItem(value: 'MAD', child: Text('DH  Dirham marocain (MAD)')),
                DropdownMenuItem(value: 'DZD', child: Text('DA  Dinar algérien (DZD)')),
                DropdownMenuItem(value: 'TND', child: Text('DT  Dinar tunisien (TND)')),
                DropdownMenuItem(value: 'XOF', child: Text('CFA  Franc CFA (XOF)')),
              ],
              onChanged: (v) {
                const sym = {'HTG':'G','USD':'\$','EUR':'€','GBP':'£','MAD':'DH','DZD':'DA','TND':'DT','XOF':'CFA'};
                settings.setAll({'currency_code': v!, 'currency_symbol': sym[v] ?? v});
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              initialValue: settings.taxRate.toString(),
              decoration: const InputDecoration(labelText: 'Taux TVA (%)', suffixText: '%'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
              onChanged: (v) => settings.set('tax_rate', v),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : () async {
                  setState(() => _saving = true);
                  await context.read<SettingsProvider>().setAll({
                    'business_name': _nameCtrl.text.trim(),
                    'business_address': _addrCtrl.text.trim(),
                    'business_phone': _phoneCtrl.text.trim(),
                  });
                  setState(() => _saving = false);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✅  Paramètres sauvegardés'), backgroundColor: Colors.green));
                },
                icon: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_rounded, size: 18),
                label: const Text('Enregistrer les paramètres'),
              ),
            ),
          ])),

          const SizedBox(width: 32),

          // ── Logo ──
          SizedBox(width: 240, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionLabel('Logo de la boutique'),
              const SizedBox(height: 8),
              const Text('Affiché sur les reçus et l\'en-tête.',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: _pickLogo,
                child: Container(
                  width: 240, height: 180,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: hasLogo ? Colors.blue.shade300 : Colors.grey.shade300,
                      width: hasLogo ? 2 : 1,
                    ),
                  ),
                  child: hasLogo
                      ? ClipRRect(borderRadius: BorderRadius.circular(11),
                          child: Image.file(File(logoPath), fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => _noLogoWidget()))
                      : _noLogoWidget(),
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: ElevatedButton.icon(
                  onPressed: _pickLogo,
                  icon: const Icon(Icons.upload_file, size: 16),
                  label: Text(hasLogo ? 'Changer' : 'Choisir'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1565C0), foregroundColor: Colors.white),
                )),
                if (hasLogo) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => settings.set('logo_path', ''),
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    style: IconButton.styleFrom(backgroundColor: Colors.red.shade50,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  ),
                ],
              ]),
              const SizedBox(height: 6),
              const Text('JPG, PNG, GIF, WEBP\n400×200 px recommandé',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          )),
        ]),
      )),
    );
  }

  Widget _noLogoWidget() => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(Icons.add_photo_alternate_outlined, size: 44, color: Colors.grey.shade400),
      const SizedBox(height: 10),
      Text('Cliquer pour ajouter un logo',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 12), textAlign: TextAlign.center),
    ],
  );
}

// ─── SÉCURITÉ POSTES ──────────────────────────────────────────────────────────

class _SecurityPostesTab extends StatefulWidget {
  const _SecurityPostesTab();
  @override State<_SecurityPostesTab> createState() => _SecurityPostesTabState();
}

class _SecurityPostesTabState extends State<_SecurityPostesTab> {
  final _oldPwdCtrl  = TextEditingController();
  final _newPwdCtrl  = TextEditingController();
  final _confPwdCtrl = TextEditingController();
  final _pinCtrl     = TextEditingController();
  bool _pwdSaving = false;
  bool _pinSaving = false;
  bool _busy = false;
  String _lastBackup = '';

  // ── Sauvegarde cloud par email (SMTP) ──
  final _smtpHostCtrl      = TextEditingController();
  final _smtpPortCtrl      = TextEditingController(text: '587');
  final _smtpUserCtrl      = TextEditingController();
  final _smtpPassCtrl      = TextEditingController();
  final _smtpRecipientCtrl = TextEditingController();
  final _backupDirCtrl     = TextEditingController();
  bool _smtpSecure  = false;
  bool _cloudSaving = false;

  @override
  void initState() {
    super.initState();
    final sp = context.read<SettingsProvider>();
    _pinCtrl.text            = sp.screenPin;
    _smtpHostCtrl.text       = sp.settingValue('cloud_backup_smtp_host', '');
    _smtpPortCtrl.text       = sp.settingValue('cloud_backup_smtp_port', '587');
    _smtpUserCtrl.text       = sp.settingValue('cloud_backup_username', '');
    _smtpPassCtrl.text       = sp.settingValue('cloud_backup_password', '');
    _smtpRecipientCtrl.text  = sp.settingValue('cloud_backup_recipient', '');
    _backupDirCtrl.text      = sp.settingValue('auto_backup_dir', '');
    _smtpSecure = sp.settingValue('cloud_backup_smtp_secure', '0') == '1';
    _findLastBackup();
  }

  @override
  void dispose() {
    _oldPwdCtrl.dispose(); _newPwdCtrl.dispose(); _confPwdCtrl.dispose(); _pinCtrl.dispose();
    _smtpHostCtrl.dispose(); _smtpPortCtrl.dispose(); _smtpUserCtrl.dispose();
    _smtpPassCtrl.dispose(); _smtpRecipientCtrl.dispose(); _backupDirCtrl.dispose();
    super.dispose();
  }

  Future<void> _findLastBackup() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'posbackup'));
      if (!dir.existsSync()) return;
      final files = dir.listSync().whereType<File>()
          .where((f) => f.path.endsWith('.db')).toList()
        ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      if (files.isNotEmpty && mounted) setState(() => _lastBackup = p.basename(files.first.path));
    } catch (_) {}
  }

  void _snack(String msg, {bool ok = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: ok ? Colors.green : Colors.red));
  }

  Future<void> _backupLocal() async {
    setState(() => _busy = true);
    try {
      final src = File(DB.instance.dbPath);
      if (!src.existsSync()) { _snack('Base de données introuvable.', ok: false); return; }
      final docs = await getApplicationDocumentsDirectory();
      final dir  = Directory(p.join(docs.path, 'posbackup'));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final ts   = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
      final dest = p.join(dir.path, 'pos_backup_$ts.db');
      await src.copy(dest);
      setState(() => _lastBackup = p.basename(dest));
      _snack('Sauvegarde : pos_backup_$ts.db');
    } catch (e) {
      _snack('Erreur : $e', ok: false);
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _backupOnline() async {
    final sp = context.read<SettingsProvider>();
    final host = sp.settingValue('cloud_backup_smtp_host', '');
    final user = sp.settingValue('cloud_backup_username', '');
    final pass = sp.settingValue('cloud_backup_password', '');
    final dest = sp.settingValue('cloud_backup_recipient', '');
    if (host.isEmpty || user.isEmpty || pass.isEmpty || dest.isEmpty) {
      _snack('Configurez d\'abord la sauvegarde cloud par email ci-dessous.', ok: false);
      return;
    }
    setState(() => _busy = true);
    try {
      final port   = int.tryParse(sp.settingValue('cloud_backup_smtp_port', '587')) ?? 587;
      final secure = sp.settingValue('cloud_backup_smtp_secure', '0') == '1';
      final dir    = sp.settingValue('auto_backup_dir', '');
      final file   = await BackupService.createLocalBackup(customDir: dir.isEmpty ? null : dir);
      await BackupService.sendBackupEmail(
        backupFile: file, host: host, port: port, secure: secure,
        username: user, password: pass, recipient: dest,
      );
      await sp.set('cloud_backup_last_sent', DateTime.now().toIso8601String());
      _snack('Sauvegarde envoyée à $dest');
    } catch (e) {
      _snack('Envoi impossible : $e', ok: false);
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _saveCloudConfig() async {
    setState(() => _cloudSaving = true);
    try {
      await context.read<SettingsProvider>().setAll({
        'cloud_backup_smtp_host':   _smtpHostCtrl.text.trim(),
        'cloud_backup_smtp_port':   _smtpPortCtrl.text.trim(),
        'cloud_backup_smtp_secure': _smtpSecure ? '1' : '0',
        'cloud_backup_username':    _smtpUserCtrl.text.trim(),
        'cloud_backup_password':    _smtpPassCtrl.text,
        'cloud_backup_recipient':   _smtpRecipientCtrl.text.trim(),
        'auto_backup_dir':          _backupDirCtrl.text.trim(),
      });
      _snack('Configuration enregistrée');
    } finally {
      setState(() => _cloudSaving = false);
    }
  }

  Future<void> _pickBackupDir() async {
    final dir = await getDirectoryPath();
    if (dir != null) setState(() => _backupDirCtrl.text = dir);
  }

  Future<void> _restore() async {
    const tg = XTypeGroup(label: 'Base de données', extensions: ['db']);
    final file = await openFile(acceptedTypeGroups: [tg]);
    if (file == null || !mounted) return;
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Confirmer la restauration'),
      content: Text('Remplacer la base par :\n${file.name}\n\nToutes les données actuelles seront perdues.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
          child: const Text('Restaurer'),
        ),
      ],
    ));
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await DB.instance.closeAndReset();
      await File(file.path).copy(DB.instance.dbPath);
      if (mounted) await context.read<SettingsProvider>().load();
      _snack('Base restaurée avec succès');
    } catch (e) {
      _snack('Erreur : $e', ok: false);
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _viewBackups() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir  = Directory(p.join(docs.path, 'posbackup'));
      if (!dir.existsSync()) { _snack('Aucun dossier de sauvegarde.', ok: false); return; }
      await Process.run('explorer', [dir.path]);
    } catch (e) {
      _snack('Impossible d\'ouvrir : $e', ok: false);
    }
  }

  Future<void> _clearData() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Row(children: [
        Icon(Icons.warning, color: Colors.red), SizedBox(width: 8),
        Text('Effacement total', style: TextStyle(color: Colors.red)),
      ]),
      content: const Text('Supprime toutes les ventes, dépenses et transactions.\nCette action est IRRÉVERSIBLE.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          child: const Text('Effacer'),
        ),
      ],
    ));
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final db = await DB.instance.database;
      for (final t in ['sale_items', 'sales', 'expenses', 'bank_transactions', 'held_orders']) {
        await db.delete(t);
      }
      _snack('Données transactionnelles effacées');
    } catch (e) {
      _snack('Erreur : $e', ok: false);
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Mot de passe ──
          _sectionLabel('Changer le mot de passe'),
          const SizedBox(height: 16),
          TextField(controller: _oldPwdCtrl, obscureText: true,
              decoration: const InputDecoration(labelText: 'Mot de passe actuel', prefixIcon: Icon(Icons.lock_outline))),
          const SizedBox(height: 12),
          TextField(controller: _newPwdCtrl, obscureText: true,
              decoration: const InputDecoration(labelText: 'Nouveau mot de passe', prefixIcon: Icon(Icons.lock_reset))),
          const SizedBox(height: 12),
          TextField(controller: _confPwdCtrl, obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirmer le nouveau mot de passe', prefixIcon: Icon(Icons.lock_reset))),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _pwdSaving ? null : () async {
              if (_newPwdCtrl.text != _confPwdCtrl.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Les mots de passe ne correspondent pas'), backgroundColor: Colors.red));
                return;
              }
              setState(() => _pwdSaving = true);
              final auth = context.read<AuthProvider>();
              final ok = await DB.instance.updatePassword(auth.user!['id'] as int, _oldPwdCtrl.text, _newPwdCtrl.text);
              setState(() => _pwdSaving = false);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(ok ? 'Mot de passe modifié' : 'Ancien mot de passe incorrect'),
                  backgroundColor: ok ? Colors.green : Colors.red,
                ));
                if (ok) { _oldPwdCtrl.clear(); _newPwdCtrl.clear(); _confPwdCtrl.clear(); }
              }
            },
            icon: _pwdSaving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.lock_reset),
            label: const Text('Modifier le mot de passe'),
          ),

          const SizedBox(height: 28), const Divider(), const SizedBox(height: 20),

          // ── PIN & verrouillage ──
          _sectionLabel('Verrouillage du poste'),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Verrouillage automatique'),
            subtitle: const Text('Demande le PIN après inactivité'),
            value: settings.requirePinOnIdle,
            onChanged: (v) => settings.set('require_pin_idle', v ? '1' : '0'),
            secondary: const Icon(Icons.lock_clock),
          ),
          if (settings.requirePinOnIdle) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                const Text('Délai : ', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: settings.autoLockMinutes,
                  items: [1, 2, 5, 10, 15, 30].map((m) =>
                      DropdownMenuItem(value: m, child: Text('$m min'))).toList(),
                  onChanged: (v) => settings.set('auto_lock_minutes', v.toString()),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: TextFormField(
              controller: _pinCtrl,
              decoration: const InputDecoration(
                labelText: 'PIN de déverrouillage',
                hintText: '4 chiffres',
                prefixIcon: Icon(Icons.pin),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
              obscureText: true,
            )),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _pinSaving ? null : () async {
                setState(() => _pinSaving = true);
                await settings.set('screen_pin', _pinCtrl.text);
                setState(() => _pinSaving = false);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✅  PIN sauvegardé'), backgroundColor: Colors.green));
              },
              icon: _pinSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded, size: 18),
              label: const Text('Enregistrer le PIN'),
            ),
          ]),

          const SizedBox(height: 28), const Divider(), const SizedBox(height: 20),

          // ── Sauvegarde ──
          _sectionLabel('Sauvegarde & Restauration'),
          const SizedBox(height: 4),
          if (_lastBackup.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                const Icon(Icons.check_circle_outline, color: Colors.green, size: 15),
                const SizedBox(width: 6),
                Text('Dernière : $_lastBackup', style: const TextStyle(fontSize: 12, color: Colors.green)),
              ]),
            ),
          Wrap(spacing: 10, runSpacing: 8, children: [
            ElevatedButton.icon(
              onPressed: _busy ? null : _backupLocal,
              icon: const Icon(Icons.save_alt, size: 17),
              label: const Text('Sauvegarder'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1565C0), foregroundColor: Colors.white),
            ),
            ElevatedButton.icon(
              onPressed: _busy ? null : _backupOnline,
              icon: const Icon(Icons.email_outlined, size: 17),
              label: const Text('Envoyer par email'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _restore,
              icon: const Icon(Icons.upload_file, size: 17),
              label: const Text('Restaurer'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.orange, side: const BorderSide(color: Colors.orange)),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _viewBackups,
              icon: const Icon(Icons.folder_open, size: 17),
              label: const Text('Voir les sauvegardes'),
            ),
          ]),
          const SizedBox(height: 8),
          const Text('Sauvegardes dans Documents\\posbackup\\ (ou dossier personnalisé ci-dessous)',
              style: TextStyle(fontSize: 11, color: Colors.grey)),

          const SizedBox(height: 28), const Divider(), const SizedBox(height: 20),

          // ── Sauvegarde automatique ──
          _sectionLabel('Sauvegarde automatique'),
          const SizedBox(height: 4),
          const Text(
            'Sauvegarde locale toutes les heures pendant que l\'application est ouverte '
            '(pas de tâche planifiée système — uniquement pendant l\'utilisation).',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Activer la sauvegarde locale automatique'),
            subtitle: settings.settingValue('auto_backup_last_local', '').isNotEmpty
                ? Text('Dernière : ${settings.settingValue('auto_backup_last_local', '')}',
                    style: const TextStyle(fontSize: 11))
                : null,
            value: settings.settingValue('auto_backup_enabled', '1') == '1',
            onChanged: (v) => settings.set('auto_backup_enabled', v ? '1' : '0'),
            secondary: const Icon(Icons.history_toggle_off_rounded),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(
              controller: _backupDirCtrl,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Dossier de sauvegarde personnalisé (optionnel)',
                hintText: 'Par défaut : Documents\\posbackup',
                prefixIcon: Icon(Icons.folder_outlined),
              ),
            )),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: _pickBackupDir, child: const Text('Choisir…')),
          ]),

          const SizedBox(height: 24),

          // ── Sauvegarde cloud par email ──
          _sectionLabel('Sauvegarde cloud par email'),
          const SizedBox(height: 4),
          const Text(
            'Envoie une copie de la base par email (SMTP) une fois par jour. '
            'Utilise votre propre compte email — aucun identifiant partagé avec d\'autres installations.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Activer la sauvegarde cloud quotidienne'),
            subtitle: settings.settingValue('cloud_backup_last_sent', '').isNotEmpty
                ? Text('Dernier envoi : ${settings.settingValue('cloud_backup_last_sent', '')}',
                    style: const TextStyle(fontSize: 11))
                : null,
            value: settings.settingValue('cloud_backup_enabled', '0') == '1',
            onChanged: (v) => settings.set('cloud_backup_enabled', v ? '1' : '0'),
            secondary: const Icon(Icons.cloud_sync_rounded),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(flex: 2, child: TextField(controller: _smtpHostCtrl,
                decoration: const InputDecoration(labelText: 'Serveur SMTP', hintText: 'smtp.gmail.com'))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: _smtpPortCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Port', hintText: '587'))),
          ]),
          const SizedBox(height: 12),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Connexion SSL directe (sinon STARTTLS automatique)'),
            value: _smtpSecure,
            onChanged: (v) => setState(() => _smtpSecure = v ?? false),
          ),
          const SizedBox(height: 4),
          TextField(controller: _smtpUserCtrl,
              decoration: const InputDecoration(labelText: 'Adresse email / utilisateur SMTP', prefixIcon: Icon(Icons.alternate_email))),
          const SizedBox(height: 12),
          TextField(controller: _smtpPassCtrl, obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Mot de passe (ou mot de passe d\'application)',
                  prefixIcon: Icon(Icons.key_outlined))),
          const SizedBox(height: 12),
          TextField(controller: _smtpRecipientCtrl,
              decoration: const InputDecoration(labelText: 'Email destinataire des sauvegardes', prefixIcon: Icon(Icons.inbox_outlined))),
          const SizedBox(height: 16),
          Wrap(spacing: 10, runSpacing: 8, children: [
            FilledButton.icon(
              onPressed: _cloudSaving ? null : _saveCloudConfig,
              icon: _cloudSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded, size: 18),
              label: const Text('Enregistrer la configuration'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _backupOnline,
              icon: const Icon(Icons.send_rounded, size: 17),
              label: const Text('Tester l\'envoi maintenant'),
            ),
          ]),

          const SizedBox(height: 28), const Divider(), const SizedBox(height: 20),

          // ── Zone danger ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.shade50, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.dangerous, color: Colors.red, size: 18),
                SizedBox(width: 8),
                Text('Zone de danger', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 15)),
              ]),
              const SizedBox(height: 8),
              const Text('Efface toutes les ventes, dépenses et transactions. Les produits, clients et paramètres sont conservés.',
                  style: TextStyle(fontSize: 12, color: Colors.red)),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _busy ? null : _clearData,
                icon: const Icon(Icons.delete_forever),
                label: const Text('Effacer les données'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              ),
            ]),
          ),

          if (_busy) ...[const SizedBox(height: 16), const Center(child: CircularProgressIndicator())],
        ]),
      )),
    );
  }
}

// ─── APPARENCE ────────────────────────────────────────────────────────────────

class _AppearanceTab extends StatelessWidget {
  const _AppearanceTab();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionLabel('Thème de l\'application'),
          const SizedBox(height: 16),
          Card(child: SwitchListTile(
            title: const Text('Mode sombre'),
            subtitle: const Text('Utiliser un fond sombre'),
            value: settings.isDark,
            onChanged: (v) => settings.set('theme_mode', v ? 'dark' : 'light'),
            secondary: Icon(settings.isDark ? Icons.dark_mode : Icons.light_mode),
          )),

          const SizedBox(height: 24),
          _sectionLabel('Couleur principale'),
          const SizedBox(height: 12),
          // Theme color preview cards
          Wrap(spacing: 12, runSpacing: 10, children: [
            _colorOption(context, settings, 'Bleu (défaut)',  '1565C0', const Color(0xFF1565C0)),
            _colorOption(context, settings, 'Vert',          '2E7D32', const Color(0xFF2E7D32)),
            _colorOption(context, settings, 'Violet',        '6A1B9A', const Color(0xFF6A1B9A)),
            _colorOption(context, settings, 'Rouge',         'C62828', const Color(0xFFC62828)),
            _colorOption(context, settings, 'Orange',        'E65100', const Color(0xFFE65100)),
            _colorOption(context, settings, 'Teal',          '00695C', const Color(0xFF00695C)),
          ]),

          const SizedBox(height: 28),
          _sectionLabel('Style du menu latéral'),
          const SizedBox(height: 4),
          const Text('Couleur de fond de la barre de navigation',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 10, children: [
            _navStyleOption(context, settings, 'Thème',     'theme',     Theme.of(context).colorScheme.primary),
            _navStyleOption(context, settings, 'Bleu foncé','dark_blue', const Color(0xFF0D47A1)),
            _navStyleOption(context, settings, 'Noir',      'black',     const Color(0xFF212121)),
            _navStyleOption(context, settings, 'Ardoise',   'slate',     const Color(0xFF455A64)),
            _navStyleOption(context, settings, 'Bordeaux',  'bordeaux',  const Color(0xFF880E4F)),
            _navStyleOption(context, settings, 'Forêt',     'forest',    const Color(0xFF1B5E20)),
          ]),

          const SizedBox(height: 28),
          _sectionLabel('Couleurs des cartes du tableau de bord'),
          const SizedBox(height: 4),
          const Text('Personnalisez la couleur de chaque indicateur KPI',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 12),
          Card(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(children: [
              _kpiColorRow(context, settings, 0, "Ventes aujourd'hui", Icons.attach_money_rounded),
              const Divider(height: 24),
              _kpiColorRow(context, settings, 1, 'Commandes du jour',  Icons.receipt_long_rounded),
              const Divider(height: 24),
              _kpiColorRow(context, settings, 2, 'CA ce mois',          Icons.bar_chart_rounded),
              const Divider(height: 24),
              _kpiColorRow(context, settings, 3, 'Clients',             Icons.people_rounded),
            ]),
          )),

          const SizedBox(height: 28),
          _sectionLabel('Police des reçus'),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: settings.receiptFont,
            decoration: const InputDecoration(labelText: 'Police'),
            items: const [
              DropdownMenuItem(value: 'default',   child: Text('Par défaut (sans-serif)')),
              DropdownMenuItem(value: 'monospace', child: Text('Monospace (ticket caisse)')),
              DropdownMenuItem(value: 'serif',     child: Text('Serif')),
            ],
            onChanged: (v) => settings.set('receipt_font', v!),
          ),
        ]),
      )),
    );
  }

  // ── Nav style preview card ──────────────────────────────────────────────────
  Widget _navStyleOption(BuildContext ctx, SettingsProvider sp,
      String label, String key, Color color) {
    final selected = sp.settingValue('nav_bg_style', 'theme') == key;
    final accent   = Theme.of(ctx).colorScheme.primary;
    return GestureDetector(
      onTap: () => sp.set('nav_bg_style', key),
      child: Container(
        width: 88,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? accent : Colors.transparent, width: 2),
          color: selected ? accent.withOpacity(0.07) : Colors.grey.shade100,
        ),
        child: Column(children: [
          // Mini nav preview
          Container(
            width: 58, height: 76,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(7),
              boxShadow: [BoxShadow(color: color.withOpacity(0.35), blurRadius: 6, offset: const Offset(0, 3))],
            ),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(4, (i) => Container(
                height: 4,
                width: i == 0 ? 36 : 28,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(i == 0 ? 0.95 : 0.40),
                  borderRadius: BorderRadius.circular(2),
                ),
              )),
            ),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.bold : null),
              textAlign: TextAlign.center),
          if (selected)
            Icon(Icons.check_circle_rounded, size: 13, color: accent),
        ]),
      ),
    );
  }

  // ── KPI color row ───────────────────────────────────────────────────────────
  static const _kpiDefaults = ['1565C0', '00897B', '6A1B9A', 'E65100'];
  static const _kpiPalette  = [
    ('1565C0', Color(0xFF1565C0)),
    ('00897B', Color(0xFF00897B)),
    ('6A1B9A', Color(0xFF6A1B9A)),
    ('E65100', Color(0xFFE65100)),
    ('2E7D32', Color(0xFF2E7D32)),
    ('C62828', Color(0xFFC62828)),
    ('283593', Color(0xFF283593)),
    ('AD1457', Color(0xFFAD1457)),
    ('00838F', Color(0xFF00838F)),
    ('5D4037', Color(0xFF5D4037)),
    ('F9A825', Color(0xFFF9A825)),
    ('37474F', Color(0xFF37474F)),
  ];

  Widget _kpiColorRow(BuildContext ctx, SettingsProvider sp,
      int idx, String label, IconData icon) {
    final current = sp.settingValue('kpi_color_$idx', _kpiDefaults[idx]);
    Color curColor;
    try { curColor = Color(int.parse('FF$current', radix: 16)); }
    catch (_) { curColor = Colors.blue; }
    return Row(children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: curColor.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: curColor, size: 20),
      ),
      const SizedBox(width: 12),
      SizedBox(
        width: 140,
        child: Text(label,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            overflow: TextOverflow.ellipsis),
      ),
      const SizedBox(width: 8),
      Expanded(child: Wrap(
        spacing: 6, runSpacing: 6,
        children: _kpiPalette.map((entry) {
          final (hex, color) = entry;
          final sel = current == hex;
          return GestureDetector(
            onTap: () => sp.set('kpi_color_$idx', hex),
            child: Container(
              width: 24, height: 24,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: sel ? Colors.black54 : Colors.transparent,
                  width: 2,
                ),
                boxShadow: sel
                    ? [BoxShadow(color: color.withOpacity(0.55), blurRadius: 5)]
                    : null,
              ),
              child: sel ? const Icon(Icons.check, color: Colors.white, size: 13) : null,
            ),
          );
        }).toList(),
      )),
    ]);
  }

  Widget _colorOption(BuildContext ctx, SettingsProvider settings, String label, String hex, Color color) {
    final selected = settings.settingValue('theme_color', '1565C0') == hex;
    return GestureDetector(
      onTap: () => settings.set('theme_color', hex),
      child: Container(
        width: 90,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? color : Colors.transparent,
            width: 2,
          ),
          color: selected ? color.withOpacity(0.08) : Colors.grey.shade100,
        ),
        child: Column(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: selected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
          ),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.bold : null),
              textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

// ─── IMPRIMANTE ───────────────────────────────────────────────────────────────

class _PrinterTab extends StatefulWidget {
  const _PrinterTab();
  @override State<_PrinterTab> createState() => _PrinterTabState();
}

class _PrinterTabState extends State<_PrinterTab> {
  final _footerCtrl = TextEditingController();
  bool _testPrinting = false;

  @override
  void initState() {
    super.initState();
    _footerCtrl.text = context.read<SettingsProvider>().receiptFooter;
  }

  @override
  void dispose() { _footerCtrl.dispose(); super.dispose(); }

  Future<void> _testPrint() async {
    setState(() => _testPrinting = true);
    final settings = context.read<SettingsProvider>();
    final sym = settings.currencySymbol;

    final logo = loadBusinessLogo(settings.logoPath);
    final showTax = settings.settingValue('receipt_show_tax', '1') != '0';
    final footer  = settings.receiptFooter;

    final taxAmount =
        (showTax && settings.taxRate > 0) ? 750.0 * settings.taxRate / 100 : 0.0;
    final doc = buildLetterInvoice(
      title: 'REÇU TEST',
      dateStr: '28/05/2026  14:30',
      businessName: settings.businessName,
      businessAddress: settings.businessAddress,
      businessPhone: settings.businessPhone,
      logo: logo,
      currency: sym,
      lines: const [
        InvoiceLine(name: 'Article de test', qty: 2, unitPrice: 250, total: 500),
        InvoiceLine(name: 'Autre article', qty: 1, unitPrice: 250, total: 250),
      ],
      tax: taxAmount,
      taxRate: (showTax && settings.taxRate > 0) ? settings.taxRate : null,
      total: 750.0 + taxAmount,
      footer: footer,
    );

    await Printing.layoutPdf(onLayout: (_) => doc.save(), name: 'Reçu_Test');
    if (mounted) setState(() => _testPrinting = false);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final showTax  = settings.settingValue('receipt_show_tax', '1') != '0';
    final showLogo = settings.settingValue('receipt_show_logo', '0') == '1';
    final logoPath = settings.logoPath;
    final hasLogo  = logoPath.isNotEmpty && File(logoPath).existsSync();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Options ──
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            _sectionLabel('Options du reçu'),
            const SizedBox(height: 12),
            Card(child: Column(children: [
              SwitchListTile(
                title: const Text('Afficher le logo'),
                subtitle: Text(hasLogo ? 'Logo configuré ✓' : 'Aucun logo — onglet Boutique'),
                value: showLogo,
                onChanged: hasLogo ? (v) => settings.set('receipt_show_logo', v ? '1' : '0') : null,
                secondary: const Icon(Icons.image_outlined),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('Afficher la TVA'),
                value: showTax,
                onChanged: (v) => settings.set('receipt_show_tax', v ? '1' : '0'),
                secondary: const Icon(Icons.percent),
              ),
            ])),
            const SizedBox(height: 16),
            TextField(
              controller: _footerCtrl,
              decoration: const InputDecoration(
                labelText: 'Message pied de page',
                hintText: 'Merci de votre visite !',
                prefixIcon: Icon(Icons.text_fields),
              ),
              maxLines: 3,
              onChanged: (v) => settings.set('receipt_footer', v),
            ),

            const SizedBox(height: 28),
            _sectionLabel('Connexion imprimante'),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: settings.settingValue('printer_type', 'network'),
              decoration: const InputDecoration(labelText: 'Type de connexion'),
              items: const [
                DropdownMenuItem(value: 'network', child: Text('Réseau (TCP/IP)')),
                DropdownMenuItem(value: 'usb',     child: Text('USB / Système')),
                DropdownMenuItem(value: 'windows', child: Text('Imprimante Windows')),
              ],
              onChanged: (v) => settings.set('printer_type', v!),
            ),
            const SizedBox(height: 12),
            if (settings.settingValue('printer_type', 'network') == 'network') ...[
              TextFormField(
                initialValue: settings.settingValue('printer_ip', ''),
                decoration: const InputDecoration(
                  labelText: 'Adresse IP de l\'imprimante',
                  hintText: '192.168.1.xxx',
                  prefixIcon: Icon(Icons.router_outlined),
                ),
                onChanged: (v) => settings.set('printer_ip', v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: settings.settingValue('printer_port', '9100'),
                decoration: const InputDecoration(labelText: 'Port', hintText: '9100'),
                keyboardType: TextInputType.number,
                onChanged: (v) => settings.set('printer_port', v),
              ),
            ],

            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _testPrinting ? null : _testPrint,
              icon: _testPrinting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.print_rounded),
              label: const Text('Imprimer un reçu test'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white),
            ),
          ])),

          const SizedBox(width: 24),

          // ── Receipt preview ──
          SizedBox(width: 230, child: Column(children: [
            const Text('APERÇU REÇU', style: TextStyle(fontSize: 10, color: Colors.grey, letterSpacing: 1.2)),
            const SizedBox(height: 8),
            Card(child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                if (showLogo && hasLogo) ...[
                  ClipRRect(borderRadius: BorderRadius.circular(4),
                      child: Image.file(File(logoPath), height: 55, fit: BoxFit.contain)),
                  const SizedBox(height: 8),
                ] else if (showLogo && !hasLogo) ...[
                  Container(height: 36, color: Colors.grey.shade200,
                      child: const Center(child: Text('LOGO', style: TextStyle(color: Colors.grey, fontSize: 10)))),
                  const SizedBox(height: 8),
                ],
                Text(settings.businessName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                if (settings.businessAddress.isNotEmpty)
                  Text(settings.businessAddress,
                      style: const TextStyle(fontSize: 10), textAlign: TextAlign.center),
                const SizedBox(height: 6),
                const Divider(height: 1),
                const Text('REÇU #001', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                const Text('28/05/2026 14:30', style: TextStyle(fontSize: 10, color: Colors.grey)),
                const SizedBox(height: 6),
                const Divider(height: 1),
                const Row(children: [
                  Expanded(child: Text('Article x2', style: TextStyle(fontSize: 10))),
                  Text('G 500,00', style: TextStyle(fontSize: 10)),
                ]),
                const Row(children: [
                  Expanded(child: Text('Autre article', style: TextStyle(fontSize: 10))),
                  Text('G 250,00', style: TextStyle(fontSize: 10)),
                ]),
                const SizedBox(height: 4),
                const Divider(height: 1),
                if (showTax && settings.taxRate > 0) ...[
                  Row(children: [
                    Expanded(child: Text(
                      'TVA ${settings.taxRate % 1 == 0 ? settings.taxRate.toInt() : settings.taxRate}%',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    )),
                    Text(
                      '${settings.currencySymbol} ${(750.0 * settings.taxRate / 100).toStringAsFixed(2).replaceAll('.', ',')}',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ]),
                ],
                Row(children: [
                  const Expanded(child: Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                  Text(
                    '${settings.currencySymbol} ${(750.0 + (showTax ? 750.0 * settings.taxRate / 100 : 0)).toStringAsFixed(2).replaceAll('.', ',')}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ]),
                const SizedBox(height: 4),
                const Divider(height: 1),
                const SizedBox(height: 6),
                Text(
                  _footerCtrl.text.isEmpty ? 'Merci de votre visite !' : _footerCtrl.text,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ]),
            )),
          ])),
        ]),
      )),
    );
  }
}

// ─── LICENCE ──────────────────────────────────────────────────────────────────

class _LicenseTab extends StatefulWidget {
  const _LicenseTab();
  @override State<_LicenseTab> createState() => _LicenseTabState();
}

class _LicenseTabState extends State<_LicenseTab> {
  final _blobCtrl = TextEditingController();
  bool _activating = false;
  String? _error;
  String _hwid = '…';

  @override
  void initState() {
    super.initState();
    HardwareId.get().then((id) {
      if (mounted) setState(() => _hwid = HardwareId.format(id));
    });
  }

  @override
  void dispose() { _blobCtrl.dispose(); super.dispose(); }

  // ── Activation ─────────────────────────────────────────────────────────────
  Future<void> _activate() async {
    setState(() { _activating = true; _error = null; });
    final blob = _blobCtrl.text.trim();
    if (blob.isEmpty) {
      setState(() { _error = 'Collez le bloc de licence.'; _activating = false; });
      return;
    }
    try {
      final verification = await context.read<SettingsProvider>().activateLicense(blob);
      if (!mounted) return;
      if (verification.isValid) {
        _blobCtrl.clear();
        setState(() => _activating = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅  Licence activée avec succès'),
          backgroundColor: Colors.green,
        ));
      } else {
        setState(() {
          _activating = false;
          _error = switch (verification.result) {
            LicenseCheckResult.wrongMachine =>
              'Cette licence n\'est pas autorisée sur cette machine.\nIdentifiant : $_hwid',
            LicenseCheckResult.expired      => 'Cette licence a expiré.',
            LicenseCheckResult.badSignature => 'Licence invalide (signature incorrecte).',
            _                                => 'Format de licence invalide.',
          };
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = 'Erreur : $e'; _activating = false; });
    }
  }

  Future<void> _deactivate() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Désactiver la licence'),
      content: const Text('Êtes-vous sûr de vouloir désactiver cette licence ?\nVous pourrez la réactiver en collant à nouveau le bloc de licence.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          child: const Text('Désactiver'),
        ),
      ],
    ));
    if (ok != true || !mounted) return;
    await context.read<SettingsProvider>().deactivateLicense();
    setState(() {});
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Licence désactivée'), backgroundColor: Colors.orange));
  }

  Future<void> _copyHwid() async {
    await Clipboard.setData(ClipboardData(text: _hwid));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Identifiant copié'), duration: Duration(seconds: 1)));
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final sp       = context.watch<SettingsProvider>();
    final info     = sp.licenseInfo;
    final isActive = sp.hasValidLicense;
    final cs       = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Status card ──────────────────────────────────────────────────────
          _buildStatusCard(isActive, info),
          const SizedBox(height: 20),

          // ── Identifiant machine ──
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.secondaryContainer.withAlpha(80),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cs.outline.withAlpha(60)),
            ),
            child: Row(children: [
              Icon(Icons.devices_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Identifiant de cette machine',
                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                  Text(_hwid, style: const TextStyle(
                      fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 13)),
                ]),
              ),
              IconButton(icon: const Icon(Icons.copy_rounded, size: 18), tooltip: 'Copier', onPressed: _copyHwid),
            ]),
          ),

          const SizedBox(height: 28),

          // ── Activation / désactivation ───────────────────────────────────────
          if (!isActive) ...[
            _sectionLabel('Activer une licence'),
            const SizedBox(height: 4),
            const Text('Collez le bloc de licence signé fourni par votre vendeur.',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 16),
            TextFormField(
              controller: _blobCtrl,
              maxLines: 4,
              minLines: 3,
              decoration: InputDecoration(
                labelText: 'Bloc de licence',
                alignLabelWithHint: true,
                errorText: _error,
                prefixIcon: const Icon(Icons.vpn_key_rounded),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.content_paste_rounded),
                  tooltip: 'Coller depuis le presse-papiers',
                  onPressed: () async {
                    final data = await Clipboard.getData('text/plain');
                    if (data?.text != null && mounted) {
                      setState(() { _blobCtrl.text = data!.text!.trim(); _error = null; });
                    }
                  },
                ),
              ),
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _activating ? null : _activate,
                icon: _activating
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.verified_rounded, size: 18),
                label: const Text('Activer la licence'),
              ),
            ),
          ] else
            // Licence active : le statut est affiché plus haut. Aucune donnée
            // sensible n'est montrée à l'écran.
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _deactivate,
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('Désactiver la licence'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
              ),
            ),

          // ── About ────────────────────────────────────────────────────────────
          const SizedBox(height: 28),
          _sectionLabel('À propos du logiciel'),
          const SizedBox(height: 12),
          Card(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.point_of_sale_rounded, color: cs.primary, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('POS Flutter', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: cs.primary)),
                  const Text('Logiciel de Point de Vente', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  Text('Version $kAppVersion', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ])),
                OutlinedButton.icon(
                  onPressed: () => checkForUpdatesAndPrompt(context, silent: false),
                  icon: const Icon(Icons.system_update_alt_rounded, size: 16),
                  label: const Text('Vérifier'),
                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
              ]),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 12),
              const Text('© 2026 Tous droits réservés.',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              const Text('Ce logiciel est protégé par les lois sur la propriété intellectuelle.\nToute reproduction non autorisée est interdite.',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
            ]),
          )),
          const SizedBox(height: 24),
        ]),
      )),
    );
  }

  Widget _buildStatusCard(bool isActive, LicenseInfo? info) {
    final Color bg, fg, borderColor;
    final IconData icon;
    final String title, subtitle;

    if (!isActive || info == null) {
      bg = Colors.blue.shade50; fg = Colors.blue.shade800; borderColor = Colors.blue.shade200;
      icon = Icons.hourglass_top_rounded;
      title = 'Aucune licence active';
      subtitle = 'Activez une licence pour accéder à toutes les fonctionnalités';
    } else {
      final daysLeft = info.expiry.difference(DateTime.now()).inDays;
      if (daysLeft <= 7) {
        bg = Colors.orange.shade50; fg = Colors.orange.shade800; borderColor = Colors.orange.shade200;
        icon = Icons.warning_amber_rounded;
        title = 'Expiration imminente';
        subtitle = 'Expire le ${_fmtDate(info.expiry)} — Renouvelez votre licence';
      } else {
        bg = Colors.green.shade50; fg = Colors.green.shade800; borderColor = Colors.green.shade200;
        icon = Icons.verified_rounded;
        title = 'Licence active';
        subtitle = '${kLicenseTypeNames[info.type] ?? info.type} — Expire le ${_fmtDate(info.expiry)}';
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(children: [
        Icon(icon, color: fg, size: 38),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: fg)),
          Text(subtitle, style: TextStyle(fontSize: 12, color: fg.withOpacity(0.8))),
        ])),
        if (isActive && info != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: fg.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
            child: Text(
              kLicenseTypeNames[info.type] ?? info.type,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg),
            ),
          ),
      ]),
    );
  }
}

// ─── RÉSEAU (serveur intégré) ─────────────────────────────────────────────────

class _NetworkTab extends StatefulWidget {
  const _NetworkTab();
  @override State<_NetworkTab> createState() => _NetworkTabState();
}

class _NetworkTabState extends State<_NetworkTab> {
  final _portCtrl = TextEditingController(
      text: PosServer.instance.isRunning
          ? PosServer.instance.port.toString()
          : PosServer.defaultPort.toString());
  bool _starting = false;
  List<String> _ips = [];

  @override
  void initState() {
    super.initState();
    if (PosServer.instance.isRunning) _loadIps();
  }

  @override
  void dispose() { _portCtrl.dispose(); super.dispose(); }

  Future<void> _loadIps() async {
    final ips = await PosServer.getLocalIps();
    if (mounted) setState(() => _ips = ips);
  }

  Future<void> _toggleServer() async {
    if (PosServer.instance.isRunning) {
      await PosServer.instance.stop();
      setState(() => _ips = []);
    } else {
      final port = int.tryParse(_portCtrl.text.trim()) ?? PosServer.defaultPort;
      setState(() => _starting = true);
      try {
        await PosServer.instance.start(port: port);
        await _loadIps();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Impossible de démarrer le serveur : $e'),
            backgroundColor: Colors.red,
          ));
        }
      }
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final running = PosServer.instance.isRunning;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _sectionLabel('Serveur POS intégré'),
        const SizedBox(height: 6),
        Text(
          'Démarrez le serveur sur ce poste pour que les terminaux '
          'puissent s\'y connecter via le réseau local.',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
        const SizedBox(height: 24),

        // ── Carte de statut ──
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: running ? Colors.green.shade50 : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: running ? Colors.green.shade200 : Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(
                  running ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                  color: running ? Colors.green : Colors.grey,
                  size: 26,
                ),
                const SizedBox(width: 12),
                Text(
                  running ? 'Serveur en cours d\'exécution' : 'Serveur arrêté',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: running ? Colors.green.shade800 : Colors.grey.shade700),
                ),
              ]),

              if (running) ...[
                const SizedBox(height: 20),
                const Text('Informations de connexion pour les terminaux :',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 12),

                // Adresses IP
                ..._ips.map((ip) => _infoRow(
                  Icons.computer_rounded,
                  'Adresse IP',
                  ip,
                  Colors.blue.shade700,
                )),

                _infoRow(
                  Icons.settings_ethernet_rounded,
                  'Port',
                  PosServer.instance.port.toString(),
                  Colors.indigo.shade700,
                ),

                const SizedBox(height: 8),
                // Code d'accès (mis en avant)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00695C).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFF00695C).withOpacity(0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.lock_outline_rounded,
                        color: Color(0xFF00695C), size: 20),
                    const SizedBox(width: 10),
                    Column(crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      const Text('Code d\'accès',
                          style: TextStyle(
                              fontSize: 11, color: Color(0xFF00695C))),
                      Text(
                        PosServer.instance.token,
                        style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 6,
                            color: Color(0xFF00695C)),
                      ),
                    ]),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded,
                          color: Color(0xFF00695C)),
                      tooltip: 'Copier le code',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(
                            text: PosServer.instance.token));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Code copié !'),
                              duration: Duration(seconds: 1)),
                        );
                      },
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: const Row(children: [
                    Icon(Icons.info_outline, size: 14, color: Colors.blue),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Sur chaque terminal : Écran de licence → '
                        '"Se connecter à un serveur existant" → '
                        'entrez l\'IP, le port et le code ci-dessus.',
                        style: TextStyle(fontSize: 11, color: Colors.blue),
                      ),
                    ),
                  ]),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 24),

        // ── Configuration du port (seulement si arrêté) ──
        if (!running) ...[
          _sectionLabel('Configuration'),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _portCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Port d\'écoute',
                  hintText: '4321',
                  prefixIcon: Icon(Icons.settings_ethernet_rounded),
                  helperText: 'Par défaut : 4321',
                ),
              ),
            ),
          ]),
          const SizedBox(height: 24),
        ],

        // ── Bouton démarrer/arrêter ──
        SizedBox(
          width: double.infinity,
          child: running
              ? OutlinedButton.icon(
                  onPressed: _toggleServer,
                  icon: const Icon(Icons.stop_rounded),
                  label: const Text('Arrêter le serveur'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                )
              : FilledButton.icon(
                  onPressed: _starting ? null : _toggleServer,
                  icon: _starting
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.play_arrow_rounded),
                  label: Text(_starting
                      ? 'Démarrage…'
                      : 'Démarrer le serveur'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF00695C),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, String value, Color color) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text('$label : ',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          SelectableText(value,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold, color: color)),
        ]),
      );
}

// ─── SHARED HELPER ────────────────────────────────────────────────────────────

Widget _sectionLabel(String title) => Text(title,
    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1565C0)));
