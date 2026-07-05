import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/server/pos_client.dart';
import '../../core/settings/local_settings.dart';
import '../../providers/settings_provider.dart';

/// Écran de connexion à un serveur POS existant.
/// L'utilisateur entre l'adresse IP, le port et le code d'accès
/// affichés sur le poste serveur (Paramètres → Réseau).
class ServerConnectScreen extends StatefulWidget {
  const ServerConnectScreen({super.key});

  @override
  State<ServerConnectScreen> createState() => _ServerConnectScreenState();
}

class _ServerConnectScreenState extends State<ServerConnectScreen> {
  final _ipCtrl    = TextEditingController(
      text: LocalSettings.isServerMode ? LocalSettings.serverIp : '');
  final _portCtrl  = TextEditingController(
      text: LocalSettings.isServerMode
          ? LocalSettings.serverPort.toString()
          : '4321');
  final _codeCtrl  = TextEditingController(
      text: LocalSettings.isServerMode ? LocalSettings.serverToken : '');
  final _labelCtrl = TextEditingController(
      text: LocalSettings.isServerMode ? LocalSettings.serverLabel : '');

  bool    _testing    = false;
  bool    _connecting = false;
  String? _testMsg;
  bool    _testOk     = false;
  String? _error;

  @override
  void dispose() {
    _ipCtrl.dispose(); _portCtrl.dispose();
    _codeCtrl.dispose(); _labelCtrl.dispose();
    super.dispose();
  }

  int get _port => int.tryParse(_portCtrl.text.trim()) ?? 4321;

  // ── Test de connexion ──────────────────────────────────────────────────────
  Future<void> _test() async {
    final ip   = _ipCtrl.text.trim();
    final code = _codeCtrl.text.trim().toUpperCase();
    if (ip.isEmpty || code.isEmpty) {
      setState(() => _error = 'Entrez l\'adresse IP et le code d\'accès.');
      return;
    }
    setState(() {
      _testing = true; _testMsg = null; _testOk = false; _error = null;
    });
    final err = await PosClient.ping(ip, _port, code);
    if (mounted) {
      setState(() {
        _testing = false;
        _testOk  = err == null;
        _testMsg = err ?? 'Connexion réussie — serveur accessible';
      });
    }
  }

