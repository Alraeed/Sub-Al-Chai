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
    final Uint8List sharedBytes =
        Uint8List.fromList(await shared.extractBytes());

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

  // ------------------------------------------ V2 — forward-secret DMs

  static const String dmRootInfo = 'spill-the-tea/v2/x3dh/root';
  static const String dmInitChainInfo = 'spill-the-tea/v2/x3dh/init';
  static const String dmRespChainInfo = 'spill-the-tea/v2/x3dh/resp';
  static const String dmKeyInfo = 'spill-the-tea/v2/x3dh/mk';
  static const String dmChainInfo = 'spill-the-tea/v2/x3dh/chain';

  /// Hard safety rails for ratchet-chain work — never trust the wire's index.
  static const int maxDmChainSteps = 4096;
  static const int maxDmSkippedKeys = 64;

  /// Fresh X25519 pair, used for one-time session ephemerals and rotated
  /// pre-keys. The private bytes are returned to the caller and must be kept
  /// only in secure memory (the session store re-seals them at rest).
  static Future<SimpleKeyPair> newEphemeralDhPair() => _x25519.newKeyPair();

  /// Rebuild an X25519 pair from a persisted 32-byte private seed so session
  /// state is fully reconstructible without storing the public half.
  static Future<SimpleKeyPair> dhPairFromSeed(Uint8List seed) =>
      _x25519.newKeyPairFromSeed(seed);

  static Future<Uint8List> dhShared({
    required SimpleKeyPair myPair,
    required Uint8List theirPublic,
  }) async {
    final SecretKey shared = await _x25519.sharedSecretKey(
      keyPair: myPair,
      remotePublicKey: SimplePublicKey(theirPublic, type: KeyPairType.x25519),
    );
    return Uint8List.fromList(await shared.extractBytes());
  }

  /// X3DH-lite session root for one v2 DM session.
  ///
  /// Both callers pass their own private halves (sender: static + ephemeral;
  /// receiver: static + pre-key). Because X25519 is symmetric and the three
  /// DH outputs are byte-sorted before hashing, both sides converge on the
  /// same 32-byte root regardless of who initiated. An attacker who only ever
  /// obtains the long-term private keys cannot reconstruct the root — the
  /// per-message ephemeral private half is gone by then (forward secrecy).
  static Future<Uint8List> deriveDmRoot({
    required SimpleKeyPair myStaticPair,
    required SimpleKeyPair myEphemeralPair,
    required Uint8List theirPreKeyPub,
    required Uint8List theirStaticPub,
  }) async {
    final Uint8List dhStaticPre = await dhShared(
      myPair: myStaticPair,
      theirPublic: theirPreKeyPub,
    );
    final Uint8List dhEphStatic = await dhShared(
      myPair: myEphemeralPair,
      theirPublic: theirStaticPub,
    );
    final Uint8List dhEphPre = await dhShared(
      myPair: myEphemeralPair,
      theirPublic: theirPreKeyPub,
    );
    final List<Uint8List> sorted = <Uint8List>[
      dhStaticPre,
      dhEphStatic,
      dhEphPre,
    ];
    sorted.sort(_compareBytes);
    final Uint8List material = Uint8List(96);
    material.setAll(0, sorted[0]);
    material.setAll(32, sorted[1]);
    material.setAll(64, sorted[2]);
    return await _hkdf32(material, Uint8List(0), utf8.encode(dmRootInfo));
  }

  /// Direction seed for a session's two independent chains (one per sender).
  /// The side that starts a session sends on the `initiator` chain and opens
  /// the `responder` one; the other side mirrors that.
  static Future<Uint8List> dmDirectionChain({
    required Uint8List root,
    required bool initiator,
  }) async {
    return await _hkdf32(
      root,
      Uint8List(0),
      utf8.encode(initiator ? dmInitChainInfo : dmRespChainInfo),
    );
  }

  /// One ratchet step. [step] feeds a per-index salt so the same [chainKey]
  /// never yields colliding keys. The step function is one-way: an old
  /// message key can never be reconstructed from a newer chain state.
  static Future<DmRatchetStep> dmRatchetStep({
    required Uint8List chainKey,
    required int step,
  }) async {
    return DmRatchetStep(
      await _hkdf32(
        chainKey,
        _dmStepSalt(step, 0x01),
        utf8.encode(dmKeyInfo),
      ),
      await _hkdf32(
        chainKey,
        _dmStepSalt(step, 0x02),
        utf8.encode(dmChainInfo),
      ),
    );
  }

  static Future<Uint8List> _hkdf32(
    Uint8List ikm,
    Uint8List salt,
    Uint8List info,
  ) async {
    final Hkdf hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final SecretKey derived = await hkdf.deriveKey(
      secretKey: SecretKey(ikm),
      nonce: salt,
      info: info,
    );
    return Uint8List.fromList(await derived.extractBytes());
  }

  /// 8-byte salt: u32(step) | u32(purpose) — domains never collide.
  static Uint8List _dmStepSalt(int step, int purpose) {
    final Uint8List out = Uint8List(8);
    out[0] = (step >> 24) & 0xFF;
    out[1] = (step >> 16) & 0xFF;
    out[2] = (step >> 8) & 0xFF;
    out[3] = step & 0xFF;
    out[4] = (purpose >> 24) & 0xFF;
    out[5] = (purpose >> 16) & 0xFF;
    out[6] = (purpose >> 8) & 0xFF;
    out[7] = purpose & 0xFF;
    return out;
  }

  static int _compareBytes(Uint8List a, Uint8List b) {
    final int n = a.length < b.length ? a.length : b.length;
    for (int i = 0; i < n; i++) {
      if (a[i] != b[i]) {
        return a[i] - b[i];
      }
    }
    return a.length - b.length;
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
    final Uint8List mac =
        Uint8List.sublistView(sealed, sealed.length - macBytes);
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

/// Result of one v2 DM ratchet step.
class DmRatchetStep {
  const DmRatchetStep(this.messageKey, this.nextChainKey);

  /// Key that seals the message at this chain position.
  final Uint8List messageKey;

  /// Chain state to feed the *next* step — the current one is unrecoverable.
  final Uint8List nextChainKey;
}
