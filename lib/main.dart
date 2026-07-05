import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'core/server/pos_client.dart';
import 'core/services/auto_backup_scheduler.dart';
import 'core/services/crash_report_service.dart';
import 'core/settings/local_settings.dart';
import 'providers/auth_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/pos_provider.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'screens/setup/setup_screen.dart';
import 'screens/license/license_screen.dart';
import 'screens/startup/welcome_screen.dart';
import 'core/theme/app_theme.dart';

void main() {
  // Capture toute erreur non gérée (async, callbacks…) échappant aux
  // gestionnaires Flutter ci-dessous, et l'envoie par email si la
  // sauvegarde cloud est configurée (voir CrashReportService).
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();

    // Erreurs du framework Flutter (build/layout/paint).
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      CrashReportService.instance.report(
        details.exception,
        details.stack ?? StackTrace.current,
        context: details.context?.toString(),
      );
    };

    // Lire pos_config.json AVANT d'ouvrir la base
    await LocalSettings.initialize();
    // Si ce poste est configuré en mode terminal, activer le client HTTP
    if (LocalSettings.isServerMode && LocalSettings.serverIp.isNotEmpty) {
      await PosClient.instance.configure(
        LocalSettings.serverIp,
        LocalSettings.serverPort,
        LocalSettings.serverToken,
      );
    }
    AutoBackupScheduler.instance.start();
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => SettingsProvider()..load()),
          ChangeNotifierProvider(create: (_) => PosProvider()),
        ],
        child: const PosApp(),
      ),
    );
  }, (error, stack) {
    CrashReportService.instance.report(error, stack);
  });
}

/// Shown for the few milliseconds while settings are loading from SQLite.
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();
  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: CircularProgressIndicator()),
  );
}

class PosApp extends StatelessWidget {
  const PosApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final auth = context.watch<AuthProvider>();

    // Parse the user-selected theme color (stored as hex string without #, e.g. "1565C0")
    final colorHex = settings.settingValue('theme_color', '1565C0');
    Color themeColor;
    try {
      themeColor = Color(int.parse('FF$colorHex', radix: 16));
    } catch (_) {
      themeColor = const Color(0xFF1565C0);
    }

    // ── Routing à 4 niveaux ──────────────────────────────────────────────────
    // 1. Splash       : settings encore en cours de chargement
    // 2. LicenseScreen: aucune licence valide → obligation d'activer
    // 3. WelcomeScreen: licence ok, mais setup pas fait → choisir mode install
    // 4. LoginScreen / MainShell : système opérationnel
    final Widget home;
    if (!settings.isLoaded) {
      home = const _SplashScreen();
    } else if (!settings.hasValidLicense) {
      home = const LicenseScreen();
    } else if (!settings.isSetupComplete) {
      home = const WelcomeScreen();
    } else if (auth.isLoggedIn) {
      home = const MainShell();
    } else {
      home = const LoginScreen();
    }

    return MaterialApp(
      title: 'POS System',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightWith(themeColor),
      darkTheme: AppTheme.darkWith(themeColor),
      themeMode: settings.isDark ? ThemeMode.dark : ThemeMode.light,
      home: home,
    );
  }
}
