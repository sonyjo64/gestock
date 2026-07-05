import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/database/db.dart';
import '../../providers/settings_provider.dart';
import '../login_screen.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _formKey = GlobalKey<FormState>();

  // ── Boutique ─────────────────────────────────────────────────────────────
  final _nameCtrl  = TextEditingController();
  final _addrCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String _currency = 'HTG';
  String _logoPath = '';

  // ── Administrateur ────────────────────────────────────────────────────────
  final _adminNameCtrl = TextEditingController();
  final _adminUserCtrl = TextEditingController();
  final _adminPwdCtrl  = TextEditingController();
  final _adminPwd2Ctrl = TextEditingController();

  bool _obscure  = true;
  bool _obscure2 = true;
  bool _saving   = false;
  String? _error;

  // Maps currency code → symbol
  static const _currencySymbols = {
    'HTG': 'G',
    'USD': '\$',
    'EUR': '€',
    'GBP': '£',
    'MAD': 'DH',
    'DZD': 'DA',
    'TND': 'DT',
    'XOF': 'CFA',
  };

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addrCtrl.dispose();
    _phoneCtrl.dispose();
    _adminNameCtrl.dispose();
    _adminUserCtrl.dispose();
    _adminPwdCtrl.dispose();
    _adminPwd2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    const tg = XTypeGroup(label: 'Images', extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif']);
    final file = await openFile(acceptedTypeGroups: [tg]);
    if (file != null && mounted) setState(() => _logoPath = file.path);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_adminPwdCtrl.text != _adminPwd2Ctrl.text) {
      setState(() => _error = 'Les mots de passe ne correspondent pas.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await DB.instance.setupBoutique(
        businessName:    _nameCtrl.text.trim(),
        businessAddress: _addrCtrl.text.trim(),
        businessPhone:   _phoneCtrl.text.trim(),
        currencyCode:    _currency,
        currencySymbol:  _currencySymbols[_currency] ?? _currency,
        logoPath:        _logoPath,
        adminName:       _adminNameCtrl.text.trim(),
        adminUsername:   _adminUserCtrl.text.trim(),
        adminPassword:   _adminPwdCtrl.text,
      );
      // Recharger les settings puis naviguer explicitement vers LoginScreen.
      // (SetupScreen peut être poussé depuis WelcomeScreen, donc on ne peut pas
      //  se fier uniquement au rebuild de PosApp pour changer de vue.)
      if (mounted) {
        await context.read<SettingsProvider>().load();
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
      }
    } catch (e) {
      if (mounted) setState(() { _error = 'Erreur inattendue : $e'; _saving = false; });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(children: [
        // ── Left panel ───────────────────────────────────────────────────
        SizedBox(width: 360, child: _buildLeftPanel()),
        // ── Right panel (form) ───────────────────────────────────────────
        Expanded(child: _buildRightPanel()),
      ]),
    );
  }

  // ── Left branding panel ──────────────────────────────────────────────────
  Widget _buildLeftPanel() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon
          Center(child: Container(
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.store_rounded, size: 72, color: Colors.white),
          )),
          const SizedBox(height: 28),
          const Center(
            child: Text('Configuration initiale',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                textAlign: TextAlign.center),
          ),
          const SizedBox(height: 10),
          const Center(
            child: Text(
              'Cette étape ne se fait qu\'une seule fois.\nVous pouvez modifier ces informations\nplus tard dans les Paramètres.',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
              textAlign: TextAlign.center,
            ),
          ),

          const SizedBox(height: 40),

          // Steps
          _step(Icons.storefront_rounded,           'Nom de la boutique',    done: true),
          _step(Icons.location_on_outlined,         'Adresse & téléphone',   done: true),
          _step(Icons.attach_money_rounded,         'Devise',                done: true),
          _step(Icons.image_outlined,               'Logo (optionnel)',       done: true),
          _step(Icons.admin_panel_settings_rounded, 'Compte administrateur', done: true),
          _step(Icons.check_circle_rounded,         'Prêt à démarrer !',     done: false),

          const Spacer(),

          // Footer
          Row(children: [
            const Icon(Icons.wifi_off_rounded, color: Colors.white38, size: 15),
            const SizedBox(width: 8),
            const Text('Fonctionne 100% hors-ligne',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
          ]),
          const SizedBox(height: 6),
          const Text('POS Flutter • v1.0.0',
              style: TextStyle(color: Colors.white24, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _step(IconData icon, String label, {required bool done}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Icon(icon, color: done ? Colors.white70 : Colors.white38, size: 18),
        const SizedBox(width: 12),
        Text(label,
            style: TextStyle(
              color: done ? Colors.white70 : Colors.white38,
              fontSize: 13,
            )),
      ]),
    );
  }

  // ── Right form panel ─────────────────────────────────────────────────────
  Widget _buildRightPanel() {
    return Container(
      color: Colors.white,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 52, vertical: 36),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Form(
              key: _formKey,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                const Text('Bienvenue 👋',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text(
                  'Remplissez les informations ci-dessous pour configurer votre boutique.',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 32),

                // ════════════════════════════════════════════════════════════
                // Section 1 : Boutique
                // ════════════════════════════════════════════════════════════
                _sectionHeader('Informations de la boutique', Icons.store_rounded),
                const SizedBox(height: 16),

                // Nom
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nom de la boutique *',
                    prefixIcon: Icon(Icons.storefront_outlined),
                  ),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Ce champ est obligatoire' : null,
                ),
                const SizedBox(height: 14),

                // Adresse
                TextFormField(
                  controller: _addrCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Adresse',
                    prefixIcon: Icon(Icons.location_on_outlined),
                    alignLabelWithHint: true,
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 14),

                // Téléphone
                TextFormField(
                  controller: _phoneCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Téléphone',
                    prefixIcon: Icon(Icons.phone_outlined),
                    hintText: '+509 ...',
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 14),

                // Devise
                DropdownButtonFormField<String>(
                  value: _currency,
                  decoration: const InputDecoration(
                    labelText: 'Devise par défaut',
                    prefixIcon: Icon(Icons.attach_money_rounded),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'HTG', child: Text('G  —  Gourde haïtienne (HTG)')),
                    DropdownMenuItem(value: 'USD', child: Text('\$  —  Dollar américain (USD)')),
                    DropdownMenuItem(value: 'EUR', child: Text('€  —  Euro (EUR)')),
                    DropdownMenuItem(value: 'GBP', child: Text('£  —  Livre sterling (GBP)')),
                    DropdownMenuItem(value: 'MAD', child: Text('DH  —  Dirham marocain (MAD)')),
                    DropdownMenuItem(value: 'DZD', child: Text('DA  —  Dinar algérien (DZD)')),
                    DropdownMenuItem(value: 'TND', child: Text('DT  —  Dinar tunisien (TND)')),
                    DropdownMenuItem(value: 'XOF', child: Text('CFA  —  Franc CFA (XOF)')),
                  ],
                  onChanged: (v) => setState(() => _currency = v!),
                ),
                const SizedBox(height: 14),

                // Logo
                _logoRow(),

                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 24),

                // ════════════════════════════════════════════════════════════
                // Section 2 : Administrateur
                // ════════════════════════════════════════════════════════════
                _sectionHeader('Compte administrateur', Icons.admin_panel_settings_rounded),
                const SizedBox(height: 4),
                const Text(
                  'Ce compte aura un accès complet à toutes les fonctionnalités.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 16),

                // Nom complet
                TextFormField(
                  controller: _adminNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nom complet de l\'administrateur *',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Ce champ est obligatoire' : null,
                ),
                const SizedBox(height: 14),

                // Username
                TextFormField(
                  controller: _adminUserCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nom d\'utilisateur *',
                    prefixIcon: Icon(Icons.alternate_email_rounded),
                    hintText: 'ex : admin, directeur...',
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(r'\s')),
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_.-]')),
                  ],
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Ce champ est obligatoire';
                    if (v.length < 3) return 'Minimum 3 caractères';
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // Mot de passe
                Row(children: [
                  Expanded(child: TextFormField(
                    controller: _adminPwdCtrl,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'Mot de passe *',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscure = !_obscure),
                        tooltip: _obscure ? 'Afficher' : 'Masquer',
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Ce champ est obligatoire';
                      if (v.length < 6) return 'Minimum 6 caractères';
                      return null;
                    },
                  )),
                  const SizedBox(width: 14),
                  Expanded(child: TextFormField(
                    controller: _adminPwd2Ctrl,
                    obscureText: _obscure2,
                    decoration: InputDecoration(
                      labelText: 'Confirmer le mot de passe *',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure2 ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscure2 = !_obscure2),
                        tooltip: _obscure2 ? 'Afficher' : 'Masquer',
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Ce champ est obligatoire';
                      if (v != _adminPwdCtrl.text) return 'Les mots de passe ne correspondent pas';
                      return null;
                    },
                  )),
                ]),

                // ── Error ────────────────────────────────────────────────
                if (_error != null) ...[
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 18),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_error!,
                          style: const TextStyle(color: Colors.red, fontSize: 13))),
                    ]),
                  ),
                ],

                const SizedBox(height: 28),

                // ── Submit ────────────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _submit,
                    icon: _saving
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.rocket_launch_rounded, size: 18),
                    label: const Text('Créer ma boutique et démarrer',
                        style: TextStyle(fontSize: 16)),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1565C0),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),

                const SizedBox(height: 12),
                const Center(
                  child: Text(
                    'Toutes les données sont stockées localement sur cet ordinateur.',
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ),
                const SizedBox(height: 24),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Widget _sectionHeader(String label, IconData icon) {
    return Row(children: [
      Icon(icon, size: 18, color: const Color(0xFF1565C0)),
      const SizedBox(width: 8),
      Text(label,
          style: const TextStyle(
            fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1565C0),
          )),
    ]);
  }

  Widget _logoRow() {
    final hasLogo = _logoPath.isNotEmpty && File(_logoPath).existsSync();
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      // Preview thumbnail
      GestureDetector(
        onTap: _pickLogo,
        child: Container(
          width: 96, height: 78,
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: hasLogo ? const Color(0xFF1565C0) : Colors.grey.shade300,
              width: hasLogo ? 2 : 1,
            ),
          ),
          child: hasLogo
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: Image.file(File(_logoPath), fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => _logoPlaceholder()))
              : _logoPlaceholder(),
        ),
      ),
      const SizedBox(width: 16),
      // Info + buttons
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Logo de la boutique',
            style: TextStyle(fontWeight: FontWeight.w500, color: Colors.grey.shade700, fontSize: 13)),
        const SizedBox(height: 2),
        Text('JPG, PNG, WEBP — Affiché sur les reçus imprimés.\nOptionnnel, modifiable plus tard.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500, height: 1.5)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(
            onPressed: _pickLogo,
            icon: const Icon(Icons.upload_file_rounded, size: 15),
            label: Text(hasLogo ? 'Changer' : 'Choisir un fichier'),
            style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                textStyle: const TextStyle(fontSize: 13)),
          ),
          if (hasLogo)
            TextButton.icon(
              onPressed: () => setState(() => _logoPath = ''),
              icon: const Icon(Icons.delete_outline, size: 15, color: Colors.red),
              label: const Text('Supprimer', style: TextStyle(color: Colors.red, fontSize: 13)),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
            ),
        ]),
      ])),
    ]);
  }

  Widget _logoPlaceholder() => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(Icons.add_photo_alternate_outlined, color: Colors.grey.shade400, size: 28),
    const SizedBox(height: 4),
    Text('Aucun logo', style: TextStyle(color: Colors.grey.shade400, fontSize: 10)),
  ]);
}
