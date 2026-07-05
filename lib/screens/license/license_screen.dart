import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/database/db.dart';
import '../../core/license/hardware_id.dart';
import '../../core/license/license_service.dart';
import '../../providers/settings_provider.dart';
import '../startup/server_connect_screen.dart';

/// Écran affiché au démarrage quand aucune licence valide n'est détectée.
/// L'utilisateur colle le bloc de licence signé fourni par le vendeur
/// (généré hors-ligne avec la clé privée, jamais présente dans l'app),
/// ou restaure une sauvegarde qui peut contenir une licence déjà activée.
class LicenseScreen extends StatefulWidget {
  const LicenseScreen({super.key});

  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  final _blobCtrl = TextEditingController();
  bool _activating = false;
  bool _restoring  = false;
  String? _error;
  String? _success;
  String _hwid = '…';
  bool _hwidVisible = false;

  @override
  void initState() {
    super.initState();
    HardwareId.get().then((id) {
      if (mounted) setState(() => _hwid = HardwareId.format(id));
    });
  }

  @override
  void dispose() {
    _blobCtrl.dispose();
    super.dispose();
  }

  // ── Activation ────────────────────────────────────────────────────────────
  Future<void> _activate() async {
    setState(() { _activating = true; _error = null; _success = null; });
    final blob = _blobCtrl.text.trim();
    if (blob.isEmpty) {
      setState(() { _error = 'Collez le bloc de licence fourni par votre vendeur.'; _activating = false; });
      return;
    }
    try {
      final verification = await context.read<SettingsProvider>().activateLicense(blob);
      if (!mounted) return;
      switch (verification.result) {
        case LicenseCheckResult.valid:
          setState(() { _activating = false; _success = 'Licence activée avec succès.'; });
          break;
        case LicenseCheckResult.invalidFormat:
          setState(() { _activating = false; _error = 'Format de licence invalide — vérifiez le collage complet.'; });
          break;
        case LicenseCheckResult.badSignature:
          setState(() { _activating = false; _error = 'Licence invalide (signature incorrecte).'; });
          break;
        case LicenseCheckResult.wrongMachine:
          setState(() {
            _activating = false;
            _error = 'Cette licence n\'est pas autorisée sur cette machine.\n'
                'Identifiant de cette machine : $_hwid';
          });
          break;
        case LicenseCheckResult.expired:
          final exp = verification.info?.expiry;
          setState(() {
            _activating = false;
            _error = exp != null
                ? 'Cette licence a expiré le ${exp.day.toString().padLeft(2,'0')}/'
                  '${exp.month.toString().padLeft(2,'0')}/${exp.year}.'
                : 'Cette licence a expiré.';
          });
          break;
      }
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
        // Sinon, l'utilisateur peut coller une nouvelle licence.
        setState(() {
          _restoring = false;
          _success   = 'Base restaurée depuis ${file.name}';
        });
      }
    } catch (e) {
      if (mounted) setState(() { _restoring = false; _error = 'Erreur de restauration : $e'; });
    }
  }

  Future<void> _copyHwid() async {
    await Clipboard.setData(ClipboardData(text: _hwid));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Identifiant copié'),
        duration: Duration(seconds: 1),
      ));
    }
  }

  /// Remplace chaque caractère hexadécimal par un point, en gardant les tirets.
  String _maskHwid(String id) =>
      id.split('').map((c) => c == '-' ? '-' : '•').join();

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
                ],
              ),
            ),
          ),

          // ── Panneau droit ──────────────────────────────────────────────────
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
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
                        'Collez le bloc de licence fourni par votre vendeur.',
                        style: TextStyle(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),

                      // ── Identifiant machine ──
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.blueGrey.shade100),
                        ),
                        child: Row(children: [
                          const Icon(Icons.devices_rounded, size: 18, color: Colors.blueGrey),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Identifiant de cette machine',
                                    style: TextStyle(fontSize: 11, color: Colors.grey)),
                                Text(_hwidVisible ? _hwid : _maskHwid(_hwid),
                                    style: const TextStyle(
                                        fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 13)),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(_hwidVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                            tooltip: _hwidVisible ? 'Masquer' : 'Afficher',
                            onPressed: () => setState(() => _hwidVisible = !_hwidVisible),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            tooltip: 'Copier',
                            onPressed: _copyHwid,
                          ),
                        ]),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Communiquez cet identifiant à votre vendeur pour obtenir votre licence.',
                        style: TextStyle(color: Colors.grey, fontSize: 11),
                      ),
                      const SizedBox(height: 24),

                      // ── Champ de saisie ──
                      TextFormField(
                        controller: _blobCtrl,
                        maxLines: 4,
                        minLines: 3,
                        decoration: InputDecoration(
                          labelText: 'Bloc de licence',
                          hintText: 'Collez ici le code fourni par votre vendeur',
                          alignLabelWithHint: true,
                          errorText: _error,
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
