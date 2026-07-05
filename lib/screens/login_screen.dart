import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/database/db.dart';
import '../core/server/pos_client.dart';
import '../core/settings/local_settings.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure   = true;
  bool _loading   = false;
  bool _showPin   = false;
  bool _restoring = false;
  String _pin = '';
  String? _error;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    final ok = await context.read<AuthProvider>().login(_userCtrl.text.trim(), _passCtrl.text);
    if (!ok && mounted) {
      setState(() { _loading = false; _error = 'Nom d\'utilisateur ou mot de passe incorrect.'; });
    }
  }

  Future<void> _pinLogin() async {
    if (_pin.length < 4) return;
    setState(() { _loading = true; _error = null; });
    final ok = await context.read<AuthProvider>().loginPin(_pin);
    if (!ok && mounted) {
      setState(() { _loading = false; _error = 'PIN incorrect.'; _pin = ''; });
    }
  }

  void _addPin(String d) {
    if (_pin.length >= 6) return;
    setState(() { _pin += d; _error = null; });
    if (_pin.length >= 4) _pinLogin();
  }

  void _backPin() {
    if (_pin.isEmpty) return;
    setState(() { _pin = _pin.substring(0, _pin.length - 1); });
  }

  // ── Restauration depuis la page de connexion ────────────────────────────────
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
          'Fichier : ${file.name}\n\n'
          'Toutes les données actuelles seront remplacées.\nContinuer ?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
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
      if (mounted) await context.read<SettingsProvider>().load();
      // SettingsProvider notifie → PosApp rebuild → routing correct
    } catch (e) {
      if (mounted) setState(() { _restoring = false; _error = 'Erreur de restauration : $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return Scaffold(
      backgroundColor: Colors.white,
      body: Row(
        children: [
          // Panneau gauche — branding
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
                  _buildLogo(settings),
                  const SizedBox(height: 24),
                  Text(
                    settings.businessName,
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Système de Point de Vente',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 48),
                  _featureRow(Icons.wifi_off_rounded, 'Fonctionne hors-ligne'),
                  const SizedBox(height: 12),
                  _featureRow(Icons.security_rounded, 'Données sécurisées'),
                  const SizedBox(height: 12),
                  _featureRow(Icons.bar_chart_rounded, 'Rapports complets'),
                ],
              ),
            ),
          ),
          // Panneau droit — formulaire
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (LocalSettings.isServerMode) ...[
                        _buildServerBanner(),
                        const SizedBox(height: 16),
                      ],
                      _showPin ? _buildPinPad() : _buildForm(),
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

  // ── Bannière mode serveur ───────────────────────────────────────────────────
  Widget _buildServerBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF00695C).withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF00695C).withOpacity(0.3)),
      ),
      child: Row(children: [
        const Icon(Icons.dns_rounded, color: Color(0xFF00695C), size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Serveur : ${LocalSettings.serverLabel}',
            style: const TextStyle(
                color: Color(0xFF00695C),
                fontSize: 12,
                fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        TextButton(
          onPressed: _disconnectServer,
          style: TextButton.styleFrom(
            foregroundColor: Colors.red,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Déconnecter', style: TextStyle(fontSize: 11)),
        ),
      ]),
    );
  }

  Future<void> _disconnectServer() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Déconnecter le serveur'),
        content: const Text(
          'Ce poste reviendra en mode local.\n'
          'La configuration serveur sera supprimée.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Déconnecter'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    PosClient.instance.disconnect();
    await LocalSettings.disableServerMode();
    if (mounted) await context.read<SettingsProvider>().load();
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Connexion', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('Entrez vos identifiants pour accéder au système', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 32),
          TextFormField(
            controller: _userCtrl,
            decoration: const InputDecoration(
              labelText: 'Nom d\'utilisateur',
              prefixIcon: Icon(Icons.person_outline),
            ),
            textInputAction: TextInputAction.next,
            validator: (v) => (v == null || v.isEmpty) ? 'Requis' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passCtrl,
            decoration: InputDecoration(
              labelText: 'Mot de passe',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            obscureText: _obscure,
            onFieldSubmitted: (_) => _login(),
            validator: (v) => (v == null || v.isEmpty) ? 'Requis' : null,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red))),
              ]),
            ),
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loading ? null : _login,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: const Color(0xFF1565C0),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: _loading
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Se connecter', style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => setState(() { _showPin = true; _error = null; }),
            icon: const Icon(Icons.dialpad),
            label: const Text('Connexion par PIN'),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
          const SizedBox(height: 12),
          // ── Restauration d'urgence ──
          Center(
            child: TextButton.icon(
              onPressed: _restoring ? null : _restoreBackup,
              icon: _restoring
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.restore_rounded, size: 16),
              label: Text(
                _restoring ? 'Restauration…' : 'Restaurer une sauvegarde',
                style: const TextStyle(fontSize: 13),
              ),
              style: TextButton.styleFrom(foregroundColor: Colors.orange.shade700),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildPinPad() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Connexion PIN', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Entrez votre code PIN', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(4, (i) => Container(
            width: 16, height: 16,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < _pin.length ? const Color(0xFF1565C0) : Colors.grey.shade300,
            ),
          )),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 28),
        _pinGrid(),
        const SizedBox(height: 20),
        TextButton(
          onPressed: () => setState(() { _showPin = false; _pin = ''; _error = null; }),
          child: const Text('Retour à la connexion standard'),
        ),
        if (_loading) const Padding(
          padding: EdgeInsets.only(top: 12),
          child: CircularProgressIndicator(),
        ),
      ],
    );
  }

  Widget _pinGrid() {
    final keys = ['1','2','3','4','5','6','7','8','9','','0','⌫'];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.5,
      physics: const NeverScrollableScrollPhysics(),
      children: keys.map((k) {
        if (k.isEmpty) return const SizedBox();
        if (k == '⌫') {
          return OutlinedButton(
            onPressed: _backPin,
            style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Icon(Icons.backspace_outlined),
          );
        }
        return ElevatedButton(
          onPressed: _loading ? null : () => _addPin(k),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.grey.shade100,
            foregroundColor: Colors.black87,
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Text(k, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500)),
        );
      }).toList(),
    );
  }

  Widget _buildLogo(SettingsProvider settings) {
    final path = settings.logoPath;
    final hasLogo = path.isNotEmpty && File(path).existsSync();
    if (hasLogo) {
      return Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(File(path), fit: BoxFit.contain),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.store_rounded, size: 72, color: Colors.white),
    );
  }

  Widget _featureRow(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white70, size: 18),
        const SizedBox(width: 10),
        Text(text, style: const TextStyle(color: Colors.white70)),
      ],
    );
  }
}
