import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Écran d'aperçu PDF plein écran avant impression (zoom, défilement des
/// pages), avec un bouton d'impression (fourni par [PdfPreview]) et un
/// bouton d'enregistrement direct vers un fichier au choix de l'utilisateur.
class PdfPreviewScreen extends StatelessWidget {
  final String title;
  final pw.Document document;
  final String suggestedFileName;

  const PdfPreviewScreen({
    super.key,
    required this.title,
    required this.document,
    required this.suggestedFileName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: PdfPreview(
        build: (format) => document.save(),
        pdfFileName: suggestedFileName,
        canChangePageFormat: false,
        canChangeOrientation: false,
        actions: [
          PdfPreviewAction(
            icon: const Icon(Icons.save_alt_rounded),
            onPressed: (ctx, build, format) async {
              final bytes = await build(format);
              final location = await getSaveLocation(
                suggestedName: suggestedFileName,
                acceptedTypeGroups: const [
                  XTypeGroup(label: 'PDF', extensions: ['pdf']),
                ],
              );
              if (location == null) return;
              await File(location.path).writeAsBytes(bytes);
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('Enregistré : ${location.path}')),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
