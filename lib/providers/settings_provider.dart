import 'package:flutter/material.dart';
import '../core/database/db.dart';

class SettingsProvider extends ChangeNotifier {
  Map<String, String> _settings = {};
  bool _loaded = false;

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

  /// True si une licence active et non expirée est enregistrée.
  bool get hasValidLicense {
    if (settingValue('license_status', 'trial') != 'active') return false;
    final type = settingValue('license_type', '');
    if (type == 'lifetime') return true;
    final expiryStr = settingValue('license_expiry', '');
    if (expiryStr.isEmpty) return true;
    try {
      return DateTime.now().isBefore(DateTime.parse(expiryStr));
    } catch (_) {
      return true;
    }
  }

  Future<void> load() async {
    _settings = await DB.instance.getSettings();
    _loaded = true;
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
