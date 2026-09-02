import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// KOI client-side encryption — Dart port of crypto.ts.
///
/// Locked spec (must match the web client byte-for-byte):
///   - AES-256-GCM for encryption
///   - PBKDF2-HMAC-SHA256, 600,000 iterations, for key derivation
///   - Payload format: v1:PBKDF2:base64(salt):base64(nonce):base64(ciphertext_with_mac)
///
/// ⚠️ KNOWN TRAP, per TRACK_FLUTTER_MOBILE_PATCHED_v4_8.md: the Dart
/// `cryptography` package returns the MAC (auth tag) SEPARATELY from the
/// ciphertext by default. Web Crypto's AES-GCM auto-appends it. This file
/// manually concatenates cipherText + mac.bytes to match Web Crypto's
/// output shape — see `encrypt()`/`decrypt()` below. This has NOT yet
/// been verified byte-for-byte against a real Web-generated payload
/// (Gate 1-J). Do not treat this as done until that joint test passes.
class KoiCryptoService {
  static const int _pbkdf2Iterations = 600000;
  static const int _saltBytes = 16;
  static const int _gcmTagBytes = 16; // AES-GCM auth tag length
  static const String _formatVersion = 'v1';
  static const String _kdfLabel = 'PBKDF2';
  static const String _anonSecretStorageKey = 'koi_anon_secret';

  final AesGcm _algorithm = AesGcm.with256bits();
  final FlutterSecureStorage _secureStorage;

  KoiCryptoService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  // ---------- salt ----------

  /// Generates a new random 16-byte salt, base64-encoded.
  /// Persist to users/{uid}.public_crypto_metadata.salt.
  String generateSalt() {
    final random = Random.secure();
    final saltBytes =
        Uint8List.fromList(List<int>.generate(_saltBytes, (_) => random.nextInt(256)));
    return base64Encode(saltBytes);
  }

  // ---------- anonymous-phase secret ----------

  /// Returns this device's anonymous-phase secret, generating and
  /// persisting one via flutter_secure_storage on first call.
  ///
  /// NOTE: the web client stores its equivalent in localStorage (weaker).
  /// Using flutter_secure_storage here is a deliberate, positive
  /// asymmetry — it does not need to match the web storage mechanism,
  /// only the final ciphertext FORMAT needs to match across platforms.
  Future<String> getOrCreateAnonymousSecret() async {
    final existing = await _secureStorage.read(key: _anonSecretStorageKey);
    if (existing != null) return existing;

    final random = Random.secure();
    final secretBytes =
        Uint8List.fromList(List<int>.generate(32, (_) => random.nextInt(256)));
    final generated = base64Encode(secretBytes);
    await _secureStorage.write(key: _anonSecretStorageKey, value: generated);
    return generated;
  }

  /// Call after successful migration (mirrors reencryptOnLinking() on web)
  /// to remove the now-obsolete anonymous secret. Do NOT call before
  /// migration completes.
  Future<void> clearAnonymousSecret() async {
    await _secureStorage.delete(key: _anonSecretStorageKey);
  }

  // ---------- key derivation ----------

  Future<SecretKey> _deriveKey(String secret, String saltB64) async {
    final saltBytes = base64Decode(saltB64);
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _pbkdf2Iterations,
      bits: 256,
    );
    return pbkdf2.deriveKeyFromPassword(password: secret, nonce: saltBytes);
  }

  // ---------- public encrypt / decrypt ----------

  /// Encrypts [plaintext] under a key derived from [secret] + [saltB64].
  /// Returns: v1:PBKDF2:base64(salt):base64(nonce):base64(ciphertext_with_mac)
  Future<String> encrypt(String plaintext, String secret, String saltB64) async {
    final secretKey = await _deriveKey(secret, saltB64);
    final nonce = _algorithm.newNonce(); // 12 bytes, matches Web Crypto's NONCE_BYTES

    final secretBox = await _algorithm.encrypt(
      utf8.encode(plaintext),
      secretKey: secretKey,
      nonce: nonce,
    );

    // Manually append the MAC to match Web Crypto's auto-appended shape —
    // see the KNOWN TRAP note at the top of this file.
    final ciphertextWithMac =
        Uint8List.fromList([...secretBox.cipherText, ...secretBox.mac.bytes]);

    return [
      _formatVersion,
      _kdfLabel,
      saltB64,
      base64Encode(nonce),
      base64Encode(ciphertextWithMac),
    ].join(':');
  }

  /// Decrypts a payload produced by `encrypt()` (Dart or web). Validates
  /// the versioned format, failing loudly on anything malformed.
  Future<String> decrypt(String payload, String secret) async {
    final parts = payload.split(':');
    if (parts.length != 5) {
      throw FormatException(
          'Malformed KOI crypto payload: expected 5 colon-separated parts, got ${parts.length}');
    }

    final version = parts[0];
    final kdf = parts[1];
    final saltB64 = parts[2];
    final nonceB64 = parts[3];
    final ciphertextB64 = parts[4];

    if (version != _formatVersion) {
      throw FormatException('Unsupported payload version: "$version" (expected "$_formatVersion")');
    }
    if (kdf != _kdfLabel) {
      throw FormatException('Unsupported KDF label: "$kdf" (expected "$_kdfLabel")');
    }

    final combined = base64Decode(ciphertextB64);
    if (combined.length < _gcmTagBytes) {
      throw FormatException('Ciphertext too short to contain a valid GCM auth tag');
    }
    // Split the manually-appended MAC back off before handing to SecretBox.
    final cipherText = combined.sublist(0, combined.length - _gcmTagBytes);
    final macBytes = combined.sublist(combined.length - _gcmTagBytes);

    final secretBox = SecretBox(
      cipherText,
      nonce: base64Decode(nonceB64),
      mac: Mac(macBytes),
    );

    final secretKey = await _deriveKey(secret, saltB64);
    final clearBytes = await _algorithm.decrypt(secretBox, secretKey: secretKey);
    return utf8.decode(clearBytes);
  }
}
