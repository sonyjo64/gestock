import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Générateur de codes de licence pour opérateurs SaaS.
/// Accessible depuis Paramètres → Licence → "Mode Opérateur SaaS"
/// après saisie du code maître.
class SaasGeneratorScreen extends StatefulWidget {
  const SaasGeneratorScreen({super.key});

  @override
  State<SaasGeneratorScreen> createState() => _SaasGeneratorScreenState();
}

class _SaasGeneratorScreenState extends State<SaasGeneratorScreen> {
  static const _alphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static final  _rng     = Random.secure();

  // Type sélectionné : PM, P3, P6, PY, P2, PL
  String _type   = 'PY';
  int    _qty    = 1;
  final _clientCtrl = TextEditingController();

  final List<_GenCode> _history = [];

  @override
  void dispose() { _clientCtrl.dispose(); super.dispose(); }

  // ── Génération ────────────────────────────────────────────────────────────
  String _generateOne() {
    // 2 chars de préfixe + 13 chars aléatoires + 1 checksum = 16 chars
    final buf = StringBuffer(_type); // positions 0-1
    for (int i = 0; i < 13; i++) {
      buf.write(_alphabet[_rng.nextInt(_alphabet.length)]);
    }
    final partial = buf.toString(); // 15 chars
    int sum = 0;
    for (int i = 0; i < 15; i++) sum += _alphabet.indexOf(partial[i]);
    buf.write(_alphabet[sum % 36]);
    final raw = buf.toString(); // 16 chars
    return '${raw.substring(0,4)}-${raw.substring(4,8)}'
           '-${raw.substring(8,12)}-${raw.substring(12,16)}';
  }

