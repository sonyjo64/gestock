import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../../core/database/db.dart';
import '../../core/utils/helpers.dart' hide colorToHex;

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  List<Map<String, dynamic>> _cats = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final cats = await DB.instance.getCategories();
    if (mounted) setState(() { _cats = cats; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Catégories (${_cats.length})'),
        actions: [
          ElevatedButton.icon(
            onPressed: () => _openForm(null),
            icon: const Icon(Icons.add),
            label: const Text('Nouvelle catégorie'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _cats.isEmpty
              ? const Center(child: Text('Aucune catégorie'))
              : GridView.builder(
                  padding: const EdgeInsets.all(20),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220, childAspectRatio: 1.4,
                    crossAxisSpacing: 14, mainAxisSpacing: 14,
                  ),
                  itemCount: _cats.length,
                  itemBuilder: (_, i) => _catCard(_cats[i]),
                ),
    );
  }

  Widget _catCard(Map<String, dynamic> cat) {
    final color = hexToColor(cat['color'] as String? ?? '#1565C0');
    return Card(
      elevation: 3,
      child: InkWell(
        onTap: () => _openForm(cat),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(iconFromName(cat['icon'] as String? ?? 'category'), color: color, size: 30),
              ),
              const SizedBox(height: 10),
              Text(cat['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, size: 18, color: Colors.blue),
                    onPressed: () => _openForm(cat),
                    tooltip: 'Modifier',
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                    onPressed: () => _delete(cat),
                    tooltip: 'Supprimer',
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openForm(Map<String, dynamic>? cat) async {
    await showDialog(
      context: context,
      builder: (_) => _CategoryFormDialog(cat: cat),
    );
    _load();
  }

  Future<void> _delete(Map<String, dynamic> cat) async {
    final ok = await confirmDialog(context, 'Supprimer la catégorie', 'Supprimer "${cat['name']}" ? Les produits associés ne seront pas supprimés.');
    if (ok) {
      await DB.instance.deleteCategory(cat['id'] as int);
      _load();
    }
  }
}

class _CategoryFormDialog extends StatefulWidget {
  final Map<String, dynamic>? cat;
  const _CategoryFormDialog({this.cat});

  @override
  State<_CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends State<_CategoryFormDialog> {
  final _nameCtrl = TextEditingController();
  String _icon = 'category';
  Color _color = const Color(0xFF1565C0);
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.cat;
    if (c != null) {
      _nameCtrl.text = c['name'] as String;
      _icon = c['icon'] as String? ?? 'category';
      _color = hexToColor(c['color'] as String? ?? '#1565C0');
    }
  }

  @override
  void dispose() { _nameCtrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    await DB.instance.upsertCategory({
      if (widget.cat?['id'] != null) 'id': widget.cat!['id'],
      'name': _nameCtrl.text.trim(),
      'icon': _icon,
      'color': colorToHex(_color),
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.cat == null ? 'Nouvelle catégorie' : 'Modifier la catégorie'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Nom de la catégorie *'),
              autofocus: true,
            ),
            const SizedBox(height: 20),
            const Align(alignment: Alignment.centerLeft, child: Text('Icône', style: TextStyle(color: Colors.grey))),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kCategoryIcons.map((ic) {
                final selected = _icon == ic;
                return GestureDetector(
                  onTap: () => setState(() => _icon = ic),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: selected ? _color.withOpacity(0.2) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: selected ? Border.all(color: _color, width: 2) : null,
                    ),
                    child: Icon(iconFromName(ic), color: selected ? _color : Colors.grey, size: 24),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            Row(children: [
              const Text('Couleur : ', style: TextStyle(color: Colors.grey)),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _pickColor,
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: _color, borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300)),
                ),
              ),
              const SizedBox(width: 12),
              TextButton(onPressed: _pickColor, child: const Text('Choisir une couleur')),
            ]),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.close, size: 16),
          label: const Text('Annuler'),
          onPressed: () => Navigator.pop(context),
        ),
        FilledButton.icon(
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save_rounded, size: 18),
          label: const Text('Enregistrer'),
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }

  void _pickColor() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Choisir une couleur'),
        content: SingleChildScrollView(child: BlockPicker(
          pickerColor: _color,
          onColorChanged: (c) => setState(() => _color = c),
        )),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
  }
}
