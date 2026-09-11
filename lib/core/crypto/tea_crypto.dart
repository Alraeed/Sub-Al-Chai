import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// All cryptographic material & operations for صب الجاي.
///
/// No hardcoded secrets — every key is generated at runtime:
///  * identity = Ed25519 (signing) + X25519 (key agreement);
///  * session secret per peer is DERIVED deterministically from the two
///    X25519 public keys, so nothing session-like is stored on disk;
///  * every message is AES-256-GCM sealed; every hello is Ed25519 signed;
///  * at rest, messages are re-sealed with a random per-install [dbKey].
class TeaCrypto {
  TeaCrypto._();

  static const int nonceBytes = 12;
  static const int macBytes = 16;
  static const String deriveInfo = 'spill-the-tea/v1/x25519-hkdf';

  static final Ed25519 _ed25519 = Ed25519();
  static final X25519 _x25519 = X25519();
  static final AesGcm _gcm = AesGcm.with256bits();
  static final Random _rng = Random.secure();

  // ----------------------------------------------------------- Keygen

  static Future<SimpleKeyPair> newSignKeyPair() => _ed25519.newKeyPair();

  static Future<SimpleKeyPair> newDhKeyPair() => _x25519.newKeyPair();

  static Future<Uint8List> keyPairBytes(SimpleKeyPair pair) async {
    final SimpleKeyPairData data = await pair.extract();
    return Uint8List.fromList(data.bytes);
  }

  static Future<Uint8List> publicKeyBytes(SimpleKeyPair pair) async {
    final SimplePublicKey public = await pair.extractPublicKey();
    return Uint8List.fromList(public.bytes);
  }

  // ----------------------------------------------------------- Signing

  static Future<Uint8List> sign({
    required SimpleKeyPair keyPair,
    required Uint8List message,
  }) async {
    final Signature signature = await _ed25519.sign(message, keyPair: keyPair);
    return Uint8List.fromList(signature.bytes);
  }

  static Future<bool> verifySignature({
    required Uint8List message,
    required Uint8List signature,
    required Uint8List publicKey,
  }) async {
    if (signature.length != 64) {
      return false;
    }
    try {
      final Signature sig = Signature(
        signature,
        publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
      );
      return await _ed25519.verify(message, signature: sig);
    } on Object {
      return false;
    }
  }

  // ----------------------------------------------------------- Session

  /// Deterministic 256-bit session key shared with a peer.
  /// Same value computed on both sides from the two X25519 public keys.
  static Future<Uint8List> deriveSessionKey({
    required SimpleKeyPair myDhPair,
    required Uint8List theirDhPub,
    required Uint8List myDhPub,
  }) async {
    final SecretKey shared = await _x25519.sharedSecretKey(
      keyPair: myDhPair,
      remotePublicKey: SimplePublicKey(theirDhPub, type: KeyPairType.x25519),
    );
    final Uint8List sharedBytes = Uint8List.fromList(await shared.extractBytes());

    // Canonical salt from BOTH public keys (sorted) so each side derives
    // the exact same value regardless of caller order.
    final List<int> saltParts = <int>[...myDhPub, ...theirDhPub]..sort();
    final Hkdf hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final SecretKey derived = await hkdf.deriveKey(
      secretKey: SecretKey(sharedBytes),
      nonce: Uint8List.fromList(saltParts),
      info: utf8.encode(deriveInfo),
    );
    return Uint8List.fromList(await derived.extractBytes());
  }

  // ----------------------------------------------------------- AEAD

  /// Encrypt and serialize: [nonce | ciphertext | mac] (12 + 16 bytes overhead).
  static Future<Uint8List> sealBytes({
    required Uint8List key,
    required Uint8List plaintext,
  }) async {
    final SecretBox box = await _gcm.encrypt(
      plaintext,
      secretKey: SecretKey(key),
      nonce: randomBytes(nonceBytes),
    );
    final Uint8List out = Uint8List(
      box.nonce.length + box.cipherText.length + box.mac.bytes.length,
    );
    out.setAll(0, box.nonce);
    out.setAll(box.nonce.length, box.cipherText);
    out.setAll(box.nonce.length + box.cipherText.length, box.mac.bytes);
    return out;
  }

  static Future<Uint8List?> openBytes({
    required Uint8List key,
    required Uint8List sealed,
  }) async {
    if (sealed.length < nonceBytes + macBytes) {
      return null;
    }
    final Uint8List nonce = Uint8List.sublistView(sealed, 0, nonceBytes);
    final Uint8List cipher = Uint8List.sublistView(
      sealed,
      nonceBytes,
      sealed.length - macBytes,
    );
    final Uint8List mac = Uint8List.sublistView(sealed, sealed.length - macBytes);
    try {
      final List<int> clear = await _gcm.decrypt(
        SecretBox(cipher, nonce: nonce, mac: Mac(mac)),
        secretKey: SecretKey(key),
      );
      return Uint8List.fromList(clear);
    } on Object {
      return null;
    }
  }

  static Future<Uint8List> sealText({
    required Uint8List key,
    required String text,
  }) {
    return sealBytes(key: key, plaintext: utf8.encode(text));
  }

  static Future<String?> openText({
    required Uint8List key,
    required Uint8List sealed,
  }) async {
    final Uint8List? clear = await openBytes(key: key, sealed: sealed);
    if (clear == null) {
      return null;
    }
    try {
      return utf8.decode(clear, allowMalformed: false);
    } on FormatException {
      return null;
    }
  }

  // ----------------------------------------------------------- Random

  static Uint8List randomBytes(int length) {
    final Uint8List out = Uint8List(length);
    for (int i = 0; i < length; i++) {
      out[i] = _rng.nextInt(256);
    }
    return out;
  }
}