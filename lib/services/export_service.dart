import 'dart:io';
import 'package:excel/excel.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ExportService {
  static final _dateFmt = DateFormat('yyyy-MM-dd');

  /// Propose un chemin de sauvegarde, écrit le fichier, retourne true si réussi.
  static Future<bool> exportExcel({
    required BuildContext context,
    required String sheetName,
    required List<String> headers,
    required List<List<dynamic>> rows,
    String? suggestedName,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel[sheetName];

    // En-tête en gras
    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#1565C0'),
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
    );
    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = headerStyle;
    }

    // Données
    for (var r = 0; r < rows.length; r++) {
      for (var c = 0; c < rows[r].length; c++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1));
        final v = rows[r][c];
        if (v is num)    cell.value = DoubleCellValue(v.toDouble());
        else if (v is DateTime) cell.value = TextCellValue(_dateFmt.format(v));
        else             cell.value = TextCellValue(v?.toString() ?? '');
      }
    }

    final bytes = excel.encode();
    if (bytes == null) return false;

    final name = suggestedName ?? '${sheetName}_${_dateFmt.format(DateTime.now())}.xlsx';
    final location = await getSaveLocation(suggestedName: name,
        acceptedTypeGroups: [const XTypeGroup(label: 'Excel', extensions: ['xlsx'])]);
    if (location == null) return false;

    final file = File(location.path);
    await file.writeAsBytes(bytes);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Exporté : ${file.path}'),
        backgroundColor: Colors.green,
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ));
    }
    return true;
  }

  /// Export CSV simple
  static Future<bool> exportCsv({
    required BuildContext context,
    required List<String> headers,
    required List<List<dynamic>> rows,
    String? suggestedName,
  }) async {
    final sb = StringBuffer();
    sb.writeln(headers.map(_csvEscape).join(','));
    for (final row in rows) {
      sb.writeln(row.map((v) => _csvEscape(v?.toString() ?? '')).join(','));
    }

    final name = suggestedName ?? 'export_${_dateFmt.format(DateTime.now())}.csv';
    final location = await getSaveLocation(suggestedName: name,
        acceptedTypeGroups: [const XTypeGroup(label: 'CSV', extensions: ['csv'])]);
    if (location == null) return false;

    await File(location.path).writeAsString(sb.toString());

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Exporté : ${location.path}'),
        backgroundColor: Colors.green,
      ));
    }
    return true;
  }

  static String _csvEscape(String v) {
    if (v.contains(',') || v.contains('"') || v.contains('\n')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }

  // ─── Helpers spécialisés ──────────────────────────────────────────────────

  static Future<void> exportSales(BuildContext context,
      List<Map<String, dynamic>> sales, String symbol) async {
    final headers = ['#', 'Date', 'Client', 'Employé', 'Paiement',
        'Sous-total', 'Remise', 'Taxe', 'Total', 'Statut'];
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    final rows = sales.map((s) {
      DateTime? dt;
      try { dt = DateTime.parse(s['created_at'] as String); } catch (_) {}
      return [
        s['id'],
        dt != null ? fmt.format(dt) : s['created_at'],
        s['customer_name'] ?? 'Comptant',
        s['employee_name'] ?? '',
        s['payment_method'] ?? '',
        (s['subtotal'] as num?)?.toStringAsFixed(2) ?? '0.00',
        (s['discount']  as num?)?.toStringAsFixed(2) ?? '0.00',
        (s['tax']       as num?)?.toStringAsFixed(2) ?? '0.00',
        (s['total']     as num?)?.toStringAsFixed(2) ?? '0.00',
        s['status'] ?? '',
      ];
    }).toList();
    await exportExcel(context: context, sheetName: 'Ventes',
        headers: headers, rows: rows,
        suggestedName: 'ventes_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.xlsx');
  }

  static Future<void> exportStock(BuildContext context,
      List<Map<String, dynamic>> products) async {
    final headers = ['#', 'Produit', 'Catégorie', 'Code-barre',
        'Prix vente', 'Prix coût', 'Stock', 'Stock min', 'Unité', 'Statut'];
    final rows = products.map((p) {
      final stock    = (p['stock']    as num?)?.toDouble() ?? 0;
      final minStock = (p['min_stock'] as num?)?.toDouble() ?? 0;
      final status   = stock <= 0 ? 'Rupture' : stock <= minStock ? 'Bas' : 'OK';
      return [
        p['id'], p['name'], p['category_name'] ?? '', p['barcode'] ?? '',
        (p['price']      as num?)?.toStringAsFixed(2) ?? '0.00',
        (p['cost_price'] as num?)?.toStringAsFixed(2) ?? '0.00',
        stock.toStringAsFixed(2), minStock.toStringAsFixed(2),
        p['unit'] ?? 'pcs', status,
      ];
    }).toList();
    await exportExcel(context: context, sheetName: 'Stock',
        headers: headers, rows: rows,
        suggestedName: 'stock_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.xlsx');
  }

  static Future<void> exportExpenses(BuildContext context,
      List<Map<String, dynamic>> expenses) async {
    final headers = ['#', 'Date', 'Catégorie', 'Montant', 'Paiement', 'Description'];
    final fmt = DateFormat('dd/MM/yyyy');
    final rows = expenses.map((e) {
      final date = e['date'] as String? ?? '';
      DateTime? dt;
      try { dt = date.length >= 10 ? DateTime.parse(date) : null; } catch (_) {}
      return [
        e['id'],
        dt != null ? fmt.format(dt) : date,
        e['head_name'] ?? 'Divers',
        (e['amount'] as num?)?.toStringAsFixed(2) ?? '0.00',
        e['payment_method'] ?? '',
        e['description'] ?? '',
      ];
    }).toList();
    await exportExcel(context: context, sheetName: 'Dépenses',
        headers: headers, rows: rows,
        suggestedName: 'depenses_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.xlsx');
  }

  static Future<void> exportSuppliers(BuildContext context,
      List<Map<String, dynamic>> suppliers, String symbol) async {
    final headers = ['#', 'Nom', 'Téléphone', 'Email', 'Adresse', 'Solde', 'Notes'];
    final rows = suppliers.map((s) => [
      s['id'], s['name'], s['phone'] ?? '', s['email'] ?? '',
      s['address'] ?? '',
      (s['balance'] as num?)?.toStringAsFixed(2) ?? '0.00',
      s['notes'] ?? '',
    ]).toList();
    await exportExcel(context: context, sheetName: 'Fournisseurs',
        headers: headers, rows: rows,
        suggestedName: 'fournisseurs_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.xlsx');
  }
}
