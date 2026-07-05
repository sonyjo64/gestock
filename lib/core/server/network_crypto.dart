import 'dart:convert';
import 'package:cryptography/cryptography.dart';

/// Chiffrement et authentification des échanges HTTP entre le serveur POS
/// et les terminaux (mode multi-postes), dérivés du code d'accès partagé.
///
/// Le code d'accès brut n'est **jamais** transmis sur le réseau : on en
/// dérive deux valeurs distinctes par hachage à sens unique — un jeton
/// d'authentification (envoyé dans l'en-tête HTTP) et une clé de
/// chiffrement (jamais transmise). Un tiers qui intercepte l'en-tête ne
/// peut donc pas reconstituer la clé de chiffrement, ni le code d'accès.
class NetworkCrypto {
  static final AesGcm _aesGcm = AesGcm.with256bits();
  static final Sha256 _sha256 = Sha256();

  /// Valeur à envoyer dans l'en-tête `x-pos-token` (jamais le code brut).
  static Future<String> authTag(String token) async {
    final hash = await _sha256.hash(utf8.encode('auth:$token'));
    return base64Url.encode(hash.bytes);
  }

  static Future<SecretKey> _encryptionKey(String token) async {
    final hash = await _sha256.hash(utf8.encode('enc:$token'));
    return SecretKey(hash.bytes);
  }

  /// Chiffre [plainBytes] avec AES-256-GCM. Résultat : "nonce.donnees"
  /// (base64url), prêt à envoyer tel quel comme corps de requête/réponse.
  static Future<String> encrypt(String token, List<int> plainBytes) async {
    final key = await _encryptionKey(token);
    final box = await _aesGcm.encrypt(plainBytes, secretKey: key);
    final combined = <int>[...box.cipherText, ...box.mac.bytes];
    return '${base64Url.encode(box.nonce)}.${base64Url.encode(combined)}';
  }

  /// Déchiffre une chaîne produite par [encrypt]. Lève une exception si le
  /// tag d'authentification est invalide (donnée altérée ou mauvais code).
  static Future<List<int>> decrypt(String token, String payload) async {
    final key = await _encryptionKey(token);
    final parts = payload.split('.');
    if (parts.length != 2) {
      throw const FormatException('Format chiffré invalide');
    }
    final nonce = base64Url.decode(_pad(parts[0]));
    final combined = base64Url.decode(_pad(parts[1]));
    const macLength = 16; // AES-GCM : tag d'authentification de 16 octets
    if (combined.length < macLength) {
      throw const FormatException('Format chiffré invalide');
    }
    final cipherText = combined.sublist(0, combined.length - macLength);
    final mac = Mac(combined.sublist(combined.length - macLength));
    final box = SecretBox(cipherText, nonce: nonce, mac: mac);
    return _aesGcm.decrypt(box, secretKey: key);
  }

  static String _pad(String b64) {
    final mod = b64.length % 4;
    if (mod == 0) return b64;
    return b64 + '=' * (4 - mod);
  }
}
