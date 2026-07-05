import 'package:flutter/material.dart';
import '../../core/services/update_service.dart';

/// Vérifie les mises à jour et affiche un dialogue si une nouvelle version
/// est disponible. [silent] = true : ne montre rien si aucune mise à jour
/// n'est trouvée (utilisé pour la vérification automatique au démarrage).
/// [silent] = false : affiche aussi un message "à jour" (bouton manuel).
Future<void> checkForUpdatesAndPrompt(BuildContext context, {bool silent = true}) async {
  final info = await UpdateService.checkForUpdate();
  if (!context.mounted) return;

  if (info == null) {
    if (!silent) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Vous utilisez déjà la dernière version.'),
      ));
    }
    return;
  }

  final proceed = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: Row(children: [
        const Icon(Icons.system_update_alt_rounded, color: Color(0xFF1565C0)),
        const SizedBox(width: 10),
        Text('Version ${info.version} disponible'),
      ]),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 300),
        child: SingleChildScrollView(
          child: Text(info.notes.isEmpty
              ? 'Une nouvelle version de Gestock est disponible.'
              : info.notes),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Plus tard')),
        FilledButton(onPressed: () => Navigator.pop(dialogCtx, true), child: const Text('Télécharger et installer')),
      ],
    ),
  );
  if (proceed != true || !context.mounted) return;

  await _downloadAndInstall(context, info);
}

Future<void> _downloadAndInstall(BuildContext context, UpdateInfo info) async {
  final progress = ValueNotifier<double>(0);

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      title: const Text('Téléchargement en cours…'),
      content: ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (_, value, __) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(value: value > 0 ? value : null),
            const SizedBox(height: 12),
            Text('${(value * 100).toStringAsFixed(0)} %'),
          ],
        ),
      ),
    ),
  );

  try {
    final path = await UpdateService.downloadInstaller(
      info.downloadUrl,
      onProgress: (p) => progress.value = p,
    );
    await UpdateService.launchInstallerAndExit(path);
    // L'app se ferme juste après (exit(0)) — rien à faire de plus ici.
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop(); // ferme le dialogue de progression
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Échec de la mise à jour : $e'),
        backgroundColor: Colors.red,
      ));
    }
  }
}
