import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/database/db.dart';
import '../../providers/settings_provider.dart';
import '../setup/setup_screen.dart';
import 'server_connect_screen.dart';

/// Écran de sélection du mode d'installation.
/// Affiché après la validation de la licence, lors d'une première installation
/// (setup_completed = '0').
///
/// Deux options :
///  1. Nouvelle boutique → SetupScreen (wizard de configuration)
///  2. Reprendre une installation existante → restauration d'une sauvegarde DB
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _restoring = false;
  String? _error;

  // ── Option 2 : restaurer depuis un fichier .db ─────────────────────────────
  Future<void> _restoreAndLaunch() async {
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
          'Fichier sélectionné :\n${file.name}\n\n'
          'Toutes les données actuelles seront remplacées par celles de ce fichier.\n'
          'Continuer ?',
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

    setState(() { _restoring = true; _error = null; });
    try {
      await DB.instance.closeAndReset();
      await File(file.path).copy(DB.instance.dbPath);
      if (mounted) {
        await context.read<SettingsProvider>().load();
        // SettingsProvider.notifyListeners() → PosApp se reconstruit.
        // Si la sauvegarde a setup_completed='1', le routing passe à LoginScreen.
        // Si la sauvegarde n'a pas de licence valide, le routing passe à LicenseScreen.
      }
    } catch (e) {
      if (mounted) setState(() { _restoring = false; _error = 'Erreur de restauration : $e'; });
    }
  }

  // ── Option 1 : nouvelle boutique → SetupScreen ────────────────────────────
  void _startSetup() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SetupScreen()),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Row(
        children: [
          // ── Panneau gauche (branding) ──────────────────────────────────────
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
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
                  const SizedBox(height: 28),
                  const Text('Bienvenue !',
                      style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 12),
                  const Text(
                    'Choisissez comment vous souhaitez\ndémarrer votre système POS.',
                    style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.6),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 52),
                  _stepBadge('1', 'Choisissez le mode d\'installation'),
                  const SizedBox(height: 16),
                  _stepBadge('2', 'Configurez ou importez vos données'),
                  const SizedBox(height: 16),
                  _stepBadge('3', 'Commencez à vendre immédiatement'),
                  const SizedBox(height: 48),
                  const Text('POS Flutter  •  v1.0.0',
                      style: TextStyle(color: Colors.white24, fontSize: 11)),
                ],
              ),
            ),
          ),

          // ── Panneau droit (choix) ──────────────────────────────────────────
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Mode d\'installation',
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text(
                        'Sélectionnez comment configurer le logiciel sur ce poste.',
                        style: TextStyle(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 36),

                      // ── Option 1 : Nouvelle boutique ──
                      _ModeCard(
                        icon: Icons.store_rounded,
                        color: const Color(0xFF1565C0),
                        title: 'Nouvelle boutique',
                        subtitle:
                            'Configurez le logiciel pour une nouvelle boutique.\n'
                            'Vous définirez le nom, la devise et le compte administrateur.',
                        buttonLabel: 'Démarrer la configuration',
                        onTap: _startSetup,
                      ),

                      const SizedBox(height: 20),

                      // ── Option 2 : Reprendre depuis sauvegarde ──
                      _ModeCard(
                        icon: Icons.restore_rounded,
                        color: Colors.orange.shade700,
                        title: 'Reprendre une installation existante',
                        subtitle:
                            'Restaurez les données d\'un autre poste ou d\'un serveur.\n'
                            'Produits, clients, ventes et paramètres seront récupérés.',
                        buttonLabel: _restoring ? 'Restauration en cours…' : 'Sélectionner une sauvegarde',
                        loading: _restoring,
                        onTap: _restoring ? null : _restoreAndLaunch,
                      ),

                      const SizedBox(height: 20),

                      // ── Option 3 : Se connecter à un serveur ──
                      _ModeCard(
                        icon: Icons.dns_rounded,
                        color: const Color(0xFF00695C),
                        title: 'Se connecter à un serveur',
                        subtitle:
                            'Ce poste utilise la base du serveur principal.\n'
                            'Licence et configuration sont héritées du serveur.',
                        buttonLabel: 'Configurer la connexion',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const ServerConnectScreen()),
                        ),
                      ),

                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(children: [
                            const Icon(Icons.error_outline, color: Colors.red, size: 18),
                            const SizedBox(width: 10),
                            Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red))),
                          ]),
                        ),
                      ],
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

  Widget _stepBadge(String step, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(step, style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
        ),
      ),
      const SizedBox(width: 12),
      Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13)),
    ],
  );
}

// ─── Carte d'option ───────────────────────────────────────────────────────────

class _ModeCard extends StatelessWidget {
  final IconData    icon;
  final Color       color;
  final String      title;
  final String      subtitle;
  final String      buttonLabel;
  final bool        loading;
  final VoidCallback? onTap;

  const _ModeCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    this.loading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ]),
          const SizedBox(height: 12),
          Text(subtitle,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13, height: 1.55)),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onTap,
              icon: loading
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(icon, size: 16),
              label: Text(buttonLabel),
              style: FilledButton.styleFrom(
                backgroundColor: color,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
