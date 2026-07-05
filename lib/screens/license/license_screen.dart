import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/database/db.dart';
import '../../providers/settings_provider.dart';
import '../admin/saas_generator_screen.dart';
import '../startup/server_connect_screen.dart';

/// Écran affiché au démarrage quand aucune licence valide n'est détectée.
/// L'utilisateur doit entrer une clé pour accéder au logiciel,
/// ou restaurer une sauvegarde (qui peut inclure une licence déjà activée).
class LicenseScreen extends StatefulWidget {
  const LicenseScreen({super.key});

  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  static const _alphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';

  final _codeCtrl = TextEditingController();
  bool _activating = false;
  bool _restoring  = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  // ── Validation (checksum identique à settings_screen) ─────────────────────
  bool _validate(String raw16) {
    if (raw16.length != 16) return false;
    for (final c in raw16.split('')) {
      if (!_alphabet.contains(c)) return false;
    }
    int sum = 0;
    for (int i = 0; i < 15; i++) sum += _alphabet.indexOf(raw16[i]);
    return raw16[15] == _alphabet[sum % 36];
  }

  String? _licenseType(String raw) {
    if (raw.length < 2) return null;
    switch (raw.substring(0, 2)) {
      case 'PM': return 'monthly';
      case 'P3': return '3months';
      case 'P6': return '6months';
      case 'PY': return 'yearly';
      case 'P2': return '2years';
      case 'PL': return 'lifetime';
      default: return null;
    }
  }

  // ── Activation ────────────────────────────────────────────────────────────
  Future<void> _activate() async {
    setState(() { _activating = true; _error = null; _success = null; });
    try {
      final raw = _codeCtrl.text.replaceAll('-', '').toUpperCase();
      if (raw.length != 16) {
        setState(() {
          _error = 'Le code doit contenir 16 caractères (actuellement: ${raw.length}).';
          _activating = false;
        });
        return;
      }
      if (!_validate(raw)) {
        setState(() {
          _error = 'Code invalide — vérifiez chaque caractère (zéro "0" ≠ lettre "O").';
          _activating = false;
        });
        return;
      }
      final type = _licenseType(raw);
      if (type == null) {
        setState(() {
          _error = 'Préfixe inconnu. Utilisez un code commençant par PM, P3, P6, PY, P2 ou PL.';
          _activating = false;
        });
        return;
      }

      final now = DateTime.now();
      final daysMap = {
        'monthly': 30, '3months': 90, '6months': 180,
        'yearly': 365, '2years': 730,
      };
      final days = daysMap[type];
      final expiry = days != null ? now.add(Duration(days: days)) : null;

      await context.read<SettingsProvider>().setAll({
        'license_code':         raw,
        'license_type':         type,
        'license_status':       'active',
        'license_activated_at': now.toIso8601String(),
        'license_expiry':       expiry?.toIso8601String() ?? '',
      });
      // SettingsProvider.notifyListeners() → PosApp rebuilds → routing avance
      if (mounted) setState(() => _activating = false);
    } catch (e) {
      if (mounted) setState(() { _error = 'Erreur : $e'; _activating = false; });
    }
  }

