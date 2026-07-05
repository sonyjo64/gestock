import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODEL
// ─────────────────────────────────────────────────────────────────────────────
class _PcNode {
  String name;
  String ip;
  int port;
  String role; // 'cashier' | 'server' | 'manager'

  _PcNode({required this.name, required this.ip, required this.port, required this.role});

  factory _PcNode.fromJson(Map<String, dynamic> j) => _PcNode(
        name: j['name'] as String? ?? '',
        ip: j['ip'] as String? ?? '',
        port: (j['port'] as num?)?.toInt() ?? 8765,
        role: j['role'] as String? ?? 'cashier',
      );

  Map<String, dynamic> toJson() => {'name': name, 'ip': ip, 'port': port, 'role': role};
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class MultiPcScreen extends StatefulWidget {
  const MultiPcScreen({super.key});

  @override
  State<MultiPcScreen> createState() => _MultiPcScreenState();
}

class _MultiPcScreenState extends State<MultiPcScreen> {
  String _localIp = '...';
  String _serverStatus = 'stopped'; // 'stopped' | 'running'
  final _portCtrl = TextEditingController(text: '8765');

  List<_PcNode> _nodes = [];
  final Map<int, bool> _onlineStatus = {}; // index → online bool
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _getLocalIp();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadNodes());
  }

  @override
  void dispose() {
    _portCtrl.dispose();
    super.dispose();
  }

  // ── IP ────────────────────────────────────────────────────────────────────
  Future<void> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final i in interfaces) {
        for (final addr in i.addresses) {
          if (!addr.isLoopback) {
            if (mounted) setState(() => _localIp = addr.address);
            return;
          }
        }
      }
    } catch (_) {
      if (mounted) setState(() => _localIp = 'Non disponible');
    }
  }

  // ── Persistence ───────────────────────────────────────────────────────────
  void _loadNodes() {
    final sp = context.read<SettingsProvider>();
    final raw = sp.settingValue('multipc_nodes', '[]');
    try {
      final list = jsonDecode(raw) as List;
      setState(() {
        _nodes = list.map((e) => _PcNode.fromJson(e as Map<String, dynamic>)).toList();
      });
    } catch (_) {
      setState(() => _nodes = []);
    }
  }

  Future<void> _saveNodes() async {
    final sp = context.read<SettingsProvider>();
    await sp.set('multipc_nodes', jsonEncode(_nodes.map((n) => n.toJson()).toList()));
  }

  // ── Online check ──────────────────────────────────────────────────────────
  Future<void> _refreshAll() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    for (int i = 0; i < _nodes.length; i++) {
      final online = await _checkOnline(_nodes[i].ip, _nodes[i].port);
      if (mounted) setState(() => _onlineStatus[i] = online);
    }
    if (mounted) setState(() => _refreshing = false);
  }

  Future<bool> _checkOnline(String ip, int port) async {
    try {
      final socket = await Socket.connect(ip, port,
          timeout: const Duration(seconds: 2));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── CRUD ──────────────────────────────────────────────────────────────────
  Future<void> _addNode() async {
    final node = await showDialog<_PcNode>(
      context: context,
      builder: (_) => const _NodeFormDialog(),
    );
    if (node != null) {
      setState(() => _nodes.add(node));
      await _saveNodes();
    }
  }

  Future<void> _editNode(int idx) async {
    final node = await showDialog<_PcNode>(
      context: context,
      builder: (_) => _NodeFormDialog(initial: _nodes[idx]),
    );
    if (node != null) {
      setState(() => _nodes[idx] = node);
      await _saveNodes();
    }
  }

  Future<void> _deleteNode(int idx) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce PC ?'),
        content: Text('Supprimer "${_nodes[idx].name}" de la liste ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      setState(() {
        _nodes.removeAt(idx);
        _onlineStatus.remove(idx);
      });
      await _saveNodes();
    }
  }

  // ── Role helpers ─────────────────────────────────────────────────────────
  static String _roleLabel(String role) => switch (role) {
        'server' => 'Serveur',
        'manager' => 'Manager',
        _ => 'Caisse',
      };

  static Color _roleColor(String role) => switch (role) {
        'server' => Colors.blue,
        'manager' => Colors.purple,
        _ => Colors.green,
      };

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Multi-PC — Réseau local'),
        actions: [
          FilledButton.icon(
            onPressed: _addNode,
            icon: const Icon(Icons.add),
            label: const Text('Ajouter un PC'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: _refreshing
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.refresh),
            tooltip: 'Vérifier la connectivité',
            onPressed: _refreshAll,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Server card
                _serverCard(),
                const SizedBox(height: 16),
                // ── Network info card
                _networkCard(),
                const SizedBox(height: 16),
                // ── PC list
                if (_nodes.isEmpty) _emptyState() else _pcList(),
                const SizedBox(height: 16),
                // ── Instructions
                _instructionsCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Server card ───────────────────────────────────────────────────────────
  Widget _serverCard() {
    final running = _serverStatus == 'running';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.dns_rounded, color: running ? Colors.green : const Color(0xFF1565C0)),
              const SizedBox(width: 10),
              Text(
                running ? 'Serveur actif' : 'PC Administrateur (Serveur)',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(width: 8),
              if (running)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.withOpacity(0.4)),
                  ),
                  child: const Text('EN LIGNE',
                      style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
            ]),
            const SizedBox(height: 8),
            Text(
              running
                  ? 'Serveur en écoute sur $_localIp:${_portCtrl.text}'
                  : 'Ce PC devient le serveur principal. Les autres postes s\'y connecteront.',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Row(children: [
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _portCtrl,
                  decoration: const InputDecoration(labelText: 'Port', isDense: true),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  enabled: !running,
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: running
                    ? () => setState(() => _serverStatus = 'stopped')
                    : () => setState(() => _serverStatus = 'running'),
                icon: Icon(running ? Icons.stop : Icons.play_arrow),
                label: Text(running ? 'Arrêter le serveur' : 'Démarrer le serveur'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: running ? Colors.red : const Color(0xFF1565C0),
                  foregroundColor: Colors.white,
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  // ── Network info card ─────────────────────────────────────────────────────
  Widget _networkCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Informations réseau',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.lan_rounded, size: 18, color: Colors.grey),
              const SizedBox(width: 8),
              const Text('Adresse IP locale : ', style: TextStyle(color: Colors.grey)),
              Text(_localIp, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(Icons.copy, size: 16),
                tooltip: 'Copier l\'adresse IP',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _localIp));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Adresse IP copiée'), duration: Duration(seconds: 2)),
                  );
                },
              ),
            ]),
          ],
        ),
      ),
    );
  }

  // ── PC list ───────────────────────────────────────────────────────────────
  Widget _pcList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('PCs enregistrés (${_nodes.length})',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        ),
        ...List.generate(_nodes.length, (i) => _nodeCard(i)),
      ],
    );
  }

  Widget _nodeCard(int i) {
    final node = _nodes[i];
    final online = _onlineStatus[i];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          // Icon
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: _roleColor(node.role).withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(_roleIcon(node.role), color: _roleColor(node.role), size: 22),
          ),
          const SizedBox(width: 14),
          // Name + IP
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(node.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 2),
              Text('${node.ip}:${node.port}',
                  style: const TextStyle(color: Colors.grey, fontSize: 13)),
            ]),
          ),
          // Role chip
          Chip(
            label: Text(_roleLabel(node.role),
                style: TextStyle(color: _roleColor(node.role), fontSize: 11, fontWeight: FontWeight.bold)),
            backgroundColor: _roleColor(node.role).withOpacity(0.1),
            side: BorderSide(color: _roleColor(node.role).withOpacity(0.3)),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 8),
          // Online badge
          _onlineBadge(online),
          const SizedBox(width: 8),
          // Actions
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            tooltip: 'Modifier',
            onPressed: () => _editNode(i),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
            tooltip: 'Supprimer',
            onPressed: () => _deleteNode(i),
          ),
        ]),
      ),
    );
  }

  Widget _onlineBadge(bool? online) {
    if (online == null) {
      return const Tooltip(
        message: 'Non vérifié',
        child: Icon(Icons.help_outline, size: 18, color: Colors.grey),
      );
    }
    return Tooltip(
      message: online ? 'En ligne' : 'Hors ligne',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: online ? Colors.green.withOpacity(0.12) : Colors.red.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: online ? Colors.green.withOpacity(0.4) : Colors.red.withOpacity(0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(online ? Icons.circle : Icons.circle_outlined,
              size: 8, color: online ? Colors.green : Colors.red),
          const SizedBox(width: 4),
          Text(online ? 'En ligne' : 'Hors ligne',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: online ? Colors.green : Colors.red)),
        ]),
      ),
    );
  }

  static IconData _roleIcon(String role) => switch (role) {
        'server' => Icons.dns_rounded,
        'manager' => Icons.admin_panel_settings_rounded,
        _ => Icons.point_of_sale_rounded,
      };

  // ── Empty state ───────────────────────────────────────────────────────────
  Widget _emptyState() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.devices_other_rounded, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text('Aucun PC enregistré',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 8),
            const Text(
              'Ajoutez les postes du réseau pour les surveiller\net vérifier leur connectivité.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _addNode,
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un PC'),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Instructions card ─────────────────────────────────────────────────────
  Widget _instructionsCard() {
    final cs = Theme.of(context).colorScheme;
    return Card(
      // Uses theme's secondaryContainer — adapts automatically to light & dark mode
      color: cs.secondaryContainer.withAlpha(120),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.info_outline, color: cs.secondary),
              const SizedBox(width: 8),
              Text('Instructions d\'utilisation',
                  style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurface)),
            ]),
            const SizedBox(height: 12),
            ...[
              '1. Sur le PC principal : cliquez "Démarrer le serveur"',
              '2. Sur chaque caisse secondaire : ouvrez l\'application et configurez l\'IP du serveur',
              '3. Ajoutez ici chaque PC du réseau pour surveiller son état',
              '4. Cliquez sur l\'icône Actualiser pour vérifier la connectivité',
              '5. Tous les PCs doivent être sur le même réseau Wi-Fi/LAN',
            ].map((s) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(s, style: TextStyle(fontSize: 13, color: cs.onSurface)),
                )),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NODE FORM DIALOG