  void _generate() {
    final client = _clientCtrl.text.trim();
    final now    = DateTime.now();
    final codes  = List.generate(_qty, (_) => _generateOne());
    setState(() {
      for (final code in codes) {
        _history.insert(0, _GenCode(
          code:        code,
          type:        _type,
          client:      client.isEmpty ? null : client,
          generatedAt: now,
        ));
      }
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  static String typeName(String t) {
    const names = {
      'PM': 'Mensuel',    'P3': 'Trimestriel',
      'P6': 'Semestriel', 'PY': 'Annuel',
      'P2': 'Bisannuel',  'PL': 'À vie',
    };
    return names[t] ?? t;
  }

  static String typeValidity(String t) {
    const v = {
      'PM': '30 jours après activation',
      'P3': '90 jours après activation',
      'P6': '180 jours après activation',
      'PY': '365 jours après activation',
      'P2': '2 ans après activation',
      'PL': 'Illimité — aucune expiration',
    };
    return v[t] ?? '';
  }

  static Color typeColor(String t) {
    const colors = {
      'PM': Color(0xFF1565C0),
      'P3': Color(0xFF00838F),
      'P6': Color(0xFF2E7D32),
      'PY': Color(0xFF6A1B9A),
      'P2': Color(0xFF4527A0),
      'PL': Color(0xFFBF360C),
    };
    return colors[t] ?? Colors.grey;
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}  '
      '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          Icon(Icons.admin_panel_settings_rounded, size: 20),
          SizedBox(width: 10),
          Text('Générateur de licences SaaS'),
        ]),
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        actions: [
          if (_history.isNotEmpty)
            TextButton.icon(
              onPressed: () => setState(() => _history.clear()),
              icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white70, size: 18),
              label: const Text('Vider', style: TextStyle(color: Colors.white70)),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          // ── Colonne gauche : contrôles ─────────────────────────────────────
          SizedBox(
            width: 340,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A237E).withOpacity(0.03),
                border: Border(right: BorderSide(color: Colors.grey.shade200)),
              ),
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // ── Types ──
                    const Text('Type de licence',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 12),
                    ...['PM','P3','P6','PY','P2','PL'].map((t) {
                      final sel   = _type == t;
                      final color = typeColor(t);
                      return GestureDetector(
                        onTap: () => setState(() => _type = t),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color:  sel ? color.withOpacity(0.08) : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: sel ? color : Colors.grey.shade300,
                              width: sel ? 2 : 1,
                            ),
                          ),
                          child: Row(children: [
                            Icon(
                              sel ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                              color: sel ? color : Colors.grey.shade400, size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(typeName(t),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: sel ? color : null, fontSize: 13,
                                    )),
                                Text(typeValidity(t),
                                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                              ],
                            )),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(t,
                                  style: TextStyle(
                                      fontSize: 10, fontWeight: FontWeight.bold, color: color)),
                            ),
                          ]),
                        ),
                      );
                    }),

                    const SizedBox(height: 20),

                    // ── Client ──
                    TextField(
                      controller: _clientCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Client (référence)',
                        hintText: 'Nom ou numéro de client',
                        prefixIcon: Icon(Icons.business_rounded),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Quantité ──
                    Row(children: [
                      const Text('Quantité : ', style: TextStyle(fontWeight: FontWeight.w500)),
                      const SizedBox(width: 8),
                      _QtyBtn(icon: Icons.remove, onTap: () {
                        if (_qty > 1) setState(() => _qty--);
                      }),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text('$_qty',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                      _QtyBtn(icon: Icons.add, onTap: () {
                        if (_qty < 20) setState(() => _qty++);
                      }),
                    ]),

                    const SizedBox(height: 24),

                    // ── Bouton générer ──
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _generate,
                        icon: const Icon(Icons.add_card_rounded, size: 18),
                        label: Text(
                          _qty == 1 ? 'Générer un code' : 'Générer $_qty codes',
                          style: const TextStyle(fontSize: 15),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1565C0),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Info ──
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(Icons.info_outline, size: 15, color: Colors.amber),
                        SizedBox(width: 8),
                        Expanded(child: Text(
                          'La durée commence à la date d\'activation par le client, '
                          'pas à la date de génération.',
                          style: TextStyle(fontSize: 11, color: Colors.brown),
                        )),
                      ]),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Colonne droite : historique ────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // En-tête historique
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                  child: Row(children: [
                    const Text('Codes générés',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('${_history.length}',
                          style: TextStyle(fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700, fontSize: 12)),
                    ),
                    const Spacer(),
                    if (_history.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () {
                          final all = _history.map((e) => '${e.code}  [${typeName(e.type)}]'
                              '${e.client != null ? "  ${e.client}" : ""}').join('\n');
                          Clipboard.setData(ClipboardData(text: all));
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text('Tous les codes copiés dans le presse-papiers'),
                            duration: Duration(seconds: 2),
                          ));
                        },
                        icon: const Icon(Icons.copy_all_rounded, size: 16),
                        label: const Text('Copier tout'),
                        style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
                      ),
                  ]),
                ),

                // Liste ou état vide
                if (_history.isEmpty)
                  const Expanded(child: Center(child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.vpn_key_outlined, size: 64, color: Colors.black12),
                      SizedBox(height: 16),
                      Text('Aucun code généré', style: TextStyle(color: Colors.grey, fontSize: 16)),
                      SizedBox(height: 6),
                      Text('Choisissez un type et cliquez sur Générer',
                          style: TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  )))
                else
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      itemCount: _history.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (ctx, i) => _CodeTile(
                        item: _history[i],
                        onCopy: () {
                          Clipboard.setData(ClipboardData(text: _history[i].code));
                          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                            content: Text('Code copié !'),
                            duration: Duration(seconds: 1),
                            backgroundColor: Colors.green,
                          ));
                        },
                        onDelete: () => setState(() => _history.removeAt(i)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Tile d'un code généré ────────────────────────────────────────────────────

class _CodeTile extends StatelessWidget {
  final _GenCode   item;
  final VoidCallback onCopy;
  final VoidCallback onDelete;

  const _CodeTile({required this.item, required this.onCopy, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final color = _SaasGeneratorScreenState.typeColor(item.type);
    final name  = _SaasGeneratorScreenState.typeName(item.type);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // En-tête
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(item.type,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
          ),
          const SizedBox(width: 8),
          Text(name, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const Spacer(),
          Text(
            '${item.generatedAt.day.toString().padLeft(2,'0')}/'
            '${item.generatedAt.month.toString().padLeft(2,'0')}/'
            '${item.generatedAt.year}  '
            '${item.generatedAt.hour.toString().padLeft(2,'0')}:'
            '${item.generatedAt.minute.toString().padLeft(2,'0')}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.close_rounded, size: 16),
            style: IconButton.styleFrom(
              foregroundColor: Colors.grey,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ]),
        if (item.client != null) ...[
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.business_rounded, size: 13, color: Colors.grey),
            const SizedBox(width: 4),
            Text(item.client!, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ]),
        ],
        const SizedBox(height: 10),
        // Code
        Row(children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: SelectableText(
                item.code,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Tooltip(
            message: 'Copier le code',
            child: IconButton.filled(
              onPressed: onCopy,
              icon: const Icon(Icons.copy_rounded, size: 18),
              style: IconButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(12),
              ),
            ),
          ),
        ]),
      ]),
    );
  }
}

// ─── Bouton +/- quantité ──────────────────────────────────────────────────────

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _QtyBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(6),
    child: Container(
      width: 30, height: 30,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, size: 18),
    ),
  );
}

// ─── Modèle ───────────────────────────────────────────────────────────────────

class _GenCode {
  final String    code;
  final String    type;
  final String?   client;
  final DateTime  generatedAt;

  const _GenCode({
    required this.code,
    required this.type,
    this.client,
    required this.generatedAt,
  });
}
