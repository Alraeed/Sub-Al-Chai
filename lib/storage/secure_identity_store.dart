import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/utils/safe_log.dart';

/// All secrets of an installation — held ONLY inside hardware-backed secure
/// storage (Android Keystore / iOS Keychain). Never plaintext on disk.
class IdentityMaterial {
  const IdentityMaterial({
    required this.displayName,
    required this.signSeed,
    required this.dhPrivate,
    required this.signPublic,
    required this.dhPublic,
  });

  final String displayName;

  /// Ed25519 seed (32 B).
  final Uint8List signSeed;

  /// X25519 private scalar (32 B).
  final Uint8List dhPrivate;

  final Uint8List signPublic;
  final Uint8List dhPublic;

  SimpleKeyPair get signKeyPair => SimpleKeyPairData(
      signSeed,
      publicKey: SimplePublicKey(signPublic, type: KeyPairType.ed25519),
      type: KeyPairType.ed25519,
    );

  SimpleKeyPair get dhKeyPair => SimpleKeyPairData(
      dhPrivate,
      publicKey: SimplePublicKey(dhPublic, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
}

/// Persists the identity under keys scoped to the app on both platforms.
class SecureIdentityStore {
  SecureIdentityStore._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static const String _kName = 'identity_name';
  static const String _kSignSeed = 'identity_sign_seed';
  static const String _kSignPub = 'identity_sign_pub';
  static const String _kDhPriv = 'identity_dh_priv';
  static const String _kDhPub = 'identity_dh_pub';
  static const String _kDbKey = 'local_db_key';

  static Future<IdentityMaterial?> loadIdentity() async {
    try {
      final String? name = await _storage.read(key: _kName);
      final String? signSeed = await _storage.read(key: _kSignSeed);
      final String? signPub = await _storage.read(key: _kSignPub);
      final String? dhPriv = await _storage.read(key: _kDhPriv);
      final String? dhPub = await _storage.read(key: _kDhPub);
      if (name == null ||
          signSeed == null ||
          signPub == null ||
          dhPriv == null ||
          dhPub == null) {
        return null;
      }
      return IdentityMaterial(
        displayName: name,
        signSeed: _decode(signSeed),
        signPublic: _decode(signPub),
        dhPrivate: _decode(dhPriv),
        dhPublic: _decode(dhPub),
      );
    } on Object catch (e) {
      SafeLog.error('secureStore', 'loadIdentity failed', e);
      return null;
    }
  }

  static Future<void> saveIdentity(IdentityMaterial identity) async {
    try {
      await _storage.write(key: _kName, value: identity.displayName);
      await _storage.write(key: _kSignSeed, value: _encode(identity.signSeed));
      await _storage.write(key: _kSignPub, value: _encode(identity.signPublic));
      await _storage.write(key: _kDhPriv, value: _encode(identity.dhPrivate));
      await _storage.write(key: _kDhPub, value: _encode(identity.dhPublic));
    } on Object catch (e) {
      SafeLog.error('secureStore', 'saveIdentity failed', e);
      rethrow;
    }
  }

  static Future<void> deleteIdentity() async {
    try {
      await _storage.deleteAll();
    } on Object catch (e) {
      SafeLog.error('secureStore', 'deleteIdentity failed', e);
      rethrow;
    }
  }

  /// The per-install random key that seals the local message DB.
  /// Generated once and reused; kept only in secure storage.
  static Future<Uint8List> loadOrCreateDbKey() async {
    final String? existing = await _storage.read(key: _kDbKey);
    if (existing != null) {
      return _decode(existing);
    }
    final Uint8List fresh = TeaNewKey.random32();
    await _storage.write(key: _kDbKey, value: _encode(fresh));
    return fresh;
  }

  static String _encode(Uint8List bytes) => base64Encode(bytes);

  static Uint8List _decode(String value) => Uint8List.fromList(base64Decode(value));
}

/// Tiny local key source — kept separate from package:cryptography usage so
/// the storage layer never needs an algorithm object.
abstract final class TeaNewKey {
  static Uint8List random32() {
    final Uint8List out = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      out[i] = _random.nextInt(256);
    }
    return out;
  }

  static final Random _random = Random.secure();
}