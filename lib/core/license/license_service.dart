import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'hardware_id.dart';
import 'license_public_key.dart';

/// Durées de licence disponibles (en jours), à partir de la date d'émission
/// signée dans la licence (pas la date d'activation locale — évite toute
/// manipulation de l'horloge du poste pour prolonger un essai).
const Map<String, int> kLicenseDurationDays = {
  'PM': 30,
  'P3': 90,
  'P6': 180,
  'PY': 365,
};

const Map<String, String> kLicenseTypeNames = {
  'PM': 'Mensuel',
  'P3': 'Trimestriel',
  'P6': 'Semestriel',
  'PY': 'Annuel',
};

class LicenseInfo {
  final String type;
  final String client;
  final DateTime issued;
  final DateTime expiry;
  final List<String> hwids;

  LicenseInfo({
    required this.type,
    required this.client,
    required this.issued,
    required this.expiry,
    required this.hwids,
  });
}

enum LicenseCheckResult {
  valid,
  invalidFormat,
  badSignature,
  wrongMachine,
  expired,
}

class LicenseVerification {
  final LicenseCheckResult result;
  final LicenseInfo? info;
  const LicenseVerification(this.result, this.info);

  bool get isValid => result == LicenseCheckResult.valid;
}

/// Vérifie hors-ligne une licence signée Ed25519 avec la clé publique
/// embarquée dans l'application. La clé privée correspondante n'existe que
/// dans l'outil générateur séparé — impossible de forger une licence valide
/// sans elle, même en décompilant complètement cette application.
class LicenseService {
  static final Ed25519 _algorithm = Ed25519();

  /// Vérifie un bloc de licence au format "payload.signature" (base64url)
  /// et confirme que la machine actuelle fait partie des postes autorisés.
  static Future<LicenseVerification> verify(String licenseBlob) async {
    final cleaned = licenseBlob.trim();
    final parts = cleaned.split('.');
    if (parts.length != 2) {
      return const LicenseVerification(LicenseCheckResult.invalidFormat, null);
    }

    List<int> payloadBytes;
    List<int> sigBytes;
    try {
      payloadBytes = base64Url.decode(_pad(parts[0]));
      sigBytes = base64Url.decode(_pad(parts[1]));
    } catch (_) {
      return const LicenseVerification(LicenseCheckResult.invalidFormat, null);
    }

    final publicKey = SimplePublicKey(
      base64Url.decode(_pad(kLicensePublicKeyB64)),
      type: KeyPairType.ed25519,
    );
    final signature = Signature(sigBytes, publicKey: publicKey);

    bool signatureOk;
    try {
      signatureOk = await _algorithm.verify(payloadBytes, signature: signature);
    } catch (_) {
      signatureOk = false;
    }
    if (!signatureOk) {
      return const LicenseVerification(LicenseCheckResult.badSignature, null);
    }

    final info = _parsePayload(utf8.decode(payloadBytes));
    if (info == null) {
      return const LicenseVerification(LicenseCheckResult.invalidFormat, null);
    }

    final myHwid = await HardwareId.get();
    if (!info.hwids.contains(myHwid)) {
      return LicenseVerification(LicenseCheckResult.wrongMachine, info);
    }

    if (DateTime.now().isAfter(info.expiry)) {
      return LicenseVerification(LicenseCheckResult.expired, info);
    }

    return LicenseVerification(LicenseCheckResult.valid, info);
  }

  static LicenseInfo? _parsePayload(String s) {
    final f = s.split('|');
    if (f.length != 5) return null;
    if (f[0] != '1') return null; // version du format
    final type = f[1];
    final days = kLicenseDurationDays[type];
    if (days == null) return null;
    final issued = DateTime.tryParse(f[3]);
    if (issued == null) return null;
    final hwids = f[4].split(',').where((e) => e.isNotEmpty).toList();
    if (hwids.isEmpty) return null;
    return LicenseInfo(
      type: type,
      client: f[2],
      issued: issued,
      expiry: issued.add(Duration(days: days)),
      hwids: hwids,
    );
  }

  static String _pad(String b64) {
    final mod = b64.length % 4;
    if (mod == 0) return b64;
    return b64 + '=' * (4 - mod);
  }
}
