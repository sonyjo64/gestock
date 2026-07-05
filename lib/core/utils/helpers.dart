import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

String formatCurrency(double amount, {String symbol = '€'}) {
  return '${NumberFormat('#,##0.00', 'fr_FR').format(amount)} $symbol';
}

String formatDate(String? isoDate) {
  if (isoDate == null || isoDate.isEmpty) return '';
  try {
    return DateFormat('dd/MM/yyyy').format(DateTime.parse(isoDate));
  } catch (_) {
    return isoDate;
  }
}

String formatDateTime(String? isoDate) {
  if (isoDate == null || isoDate.isEmpty) return '';
  try {
    return DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(isoDate));
  } catch (_) {
    return isoDate;
  }
}

String today() => DateTime.now().toIso8601String().substring(0, 10);
String firstDayOfMonth() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
}

Color hexToColor(String hex) {
  try {
    return Color(int.parse(hex.replaceAll('#', '0xFF')));
  } catch (_) {
    return Colors.blue;
  }
}

String colorToHex(Color color) =>
    '#${color.r.round().toRadixString(16).padLeft(2, '0')}${color.g.round().toRadixString(16).padLeft(2, '0')}${color.b.round().toRadixString(16).padLeft(2, '0')}';

IconData iconFromName(String name) {
  const map = {
    'devices': Icons.devices,
    'restaurant': Icons.restaurant,
    'checkroom': Icons.checkroom,
    'home': Icons.home,
    'local_cafe': Icons.local_cafe,
    'category': Icons.category,
    'shopping_bag': Icons.shopping_bag,
    'phone': Icons.phone_android,
    'computer': Icons.computer,
    'tv': Icons.tv,
    'receipt_long': Icons.receipt_long,
    'fastfood': Icons.fastfood,
    'local_pharmacy': Icons.local_pharmacy,
    'sports': Icons.sports,
    'toys': Icons.toys,
    'book': Icons.book,
    'palette': Icons.palette,
    'fitness_center': Icons.fitness_center,
    'directions_car': Icons.directions_car,
    // Construction
    'construction': Icons.construction,
    'foundation': Icons.foundation,
    'hardware': Icons.hardware,
    'layers': Icons.layers,
    'grain': Icons.grain,
    'carpenter': Icons.carpenter,
    'plumbing': Icons.plumbing,
    'electrical_services': Icons.electrical_services,
    'format_paint': Icons.format_paint,
    'grid_view': Icons.grid_view,
    'roofing': Icons.roofing,
  };
  return map[name] ?? Icons.category;
}

const kCategoryIcons = [
  'category', 'devices', 'restaurant', 'checkroom', 'home', 'local_cafe',
  'shopping_bag', 'phone', 'computer', 'tv', 'fastfood', 'local_pharmacy',
  'sports', 'toys', 'book', 'palette', 'fitness_center', 'directions_car',
  // Construction
  'construction', 'foundation', 'hardware', 'layers', 'grain', 'carpenter',
  'plumbing', 'electrical_services', 'format_paint', 'grid_view', 'roofing',
];

void showSuccess(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.green.shade700, behavior: SnackBarBehavior.floating),
  );
}

void showError(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700, behavior: SnackBarBehavior.floating),
  );
}

Future<bool> confirmDialog(BuildContext context, String title, String body) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          child: const Text('Confirmer'),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Payment-method key → French label (shared across all screens).
String paymentMethodLabel(String m) {
  switch (m) {
    case 'cash':     return 'Espèces';
    case 'card':     return 'Carte';
    case 'credit':   return 'Crédit';
    case 'transfer': return 'Virement';
    default:         return m;
  }
}