  // ── Connexion ──────────────────────────────────────────────────────────────
  Future<void> _connect() async {
    final ip   = _ipCtrl.text.trim();
    final code = _codeCtrl.text.trim().toUpperCase();
    final label = _labelCtrl.text.trim();
    if (ip.isEmpty || code.isEmpty) {
      setState(() => _error = 'Entrez l\'adresse IP et le code d\'accès.');
      return;
    }
    setState(() { _connecting = true; _error = null; });
    try {
      // Vérifier la connexion avant de persister
      final err = await PosClient.ping(ip, _port, code);
      if (err != null) {
        setState(() { _connecting = false; _error = err; });
        return;
      }
      // Persister la config + activer le client
      await LocalSettings.enableServerMode(ip, _port, code,
          label: label.isEmpty ? '$ip:$_port' : label);
      PosClient.instance.configure(ip, _port, code);
      // Recharger les settings depuis le serveur
      if (mounted) await context.read<SettingsProvider>().load();
      // PosApp se reconstruit → routing avance automatiquement
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = 'Impossible de se connecter : $e';
        });
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Row(
        children: [
          // ── Panneau gauche ──────────────────────────────────────────────────
          SizedBox(
            width: 320,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF00695C), Color(0xFF004D40)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.dns_rounded, size: 64, color: Colors.white),
                  ),
                  const SizedBox(height: 24),
                  const Text('Mode Terminal',
                      style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  const SizedBox(height: 12),
                  const Text(
                    'Ce poste se connecte au serveur\nPOS via le réseau local.',
                    style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 36),
                  _benefit(Icons.verified_rounded,  'Licence du serveur partagée'),
                  _benefit(Icons.settings_rounded,  'Aucune configuration locale'),
                  _benefit(Icons.sync_rounded,      'Données en temps réel'),
                  _benefit(Icons.computer_rounded,  'Multi-postes simultanés'),
                  const SizedBox(height: 36),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Comment trouver les infos ?',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12)),
                        SizedBox(height: 8),
                        Text(
                          '1. Sur le serveur : Paramètres → Réseau\n'
                          '2. Cliquez "Démarrer le serveur"\n'
                          '3. Notez l\'IP, le port et le code d\'accès\n'
                          '4. Entrez ces informations ici',
                          style: TextStyle(
                              color: Colors.white60, fontSize: 11, height: 1.7),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Panneau droit ───────────────────────────────────────────────────
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(48),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Retour
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                        style: IconButton.styleFrom(
                            backgroundColor: Colors.grey.shade100),
                      ),
                      const SizedBox(height: 28),

                      const Text('Connexion au serveur',
                          style: TextStyle(
                              fontSize: 24, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      const Text(
                        'Entrez les informations affichées sur le poste serveur '
                        '(Paramètres → Réseau).',
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 32),

                      // ── Adresse IP ──
                      const Text('Adresse IP du serveur *',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _ipCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                        decoration: const InputDecoration(
                          hintText: '192.168.1.10',
                          prefixIcon: Icon(Icons.computer_rounded),
                        ),
                        onChanged: (_) => setState(() {
                          _testMsg = null; _error = null;
                        }),
                      ),
                      const SizedBox(height: 16),

                      // ── Port ──
                      Row(children: [
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Port *',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13)),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _portCtrl,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: const InputDecoration(
                                  hintText: '4321',
                                  prefixIcon: Icon(Icons.settings_ethernet_rounded),
                                ),
                                onChanged: (_) => setState(() {
                                  _testMsg = null; _error = null;
                                }),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Code d\'accès *',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13)),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _codeCtrl,
                                textCapitalization:
                                    TextCapitalization.characters,
                                decoration: InputDecoration(
                                  hintText: 'AB3X7K',
                                  prefixIcon:
                                      const Icon(Icons.lock_outline_rounded),
                                  suffixIcon: IconButton(
                                    icon: const Icon(Icons.content_paste_rounded, size: 18),
                                    tooltip: 'Coller',
                                    onPressed: () async {
                                      final d = await Clipboard.getData('text/plain');
                                      if (d?.text != null && mounted) {
                                        _codeCtrl.text = d!.text!.trim().toUpperCase();
                                        setState(() { _testMsg = null; _error = null; });
                                      }
                                    },
                                  ),
                                ),
                                onChanged: (_) => setState(() {
                                  _testMsg = null; _error = null;
                                }),
                              ),
                            ],
                          ),
                        ),
                      ]),
                      const SizedBox(height: 16),

                      // ── Nom du serveur (optionnel) ──
                      TextField(
                        controller: _labelCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nom du serveur (optionnel)',
                          hintText: 'ex : Serveur principal — Boutique XY',
                          prefixIcon: Icon(Icons.label_outline_rounded),
                        ),
                      ),

                      // ── Résultat test ──
                      if (_testMsg != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: _testOk
                                ? Colors.green.shade50
                                : Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: _testOk
                                    ? Colors.green.shade200
                                    : Colors.orange.shade300),
                          ),
                          child: Row(children: [
                            Icon(
                              _testOk
                                  ? Icons.check_circle_outline
                                  : Icons.warning_amber_rounded,
                              color: _testOk ? Colors.green : Colors.orange,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_testMsg!,
                                  style: TextStyle(
                                      color: _testOk
                                          ? Colors.green.shade800
                                          : Colors.orange.shade800,
                                      fontSize: 13)),
                            ),
                          ]),
                        ),
                      ],

                      // ── Erreur ──
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(children: [
                            const Icon(Icons.error_outline,
                                color: Colors.red, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_error!,
                                  style:
                                      const TextStyle(color: Colors.red)),
                            ),
                          ]),
                        ),
                      ],

                      const SizedBox(height: 28),

                      // ── Boutons ──
                      Row(children: [
                        OutlinedButton.icon(
                          onPressed: _testing ? null : _test,
                          icon: _testing
                              ? const SizedBox(
                                  width: 14, height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.wifi_find_rounded, size: 17),
                          label: const Text('Tester'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                vertical: 14, horizontal: 18),
                            foregroundColor: const Color(0xFF00695C),
                            side: const BorderSide(color: Color(0xFF00695C)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _connecting ? null : _connect,
                            icon: _connecting
                                ? const SizedBox(
                                    width: 16, height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white))
                                : const Icon(Icons.link_rounded, size: 18),
                            label: const Text('Se connecter au serveur'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF00695C),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ]),
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

  Widget _benefit(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: Colors.white70, size: 16),
      const SizedBox(width: 10),
      Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13)),
    ]),
  );
}
