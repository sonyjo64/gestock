import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/database/db.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PRODUCT IMPORT SCREEN
// Wizard: Bienvenue → Aperçu → Résultats
// ─────────────────────────────────────────────────────────────────────────────

class ProductImportScreen extends StatefulWidget {
  const ProductImportScreen({super.key});

  @override
  State<ProductImportScreen> createState() => _ProductImportScreenState();
}

class _ProductImportScreenState extends State<ProductImportScreen> {
  // ── wizard step ──────────────────────────────────────────────────────────────
  int _step = 0; // 0 = welcome, 1 = preview, 2 = results

  // ── data ────────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _categories = [];
  List<_ParsedRow> _rows = [];
  String? _fileName;
  String? _fileError;
  bool _importing = false;

  // ── results ──────────────────────────────────────────────────────────────────
  int _resInserted = 0;
  int _resUpdated  = 0;
  int _resErrors   = 0;

  // ── CSV columns (French headers that we accept) ──────────────────────────────
  static const _templateHeaders =
      'nom,code_barre,prix_vente,prix_achat,stock,stock_min,categorie,unite,description';

  static const _templateRows = '''
Café Moulu,CB001,2500.00,1800.00,100,10,Alimentaire,pcs,Café arabica 250g
Eau Minérale,CB002,500.00,300.00,200,20,Boissons,pcs,Bouteille 1.5L
Sucre 1kg,CB003,800.00,550.00,150,15,Alimentaire,kg,Sucre cristallisé''';

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final cats = await DB.instance.getCategories();
    if (mounted) setState(() => _categories = cats);
  }

  // ── template download ────────────────────────────────────────────────────────
  Future<void> _downloadTemplate() async {
    final content = '$_templateHeaders\n$_templateRows\n';
    // ask where to save
    final location = await getSaveLocation(
      suggestedName: 'modele_produits.csv',
      acceptedTypeGroups: [
        const XTypeGroup(label: 'CSV', extensions: ['csv']),
      ],
    );
    if (location == null) return;
    try {
      // Write UTF-8 with BOM so Excel opens it correctly
      final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode(content)];
      await File(location.path).writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Modèle enregistré : ${location.path}'),
            action: SnackBarAction(label: 'OK', onPressed: () {}),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
      }
    }
  }

  // ── file picker ──────────────────────────────────────────────────────────────
  Future<void> _pickFile() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'CSV', extensions: ['csv']),
      ],
    );
    if (file == null) return;

    setState(() { _fileError = null; _rows = []; _fileName = file.name; });

    try {
      // Try UTF-8 first; fall back to latin-1
      String content;
      try {
        content = await file.readAsString(encoding: utf8);
      } catch (_) {
        content = await file.readAsString(encoding: latin1);
      }
      // strip UTF-8 BOM if present
      if (content.startsWith('﻿')) content = content.substring(1);

      final rows = _parseCsv(content);
      if (rows.isEmpty) {
        setState(() => _fileError = 'Fichier vide ou illisible.');
        return;
      }

      // Detect header row
      final header = rows.first.map((h) => h.toLowerCase().trim()).toList();
      final colName      = _col(header, ['nom', 'name', 'produit', 'article']);
      final colBarcode   = _col(header, ['code_barre', 'barcode', 'code barre', 'ean']);
      final colPrice     = _col(header, ['prix_vente', 'prix vente', 'price', 'prix']);
      final colCost      = _col(header, ['prix_achat', 'prix achat', 'cost', 'coût']);
      final colStock     = _col(header, ['stock', 'quantite', 'quantité', 'qty']);
      final colMinStock  = _col(header, ['stock_min', 'min stock', 'min_stock', 'minimum']);
      final colCategory  = _col(header, ['categorie', 'catégorie', 'category', 'cat']);
      final colUnit      = _col(header, ['unite', 'unité', 'unit', 'uom']);
      final colDesc      = _col(header, ['description', 'desc', 'notes', 'note']);

      if (colName < 0) {
        setState(() =>
            _fileError = 'Colonne "nom" introuvable. '
                'Vérifiez que la 1ère ligne correspond aux en-têtes du modèle.');
        return;
      }
      if (colPrice < 0) {
        setState(() =>
            _fileError = 'Colonne "prix_vente" introuvable.');
        return;
      }

      final parsed = <_ParsedRow>[];
      for (int i = 1; i < rows.length; i++) {
        final r = rows[i];
        if (r.every((c) => c.trim().isEmpty)) continue; // skip blank lines

        final name    = _cell(r, colName);
        final barcode = colBarcode >= 0 ? _cell(r, colBarcode) : null;
        final priceRaw= colPrice  >= 0 ? _cell(r, colPrice)   : '';
        final costRaw = colCost   >= 0 ? _cell(r, colCost)    : '';
        final stockRaw= colStock  >= 0 ? _cell(r, colStock)   : '';
        final minRaw  = colMinStock >= 0 ? _cell(r, colMinStock) : '';
        final catName = colCategory >= 0 ? _cell(r, colCategory) : null;
        final unit    = colUnit   >= 0 ? _cell(r, colUnit)    : '';
        final desc    = colDesc   >= 0 ? _cell(r, colDesc)    : null;

        // Validate
        String? error;
        if (name.isEmpty) { error = 'Nom requis'; }

        final price = _parseNum(priceRaw);
        if (price == null && error == null) error = 'Prix invalide: "$priceRaw"';

        final cost  = _parseNum(costRaw)  ?? 0;
        final stock = _parseNum(stockRaw) ?? 0;
        final min   = _parseNum(minRaw)   ?? 5;

        // Match category
        int? catId;
        if (catName != null && catName.isNotEmpty) {
          final catNameTrimmed = catName.trim();
          final match = _categories.firstWhere(
            (c) => (c['name'] as String).toLowerCase().trim() == catNameTrimmed.toLowerCase(),
            orElse: () => {},
          );
          if (match.isNotEmpty) catId = match['id'] as int?;
        }

        parsed.add(_ParsedRow(
          rowNum: i + 1,
          name: name,
          barcode: (barcode != null && barcode.isNotEmpty) ? barcode : null,
          price: price ?? 0,
          costPrice: cost,
          stock: stock,
          minStock: min,
          categoryName: catName,
          categoryId: catId,
          unit: unit.isEmpty ? 'pcs' : unit,
          description: (desc != null && desc.isNotEmpty) ? desc : null,
          error: error,
        ));
      }

      if (parsed.isEmpty) {
        setState(() => _fileError = 'Aucune donnée trouvée après l\'en-tête.');
        return;
      }

      setState(() { _rows = parsed; _step = 1; });
    } catch (e) {
      setState(() => _fileError = 'Erreur de lecture : $e');
    }
  }

  // ── import ───────────────────────────────────────────────────────────────────
  Future<void> _doImport() async {
    setState(() => _importing = true);
    final validRows = _rows.where((r) => r.isValid).map((r) => r.toDbMap()).toList();
    final res = await DB.instance.bulkImportProducts(validRows);
    if (mounted) {
      setState(() {
        _importing  = false;
        _resInserted = res['inserted'] ?? 0;
        _resUpdated  = res['updated']  ?? 0;
        _resErrors   = res['errors']   ?? 0;
        _step = 2;
      });
    }
  }

  // ── CSV parser ───────────────────────────────────────────────────────────────
  List<List<String>> _parseCsv(String content) {
    // Detect separator (comma or semicolon)
    final firstLine = content.split('\n').first;
    final sep = firstLine.contains(';') ? ';' : ',';

    final rows = <List<String>>[];
    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    for (final line in normalized.split('\n')) {
      if (line.trim().isEmpty) continue;
      rows.add(_splitLine(line, sep));
    }
    return rows;
  }

  List<String> _splitLine(String line, String sep) {
    final fields = <String>[];
    var inQuotes = false;
    final field = StringBuffer();
    for (int i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (c == sep && !inQuotes) {
        fields.add(field.toString().trim());
        field.clear();
      } else {
        field.write(c);
      }
    }
    fields.add(field.toString().trim());
    return fields;
  }

  // ── helpers ──────────────────────────────────────────────────────────────────
  int _col(List<String> header, List<String> candidates) {
    for (final c in candidates) {
      final i = header.indexOf(c);
      if (i >= 0) return i;
    }
    return -1;
  }

  String _cell(List<String> row, int col) =>
      col < row.length ? row[col].trim() : '';

  double? _parseNum(String s) {
    if (s.isEmpty) return null;
    final cleaned = s.replaceAll(' ', '').replaceAll(',', '.').replaceAll(' ', '');
    return double.tryParse(cleaned);
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Importer des produits'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: (_step + 1) / 3,
            backgroundColor: Colors.transparent,
          ),
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: switch (_step) {
          0 => _buildWelcome(),
          1 => _buildPreview(),
          2 => _buildResults(),
          _ => const SizedBox(),
        },
      ),
    );
  }

  // ── Step 0 – Welcome ─────────────────────────────────────────────────────────
  Widget _buildWelcome() {
    return SingleChildScrollView(
      key: const ValueKey(0),
      padding: const EdgeInsets.all(32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── header
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.upload_file_rounded,
                      size: 40, color: Colors.blue.shade700),
                ),
                const SizedBox(width: 16),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Importer des produits',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const Text('Chargez un fichier CSV pour ajouter vos produits',
                      style: TextStyle(color: Colors.grey)),
                ]),
              ]),
              const SizedBox(height: 32),

              // ── instructions card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Comment ça marche ?',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      _step0Item(Icons.download, Colors.green,
                          '1. Téléchargez le modèle',
                          'Un fichier CSV prêt à remplir dans Excel ou LibreOffice'),
                      const SizedBox(height: 12),
                      _step0Item(Icons.edit_document, Colors.orange,
                          '2. Remplissez vos produits',
                          'Une ligne par produit : nom, prix, stock, catégorie…'),
                      const SizedBox(height: 12),
                      _step0Item(Icons.upload, Colors.blue,
                          '3. Importez le fichier',
                          'Vérifiez l\'aperçu puis confirmez l\'import'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ── CSV columns reference
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.table_chart_outlined, size: 20),
                        const SizedBox(width: 8),
                        Text('Colonnes du fichier CSV',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                      ]),
                      const SizedBox(height: 12),
                      _colRef('nom',         'Obligatoire', Colors.red),
                      _colRef('code_barre',  'Optionnel – identifiant unique (EAN, etc.)', Colors.grey),
                      _colRef('prix_vente',  'Obligatoire – ex: 1500.00', Colors.red),
                      _colRef('prix_achat',  'Optionnel', Colors.grey),
                      _colRef('stock',       'Optionnel – quantité initiale (défaut: 0)', Colors.grey),
                      _colRef('stock_min',   'Optionnel – seuil d\'alerte (défaut: 5)', Colors.grey),
                      _colRef('categorie',   'Optionnel – doit correspondre à une catégorie existante', Colors.grey),
                      _colRef('unite',       'Optionnel – pcs, kg, L… (défaut: pcs)', Colors.grey),
                      _colRef('description', 'Optionnel', Colors.grey),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          border: Border.all(color: Colors.amber.shade200),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(children: [
                          Icon(Icons.info_outline, size: 16, color: Colors.amber),
                          SizedBox(width: 8),
                          Expanded(child: Text(
                            'Si le code-barre existe déjà, le produit sera mis à jour.',
                            style: TextStyle(fontSize: 12),
                          )),
                        ]),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // ── action buttons
              if (_fileError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      border: Border.all(color: Colors.red.shade200),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: Colors.red),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_fileError!,
                          style: const TextStyle(color: Colors.red))),
                    ]),
                  ),
                ),
              Row(children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.download),
                  label: const Text('Télécharger le modèle CSV'),
                  onPressed: _downloadTemplate,
                ),
                const SizedBox(width: 16),
                FilledButton.icon(
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Choisir un fichier CSV'),
                  onPressed: _pickFile,
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _step0Item(IconData icon, Color color, String title, String sub) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(sub, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ])),
      ]);

  Widget _colRef(String col, String desc, Color badgeColor) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Text(col,
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(desc, style: const TextStyle(fontSize: 12))),
          if (badgeColor == Colors.red)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('requis',
                  style: TextStyle(
                      color: Colors.red,
                      fontSize: 10,
                      fontWeight: FontWeight.bold)),
            ),
        ]),
      );

  // ── Step 1 – Preview ─────────────────────────────────────────────────────────
  Widget _buildPreview() {
    final validRows   = _rows.where((r) => r.isValid).toList();
    final invalidRows = _rows.where((r) => !r.isValid).toList();
    final fmt = NumberFormat('#,##0.##', 'fr_FR');

    return Column(
      key: const ValueKey(1),
      children: [
        // ── toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: Border(
                bottom: BorderSide(
                    color: Theme.of(context).dividerColor)),
          ),
          child: Row(children: [
            Icon(Icons.table_rows_rounded,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_fileName ?? '',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(
                '${_rows.length} lignes  •  '
                '${validRows.length} valides  •  '
                '${invalidRows.length} erreurs',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ])),
            if (invalidRows.isNotEmpty)
              Chip(
                avatar: const Icon(Icons.warning, size: 14),
                label: Text('${invalidRows.length} erreur(s)'),
                backgroundColor: Colors.orange.shade100,
              ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Retour'),
              onPressed: () => setState(() { _step = 0; _rows = []; }),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              icon: _importing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white))
                  : const Icon(Icons.cloud_upload, size: 16),
              label: Text(_importing
                  ? 'Import en cours…'
                  : 'Importer ${validRows.length} produit(s)'),
              onPressed: validRows.isEmpty || _importing ? null : _doImport,
            ),
          ]),
        ),
        // ── table
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (invalidRows.isNotEmpty) ...[
                  // Show errors first
                  Text('⚠️  Lignes avec erreurs (seront ignorées)',
                      style: TextStyle(
                          color: Colors.orange.shade800,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: _previewTable(invalidRows, fmt, isError: true),
                  ),
                  const SizedBox(height: 20),
                  Text('✅  Lignes valides (${validRows.length})',
                      style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                ] else ...[
                  Text('✅  ${validRows.length} produit(s) prêt(s) à importer',
                      style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                ],
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _previewTable(validRows, fmt),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _previewTable(List<_ParsedRow> rows, NumberFormat fmt,
      {bool isError = false}) {
    return DataTable(
      columnSpacing: 16,
      headingRowColor: WidgetStateProperty.all(
        isError
            ? Colors.orange.shade50
            : Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      columns: [
        const DataColumn(label: Text('#')),
        const DataColumn(label: Text('Nom')),
        const DataColumn(label: Text('Code-barre')),
        const DataColumn(label: Text('Prix vente'), numeric: true),
        const DataColumn(label: Text('Prix achat'), numeric: true),
        const DataColumn(label: Text('Stock'),      numeric: true),
        const DataColumn(label: Text('Min.'),       numeric: true),
        const DataColumn(label: Text('Catégorie')),
        const DataColumn(label: Text('Unité')),
        if (isError) const DataColumn(label: Text('Erreur')),
      ],
      rows: rows.map((r) {
        final rowColor = isError
            ? WidgetStateProperty.all(Colors.orange.shade50)
            : null;
        final catDisplay = r.categoryName != null
            ? (r.categoryId != null
                ? r.categoryName!
                : '⚠ ${r.categoryName} (introuvable)')
            : '—';
        return DataRow(
          color: rowColor,
          cells: [
            DataCell(Text('${r.rowNum}',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12))),
            DataCell(Text(r.name,
                style: const TextStyle(fontWeight: FontWeight.w500))),
            DataCell(Text(r.barcode ?? '—',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
            DataCell(Text(fmt.format(r.price))),
            DataCell(Text(fmt.format(r.costPrice))),
            DataCell(Text(fmt.format(r.stock))),
            DataCell(Text(fmt.format(r.minStock))),
            DataCell(Text(catDisplay,
                style: r.categoryName != null && r.categoryId == null
                    ? const TextStyle(color: Colors.orange)
                    : null)),
            DataCell(Text(r.unit)),
            if (isError)
              DataCell(Text(r.error ?? '',
                  style: const TextStyle(
                      color: Colors.red, fontSize: 12))),
          ],
        );
      }).toList(),
    );
  }

  // ── Step 2 – Results ─────────────────────────────────────────────────────────
  Widget _buildResults() {
    final total = _resInserted + _resUpdated;
    return Center(
      key: const ValueKey(2),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Card(
          margin: const EdgeInsets.all(32),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  total > 0 ? Icons.check_circle_outline : Icons.error_outline,
                  size: 72,
                  color: total > 0 ? Colors.green : Colors.orange,
                ),
                const SizedBox(height: 20),
                Text(
                  total > 0 ? 'Import terminé !' : 'Aucun produit importé',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                _resultRow(Icons.add_circle, Colors.green,
                    'Nouveaux produits créés', _resInserted),
                const SizedBox(height: 8),
                _resultRow(Icons.update, Colors.blue,
                    'Produits mis à jour (code-barre existant)', _resUpdated),
                const SizedBox(height: 8),
                if (_resErrors > 0) ...[
                  _resultRow(Icons.cancel, Colors.red,
                      'Erreurs lors de l\'insertion', _resErrors),
                  const SizedBox(height: 8),
                ],
                const Divider(height: 32),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Importer un autre fichier'),
                    onPressed: () => setState(() {
                      _step = 0;
                      _rows = [];
                      _fileName = null;
                    }),
                  ),
                  const SizedBox(width: 16),
                  FilledButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('Terminer'),
                    onPressed: () => Navigator.pop(context, total > 0),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _resultRow(IconData icon, Color color, String label, int count) =>
      Row(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
        Text('$count',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: color)),
      ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// Data model for a parsed CSV row
// ─────────────────────────────────────────────────────────────────────────────
class _ParsedRow {
  final int rowNum;
  final String name;
  final String? barcode;
  final double price;
  final double costPrice;
  final double stock;
  final double minStock;
  final String? categoryName;
  final int? categoryId;
  final String unit;
  final String? description;
  final String? error;

  const _ParsedRow({
    required this.rowNum,
    required this.name,
    required this.barcode,
    required this.price,
    required this.costPrice,
    required this.stock,
    required this.minStock,
    required this.categoryName,
    required this.categoryId,
    required this.unit,
    required this.description,
    required this.error,
  });

  bool get isValid => error == null;

  Map<String, dynamic> toDbMap() => {
        'name':        name,
        if (barcode != null) 'barcode': barcode,
        'price':       price,
        'cost_price':  costPrice,
        'stock':       stock,
        'min_stock':   minStock,
        if (categoryId != null) 'category_id': categoryId,
        'unit':        unit,
        if (description != null) 'description': description,
        'is_active':   1,
      };
}
