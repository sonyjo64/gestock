import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/database/db.dart';
import '../../core/utils/helpers.dart';

class ProductFormScreen extends StatefulWidget {
  final Map<String, dynamic>? product;
  final List<Map<String, dynamic>> categories;

  const ProductFormScreen({super.key, this.product, required this.categories});

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();
  final _minStockCtrl = TextEditingController();
  final _barcodeCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  int? _categoryId;
  String _unit = 'pcs';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    if (p != null) {
      _nameCtrl.text = p['name'] as String;
      _priceCtrl.text = (p['price'] as num).toString();
      _costCtrl.text = (p['cost_price'] as num?)?.toString() ?? '0';
      _stockCtrl.text = (p['stock'] as num?)?.toString() ?? '0';
      _minStockCtrl.text = (p['min_stock'] as num?)?.toString() ?? '5';
      _barcodeCtrl.text = p['barcode'] as String? ?? '';
      _descCtrl.text = p['description'] as String? ?? '';
      _categoryId = p['category_id'] as int?;
      _unit = p['unit'] as String? ?? 'pcs';
    } else {
      _stockCtrl.text = '0';
      _minStockCtrl.text = '5';
      _costCtrl.text = '0';
    }
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _priceCtrl, _costCtrl, _stockCtrl, _minStockCtrl, _barcodeCtrl, _descCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final data = {
      if (widget.product?['id'] != null) 'id': widget.product!['id'],
      'name': _nameCtrl.text.trim(),
      'category_id': _categoryId,
      'price': double.parse(_priceCtrl.text),
      'cost_price': double.tryParse(_costCtrl.text) ?? 0,
      'stock': double.tryParse(_stockCtrl.text) ?? 0,
      'min_stock': double.tryParse(_minStockCtrl.text) ?? 5,
      'barcode': _barcodeCtrl.text.trim().isEmpty ? null : _barcodeCtrl.text.trim(),
      'unit': _unit,
      'description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
    };
    await DB.instance.upsertProduct(data);
    if (mounted) {
      showSuccess(context, widget.product == null ? 'Produit créé' : 'Produit mis à jour');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.product != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Modifier le produit' : 'Nouveau produit'),
        actions: [
          // ── Always-visible save button in AppBar ──
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded, size: 18),
              label: Text(isEdit ? 'Enregistrer' : 'Créer le produit'),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _section('Informations générales'),
                  Row(children: [
                    Expanded(flex: 2, child: _field('Nom du produit *', _nameCtrl, required: true)),
                    const SizedBox(width: 16),
                    Expanded(child: _categoryDropdown()),
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: _numField('Prix de vente *', _priceCtrl, required: true)),
                    const SizedBox(width: 16),
                    Expanded(child: _numField('Prix d\'achat', _costCtrl)),
                    const SizedBox(width: 16),
                    Expanded(child: _unitDropdown()),
                  ]),
                  const SizedBox(height: 24),
                  _section('Stock'),
                  Row(children: [
                    Expanded(child: _numField('Stock initial', _stockCtrl)),
                    const SizedBox(width: 16),
                    Expanded(child: _numField('Seuil d\'alerte', _minStockCtrl)),
                    const SizedBox(width: 16),
                    Expanded(child: _field('Code-barre', _barcodeCtrl,
                        hint: 'Scannez ou entrez manuellement',
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z\-]'))])),
                  ]),
                  const SizedBox(height: 24),
                  _section('Description'),
                  TextFormField(
                    controller: _descCtrl,
                    decoration: const InputDecoration(hintText: 'Description optionnelle'),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 32),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Annuler'),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 16),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save_rounded, size: 18),
                      label: Text(isEdit ? 'Enregistrer les modifications' : 'Créer le produit'),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1565C0))),
  );

  Widget _field(String label, TextEditingController ctrl, {bool required = false, String? hint, List<TextInputFormatter>? inputFormatters}) {
    return TextFormField(
      controller: ctrl,
      decoration: InputDecoration(labelText: label, hintText: hint),
      inputFormatters: inputFormatters,
      validator: required ? (v) => (v == null || v.isEmpty) ? 'Requis' : null : null,
    );
  }

  Widget _numField(String label, TextEditingController ctrl, {bool required = false}) {
    return TextFormField(
      controller: ctrl,
      decoration: InputDecoration(labelText: label),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
      validator: required ? (v) => (v == null || v.isEmpty) ? 'Requis' : null : null,
    );
  }

  Widget _categoryDropdown() {
    return DropdownButtonFormField<int?>(
      value: _categoryId,
      decoration: const InputDecoration(labelText: 'Catégorie'),
      items: [
        const DropdownMenuItem(value: null, child: Text('Aucune')),
        ...widget.categories.map((c) => DropdownMenuItem(value: c['id'] as int, child: Text(c['name'] as String))),
      ],
      onChanged: (v) => setState(() {
        _categoryId = v;
        // Adapter l'unité aux unités proposées pour la catégorie choisie.
        final units = _unitsForCategory();
        if (!units.contains(_unit)) _unit = units.first;
      }),
    );
  }

  /// Unités proposées selon la catégorie sélectionnée (par nom de catégorie).
  List<String> _unitsForCategory() {
    if (_categoryId == null) return kAllUnits;
    final cat = widget.categories.firstWhere(
      (c) => c['id'] == _categoryId,
      orElse: () => const <String, dynamic>{},
    );
    final name = cat['name'] as String?;
    return (name != null ? kCategoryUnits[name] : null) ?? kAllUnits;
  }

  Widget _unitDropdown() {
    // Unités de la catégorie + l'unité déjà enregistrée (pour ne pas la perdre).
    final units = List<String>.from(_unitsForCategory());
    if (!units.contains(_unit)) units.add(_unit);
    return DropdownButtonFormField<String>(
      value: _unit,
      decoration: const InputDecoration(labelText: 'Unité'),
      items: units
          .map((u) => DropdownMenuItem(value: u, child: Text(kUnitLabels[u] ?? u)))
          .toList(),
      onChanged: (v) => setState(() => _unit = v!),
    );
  }
}

