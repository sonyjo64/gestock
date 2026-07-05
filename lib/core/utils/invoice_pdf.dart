import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Charge le logo de l'entreprise (image) si un chemin valide est fourni et que
/// le fichier existe. Retourne null sinon. Partagé par reçus, rapports, proforma.
pw.MemoryImage? loadBusinessLogo(String? path) {
  if (path == null || path.trim().isEmpty) return null;
  final f = File(path.trim());
  if (!f.existsSync()) return null;
  try {
    return pw.MemoryImage(f.readAsBytesSync());
  } catch (_) {
    return null;
  }
}

/// Une ligne d'article sur une facture / un reçu.
class InvoiceLine {
  final String name;
  final double qty;
  final double unitPrice;
  final double total;
  final String? unit;

  const InvoiceLine({
    required this.name,
    required this.qty,
    required this.unitPrice,
    required this.total,
    this.unit,
  });
}

const PdfColor _accent = PdfColors.blue800;

String _money(String sym, double v) => '$sym ${v.toStringAsFixed(2)}';
String _qty(double v) =>
    v == v.truncateToDouble() ? v.toInt().toString() : v.toString();
String _pct(double v) => v % 1 == 0 ? '${v.toInt()}%' : '$v%';

/// Construit un document PDF facture/reçu **pleine page au format Letter
/// (8,5 × 11 po)**, partagé par les reçus de vente, les bons de commande et le
/// reçu de test afin qu'ils aient tous la même présentation.
pw.Document buildLetterInvoice({
  required String title,
  required String dateStr,
  required String businessName,
  String businessAddress = '',
  String businessPhone = '',
  pw.MemoryImage? logo,
  String? customerName,
  required List<InvoiceLine> lines,
  required String currency,
  double discount = 0,
  double tax = 0,
  double? taxRate,
  required double total,
  String? paymentLabel,
  double? amountPaid,
  double? change,
  double? amountDue, // reste à payer pour cette vente
  double? customerBalance, // solde courant du client (négatif = doit)
  String footer = '',
}) {
  final doc = pw.Document();

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.letter,
    margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 36),
    build: (ctx) => [
      // En-tête : entreprise (gauche) + logo (droite)
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(businessName,
                    style: pw.TextStyle(
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                        color: _accent)),
                if (businessAddress.isNotEmpty)
                  pw.Text(businessAddress,
                      style: const pw.TextStyle(
                          fontSize: 10, color: PdfColors.grey700)),
                if (businessPhone.isNotEmpty)
                  pw.Text('Tél : $businessPhone',
                      style: const pw.TextStyle(
                          fontSize: 10, color: PdfColors.grey700)),
              ],
            ),
          ),
          if (logo != null)
            pw.Image(logo, height: 64, fit: pw.BoxFit.contain),
        ],
      ),
      pw.SizedBox(height: 14),
      pw.Divider(thickness: 1.2, color: _accent),
      pw.SizedBox(height: 10),

      // Titre + métadonnées (date, client)
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title,
              style:
                  pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(dateStr,
                  style: const pw.TextStyle(
                      fontSize: 11, color: PdfColors.grey700)),
              if (customerName != null && customerName.isNotEmpty)
                pw.Text('Client : $customerName',
                    style: const pw.TextStyle(fontSize: 11)),
            ],
          ),
        ],
      ),
      pw.SizedBox(height: 14),

      // Tableau des articles (pleine largeur)
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
        columnWidths: const {
          0: pw.FlexColumnWidth(5),
          1: pw.FlexColumnWidth(2),
          2: pw.FlexColumnWidth(1.4),
          3: pw.FlexColumnWidth(2),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _accent),
            children: [
              _cell('Article', bold: true, color: PdfColors.white),
              _cell('P.U.',
                  bold: true,
                  color: PdfColors.white,
                  align: pw.TextAlign.right),
              _cell('Qté',
                  bold: true,
                  color: PdfColors.white,
                  align: pw.TextAlign.center),
              _cell('Total',
                  bold: true,
                  color: PdfColors.white,
                  align: pw.TextAlign.right),
            ],
          ),
          ...lines.map((l) => pw.TableRow(children: [
                _cell(l.name),
                _cell(_money(currency, l.unitPrice), align: pw.TextAlign.right),
                _cell(l.unit != null ? '${_qty(l.qty)} ${l.unit}' : _qty(l.qty),
                    align: pw.TextAlign.center),
                _cell(_money(currency, l.total), align: pw.TextAlign.right),
              ])),
        ],
      ),
      pw.SizedBox(height: 14),

      // Bloc des totaux (aligné à droite)
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.end,
        children: [
          pw.SizedBox(
            width: 240,
            child: pw.Column(
              children: [
                if (discount > 0)
                  _totalRow('Remise', '- ${_money(currency, discount)}',
                      color: PdfColors.red700),
                if (tax > 0)
                  _totalRow(taxRate != null ? 'TVA (${_pct(taxRate)})' : 'TVA',
                      _money(currency, tax)),
                pw.Divider(),
                _totalRow('TOTAL', _money(currency, total),
                    bold: true, fontSize: 14),
                if (paymentLabel != null && paymentLabel.isNotEmpty)
                  _totalRow('Paiement', paymentLabel),
                if (amountPaid != null && amountPaid > 0)
                  _totalRow('Reçu', _money(currency, amountPaid)),
                if (change != null && change > 0)
                  _totalRow('Monnaie rendue', _money(currency, change),
                      bold: true, color: PdfColors.green700),
                if (amountDue != null && amountDue > 0)
                  _totalRow('Reste à payer', _money(currency, amountDue),
                      bold: true, color: PdfColors.red700),
                if (customerBalance != null && customerBalance.abs() > 0.005) ...[
                  pw.Divider(),
                  _totalRow(
                    customerBalance < 0
                        ? 'Solde du client (dû)'
                        : 'Solde du client (avance)',
                    _money(currency, customerBalance.abs()),
                    bold: true,
                    color: customerBalance < 0
                        ? PdfColors.red900
                        : PdfColors.green700,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 30),

      // Pied de page
      pw.Center(
        child: pw.Text(
          footer.isNotEmpty ? footer : 'Merci de votre visite !',
          style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
        ),
      ),
    ],
  ));

  return doc;
}

pw.Widget _cell(String text,
        {bool bold = false,
        PdfColor? color,
        pw.TextAlign align = pw.TextAlign.left}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Text(text,
          textAlign: align,
          style: pw.TextStyle(
              fontSize: 11,
              fontWeight: bold ? pw.FontWeight.bold : null,
              color: color)),
    );

pw.Widget _totalRow(String label, String value,
        {bool bold = false, PdfColor? color, double fontSize = 11}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label,
              style: pw.TextStyle(
                  fontSize: fontSize,
                  fontWeight: bold ? pw.FontWeight.bold : null,
                  color: color)),
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: fontSize,
                  fontWeight: bold ? pw.FontWeight.bold : null,
                  color: color)),
        ],
      ),
    );