  // ── Restauration depuis fichier ────────────────────────────────────────────
  Future<void> _restoreBackup() async {
    const tg = XTypeGroup(label: 'Base de données', extensions: ['db']);
    final file = await openFile(acceptedTypeGroups: [tg]);
    if (file == null || !mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.restore_rounded, color: Colors.orange),
          SizedBox(width: 8),
          Text('Confirmer la restauration'),
        ]),
        content: Text(
          'Fichier : ${file.name}\n\nCela remplacera toutes les données actuelles. Continuer ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Restaurer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() { _restoring = true; _error = null; _success = null; });
    try {
      await DB.instance.closeAndReset();
      await File(file.path).copy(DB.instance.dbPath);
      if (mounted) {
        await context.read<SettingsProvider>().load();
        // Si la sauvegarde contient une licence valide, le routing avance automatiquement.
        // Sinon, l'utilisateur peut entrer une nouvelle clé.
        setState(() {
          _restoring = false;
          _success   = 'Base restaurée depuis ${file.name}';
        });
      }
    } catch (e) {
      if (mounted) setState(() { _restoring = false; _error = 'Erreur de restauration : $e'; });
    }
  }

  // ── Accès générateur SaaS depuis l'écran de licence ─────────────────────
  Future<void> _openSaasGenerator(BuildContext context) async {
    final ctrl = TextEditingController();
    bool obscure = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx2, ss) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.admin_panel_settings_rounded, color: Color(0xFF1565C0)),
          SizedBox(width: 8),
          Text('Accès opérateur'),
        ]),
        content: TextField(
          controller: ctrl,
          obscureText: obscure,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Code maître',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
              onPressed: () => ss(() => obscure = !obscure),
            ),
          ),
          onSubmitted: (_) => Navigator.pop(ctx, ctrl.text == 'PSGEN2026'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text == 'PSGEN2026'),
            child: const Text('Accéder'),
          ),
        ],
      )),
    );
    ctrl.dispose();
    if (!context.mounted) return;
    if (ok == true) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SaasGeneratorScreen()));
    } else if (ok == false) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Code maître incorrect'),
        backgroundColor: Colors.red,
      ));
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Row(
        children: [
          // ── Panneau gauche ─────────────────────────────────────────────────
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.point_of_sale_rounded, size: 72, color: Colors.white),
                  ),
                  const SizedBox(height: 24),
                  const Text('POS Flutter',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 8),
                  const Text('Logiciel de Point de Vente',
                      style: TextStyle(color: Colors.white70, fontSize: 16)),
                  const SizedBox(height: 52),
                  _featureRow(Icons.verified_rounded,      'Accès sécurisé par licence'),
                  const SizedBox(height: 14),
                  _featureRow(Icons.wifi_off_rounded,      'Fonctionne hors-ligne'),
                  const SizedBox(height: 14),
                  _featureRow(Icons.security_rounded,      'Données 100 % locales'),
                  const SizedBox(height: 14),
                  _featureRow(Icons.support_agent_rounded, 'Support technique inclus'),
                  const SizedBox(height: 48),
                  const Text('POS Flutter  •  v1.0.0',
                      style: TextStyle(color: Colors.white24, fontSize: 11)),
                  const SizedBox(height: 16),
                  // Accès discret au générateur SaaS (opérateurs uniquement)
                  TextButton(
                    onPressed: () => _openSaasGenerator(context),
                    child: const Text('⚙ Opérateur', style: TextStyle(color: Colors.white12, fontSize: 10)),
                  ),
                ],
              ),
            ),
          ),

          // ── Panneau droit ──────────────────────────────────────────────────
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // En-tête
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1565C0).withOpacity(0.07),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.vpn_key_rounded, size: 44, color: Color(0xFF1565C0)),
                      ),
                      const SizedBox(height: 20),
                      const Text('Activation du logiciel',
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 6),
                      const Text(
                        'Entrez votre clé de licence pour accéder au système.',
                        style: TextStyle(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),

                      // ── Champ de saisie ──
                      TextFormField(
                        controller: _codeCtrl,
                        inputFormatters: [_LicenseFormatter()],
                        decoration: InputDecoration(
                          labelText: 'Clé de licence',
                          hintText: 'XXXX-XXXX-XXXX-XXXX',
                          prefixIcon: const Icon(Icons.key_rounded),
                          errorText: _error,
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.content_paste_rounded),
                            tooltip: 'Coller depuis le presse-papiers',
                            onPressed: () async {
                              final data = await Clipboard.getData('text/plain');
                              if (data?.text != null && mounted) {
                                final raw = data!.text!.toUpperCase()
                                    .replaceAll(RegExp(r'[^0-9A-Z]'), '');
                                final lim = raw.length > 16 ? raw.substring(0, 16) : raw;
                                final buf = StringBuffer();
                                for (int i = 0; i < lim.length; i++) {
                                  if (i == 4 || i == 8 || i == 12) buf.write('-');
                                  buf.write(lim[i]);
                                }
                                setState(() { _codeCtrl.text = buf.toString(); _error = null; });
                              }
                            },
                          ),
                        ),
                        style: const TextStyle(letterSpacing: 3, fontWeight: FontWeight.w600, fontSize: 15),
                        onFieldSubmitted: (_) => _activate(),
                      ),

                      // Message de succès
                      if (_success != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Row(children: [
                            const Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_success!, style: const TextStyle(color: Colors.green, fontSize: 13))),
                          ]),
                        ),
                      ],

                      const SizedBox(height: 24),

                      // ── Bouton Activer ──
                      FilledButton.icon(
                        onPressed: _activating ? null : _activate,
                        icon: _activating
                            ? const SizedBox(width: 18, height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.verified_rounded, size: 18),
                        label: const Text('Activer la licence', style: TextStyle(fontSize: 16)),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1565C0),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),

                      // ── Séparateur ──
                      const SizedBox(height: 28),
                      Row(children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Text('ou', style: TextStyle(color: Colors.grey.shade500)),
                        ),
                        const Expanded(child: Divider()),
                      ]),
                      const SizedBox(height: 24),

                      // ── Bouton Restaurer ──
                      OutlinedButton.icon(
                        onPressed: _restoring ? null : _restoreBackup,
                        icon: _restoring
                            ? const SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.restore_rounded),
                        label: const Text('Restaurer depuis une sauvegarde'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          foregroundColor: Colors.orange.shade700,
                          side: BorderSide(color: Colors.orange.shade400),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // ── Connexion serveur (licence partagée) ──
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const ServerConnectScreen()),
                        ),
                        icon: const Icon(Icons.dns_rounded),
                        label: const Text('Se connecter à un serveur existant'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          foregroundColor: const Color(0xFF00695C),
                          side: const BorderSide(color: Color(0xFF00695C)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),

                      const SizedBox(height: 28),
                      Text(
                        'Pour obtenir votre clé de licence, contactez votre fournisseur.\n'
                        'La licence est obligatoire pour accéder au logiciel.',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 11, height: 1.5),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _featureRow(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: Colors.white70, size: 18),
      const SizedBox(width: 10),
      Text(text, style: const TextStyle(color: Colors.white70)),
    ],
  );
}

/// Formate automatiquement la saisie en XXXX-XXXX-XXXX-XXXX.
class _LicenseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue value) {
    var raw = value.text.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');
    if (raw.length > 16) raw = raw.substring(0, 16);
    final buf = StringBuffer();
    for (int i = 0; i < raw.length; i++) {
      if (i == 4 || i == 8 || i == 12) buf.write('-');
      buf.write(raw[i]);
    }
    final text = buf.toString();
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}