// ─── Unités de mesure ────────────────────────────────────────────────────────
const Map<String, String> kUnitLabels = {
  'pcs': 'Pièce (pcs)',
  'kg': 'Kilogramme (kg)',
  'g': 'Gramme (g)',
  'l': 'Litre (l)',
  'ml': 'Millilitre (ml)',
  'btl': 'Bouteille (btl)',
  'box': 'Boîte (box)',
  'm': 'Mètre (m)',
  'm2': 'Mètre carré (m²)',
  'm3': 'Mètre cube (m³)',
  't': 'Tonne (t)',
  'sac': 'Sac',
  'barre': 'Barre',
  'palette': 'Palette',
  'brouette': 'Brouette',
  'planche': 'Planche',
  'rouleau': 'Rouleau',
  'gal': 'Gallon (gal)',
  'pot': 'Pot',
  'tole': 'Tôle',
  'feuille': 'Feuille',
  'lot': 'Lot',
};

const List<String> kAllUnits = [
  'pcs', 'kg', 'g', 'l', 'ml', 'btl', 'box', 'm', 'm2', 'm3', 't',
  'sac', 'barre', 'palette', 'brouette', 'planche', 'rouleau', 'gal',
  'pot', 'tole', 'feuille', 'lot',
];

/// Unités pertinentes par catégorie de construction (clé = nom de la catégorie).
const Map<String, List<String>> kCategoryUnits = {
  'Ciment & Béton':         ['sac', 't', 'm3'],
  'Fer & Acier':            ['barre', 'kg', 't', 'm'],
  'Briques & Blocs':        ['pcs', 'palette'],
  'Sable & Gravier':        ['m3', 't', 'brouette'],
  'Bois & Charpente':       ['planche', 'm', 'm2', 'pcs'],
  'Plomberie':              ['pcs', 'm'],
  'Électricité':            ['pcs', 'm', 'rouleau'],
  'Peinture':               ['l', 'gal', 'pot', 'kg'],
  'Carrelage & Revêtement': ['m2', 'box', 'pcs'],
  'Toiture':                ['tole', 'feuille', 'm2'],
  'Quincaillerie & Outils': ['pcs', 'box', 'lot'],
};
