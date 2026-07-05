import 'package:flutter/material.dart';
import '../core/database/db.dart';
import '../core/license/license_service.dart';

class SettingsProvider extends ChangeNotifier {
  Map<String, String> _settings = {};
  bool _loaded = false;
  bool _licenseValid = false;
  LicenseInfo? _licenseInfo;

  /// True once the async [load()] call has completed at least once.
  bool get isLoaded => _loaded;

  /// Default '1': if the key doesn't exist (existing installs), skip setup.
  /// New installs: the seed writes '0', so the setup wizard is shown.
  bool get isSetupComplete => settingValue('setup_completed', '1') == '1';

  String get businessName => _settings['business_name'] ?? 'Ma Boutique';
  String get currencySymbol => _settings['currency_symbol'] ?? 'G';
  String get currencyCode => _settings['currency_code'] ?? 'HTG';
  double get taxRate => double.tryParse(_settings['tax_rate'] ?? '0') ?? 0;
  String get receiptFooter => _settings['receipt_footer'] ?? '';
  bool get isDark => _settings['theme_mode'] == 'dark';
  String get logoPath => _settings['logo_path'] ?? '';
  String get businessAddress => _settings['business_address'] ?? '';
  String get businessPhone => _settings['business_phone'] ?? '';
  String get receiptFont => _settings['receipt_font'] ?? 'default';
  bool get requirePinOnIdle => _settings['require_pin_idle'] == '1';
  int get autoLockMinutes => int.tryParse(_settings['auto_lock_minutes'] ?? '5') ?? 5;
  String get screenPin => _settings['screen_pin'] ?? '';

  String settingValue(String key, String defaultValue) => _settings[key] ?? defaultValue;

  /// True si une licence signée valide (signature + machine + expiration)
  /// a été vérifiée cryptographiquement à ce démarrage. Ne se fie jamais à un
  /// simple indicateur stocké en base — la vérification est refaite à chaque
  /// [load()] avec la clé publique embarquée, pour empêcher toute
  /// falsification en modifiant directement la base de données locale.
  bool get hasValidLicense => _licenseValid;

  /// Détails de la licence actuellement vérifiée (null si invalide/absente).
  LicenseInfo? get licenseInfo => _licenseInfo;

  Future<void> load() async {
    _settings = await DB.instance.getSettings();
    await _checkLicense();
    _loaded = true;
    notifyListeners();
  }

  Future<void> _checkLicense() async {
    final blob = _settings['license_blob'] ?? '';
    if (blob.isEmpty) {
      _licenseValid = false;
      _licenseInfo = null;
      return;
    }
    final verification = await LicenseService.verify(blob);
    _licenseValid = verification.isValid;
    _licenseInfo = verification.info;
  }

  /// Active une licence à partir d'un bloc signé (collé par l'utilisateur).
  /// Retourne le résultat détaillé de la vérification pour afficher un
  /// message d'erreur précis (mauvaise machine, expirée, signature invalide…).
  Future<LicenseVerification> activateLicense(String blob) async {
    final trimmed = blob.trim();
    final verification = await LicenseService.verify(trimmed);
    if (verification.isValid) {
      await DB.instance.setSetting('license_blob', trimmed);
      _settings['license_blob'] = trimmed;
      _licenseValid = true;
      _licenseInfo = verification.info;
      notifyListeners();
    }
    return verification;
  }

  /// Désactive la licence actuelle (efface le bloc stocké).
  Future<void> deactivateLicense() async {
    await DB.instance.setSetting('license_blob', '');
    _settings['license_blob'] = '';
    _licenseValid = false;
    _licenseInfo = null;
    notifyListeners();
  }

  Future<void> set(String key, String value) async {
    await DB.instance.setSetting(key, value);
    _settings[key] = value;
    notifyListeners();
  }

  Future<void> setAll(Map<String, String> data) async {
    for (final entry in data.entries) {
      await DB.instance.setSetting(entry.key, entry.value);
      _settings[entry.key] = entry.value;
    }
    notifyListeners();
  }
}
