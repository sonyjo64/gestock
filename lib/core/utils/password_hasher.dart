import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// Hachage de mot de passe par PBKDF2-HMAC-SHA256 avec sel aléatoire par utilisateur.
///
/// Remplace l'ancien SHA-256 simple (sans sel), vulnérable aux tables arc-en-ciel
/// et au rejeu réseau. Construit uniquement avec `package:crypto` (déjà présent)
/// pour éviter une dépendance supplémentaire.
class PasswordHasher {
  static const _iterations = 50000;
  static const _saltBytes  = 16;
  static const _keyBytes   = 32;

  /// Génère un sel aléatoire (encodé base64) pour un nouvel utilisateur.
  static String generateSalt() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(_saltBytes, (_) => rnd.nextInt(256));
    return base64Encode(bytes);
  }

  /// Dérive la clé PBKDF2-HMAC-SHA256 du mot de passe + sel, encodée en base64.
  static String hash(String password, String saltB64) {
    final salt     = base64Decode(saltB64);
    final pwdBytes = utf8.encode(password);
    final hmac     = Hmac(sha256, pwdBytes);

    var u = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
    final result = List<int>.from(u);
    for (var i = 1; i < _iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < result.length; j++) {
        result[j] ^= u[j];
      }
    }
    return base64Encode(result.sublist(0, _keyBytes));
  }

  /// Vérifie un mot de passe contre un sel + hash stockés, en temps constant.
  static bool verify(String password, String saltB64, String expectedHashB64) {
    final computed = hash(password, saltB64);
    if (computed.length != expectedHashB64.length) return false;
    var diff = 0;
    for (var i = 0; i < computed.length; i++) {
      diff |= computed.codeUnitAt(i) ^ expectedHashB64.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// Ancien format (SHA-256 simple, sans sel) — conservé uniquement pour migrer
  /// en douceur les comptes créés avant l'ajout du sel. Ne pas utiliser ailleurs.
  static String legacyHash(String password) =>
      sha256.convert(utf8.encode(password)).toString();
}