// ─────────────────────────────────────────────────────────────────────────────
class _NodeFormDialog extends StatefulWidget {
  final _PcNode? initial;
  const _NodeFormDialog({this.initial});

  @override
  State<_NodeFormDialog> createState() => _NodeFormDialogState();
}

class _NodeFormDialogState extends State<_NodeFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _ipCtrl;
  late final TextEditingController _portCtrl;
  late String _role;

  @override
  void initState() {
    super.initState();
    final n = widget.initial;
    _nameCtrl = TextEditingController(text: n?.name ?? '');
    _ipCtrl   = TextEditingController(text: n?.ip ?? '');
    _portCtrl = TextEditingController(text: '${n?.port ?? 8765}');
    _role     = n?.role ?? 'cashier';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ipCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _PcNode(
        name: _nameCtrl.text.trim(),
        ip: _ipCtrl.text.trim(),
        port: int.tryParse(_portCtrl.text.trim()) ?? 8765,
        role: _role,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    return AlertDialog(
      title: Text(editing ? 'Modifier le PC' : 'Ajouter un PC'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Name
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nom du poste',
                  hintText: 'Ex: Caisse 1',
                  prefixIcon: Icon(Icons.computer),
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Nom requis' : null,
                autofocus: true,
              ),
              const SizedBox(height: 14),
              // IP
              TextFormField(
                controller: _ipCtrl,
                decoration: const InputDecoration(
                  labelText: 'Adresse IP',
                  hintText: 'Ex: 192.168.1.100',
                  prefixIcon: Icon(Icons.lan),
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Adresse IP requise' : null,
              ),
              const SizedBox(height: 14),
              // Port
              TextFormField(
                controller: _portCtrl,
                decoration: const InputDecoration(
                  labelText: 'Port',
                  hintText: '8765',
                  prefixIcon: Icon(Icons.settings_ethernet),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  final p = int.tryParse(v ?? '');
                  if (p == null || p < 1 || p > 65535) return 'Port invalide (1–65535)';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // Role selector
              const Text('Rôle', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                      value: 'cashier',
                      label: Text('Caisse'),
                      icon: Icon(Icons.point_of_sale_rounded, size: 16)),
                  ButtonSegment(
                      value: 'server',
                      label: Text('Serveur'),
                      icon: Icon(Icons.dns_rounded, size: 16)),
                  ButtonSegment(
                      value: 'manager',
                      label: Text('Manager'),
                      icon: Icon(Icons.admin_panel_settings_rounded, size: 16)),
                ],
                selected: {_role},
                onSelectionChanged: (s) => setState(() => _role = s.first),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(editing ? 'Enregistrer' : 'Ajouter'),
        ),
      ],
    );
  }
}
