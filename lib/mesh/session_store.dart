import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show SimpleKeyPair;
import 'package:hive_ce/hive.dart';

import '../core/crypto/dm_ratchet.dart';
import '../core/crypto/tea_crypto.dart';
import '../storage/local_vault.dart';

/// Rotating X25519 pre-keys + per-peer ratchet state for v2 direct messages.
///
/// Only private seeds never rest in plaintext: every sensitive value is
/// re-sealed with the install [LocalVault.dbKey] (the same hardware-backed key
/// that protects the message box) before it touches disk.
class DmSessionStore {
  DmSessionStore._();

  static const String boxName = 'dm_sessions_v1';
  static const String currentKey = 'cur';
  static const String historyKey = 'hist';
  static const String outPrefix = 'out:';
  static const String inPrefix = 'in:';

  static const int preKeyHistoryCap = 4;
  static const int maxSkipped = 64;

  static late Box<dynamic> _box;
  static bool _opened = false;

  /// Whether the box is usable. Every accessor degrades to a no-op when it is
  /// not open, so a storage fault can never break the (already-sealed) legacy
  /// DM path or escape as an unhandled async error.
  static bool get isOpen => _opened;

  static Future<void> open() async {
    if (_opened) {
      return;
    }
    _box = await Hive.openBox<dynamic>(boxName);
    _opened = true;
  }

  /// Destroy every rotating pre-key and per-peer ratchet secret, then remove
  /// the box from disk entirely. Used by "erase everything": before this the
  /// destructive erase left pre-keys and chain state behind.
  static Future<void> wipe() async {
    if (_opened) {
      try {
        await _box.clear();
        await _box.close();
      } on Object {
        // Falling through is fine — deleting the box below is the real goal.
      }
      _opened = false;
    }
    await Hive.deleteBoxFromDisk(boxName);
  }

  // ----------------------------------------------- my rotating pre-key

  /// Build + persist a brand-new pre-key, pushing the previous one into
  /// history (newest first) so in-flight messages under the old epoch can
  /// still be opened. Returns the fresh current pre-key.
  static Future<PreKey> rotatePreKey() async {
    if (!_opened) {
      throw StateError('dm session store is not open');
    }
    final PreKey? previous = await loadCurrentPreKey();
    final SimpleKeyPair pair = await TeaCrypto.newEphemeralDhPair();
    final Uint8List priv = await TeaCrypto.keyPairBytes(pair);
    final Uint8List pub = await TeaCrypto.publicKeyBytes(pair);
    final PreKey current = PreKey(priv, pub, (previous?.epoch ?? 0) + 1);
    await _box.put(currentKey, await _preKeyToMap(current));
    if (previous != null) {
      final List<PreKey> history = await loadPreKeyHistory();
      history.insert(0, previous);
      while (history.length > preKeyHistoryCap) {
        history.removeLast();
      }
      await _saveHistory(history);
    }
    return current;
  }

  static Future<PreKey?> loadCurrentPreKey() async {
    if (!_opened) {
      return null;
    }
    final Map? raw = _box.get(currentKey);
    return raw == null ? null : await _preKeyFromMap(raw);
  }

  static Future<List<PreKey>> loadPreKeyHistory() async {
    final List<PreKey> out = <PreKey>[];
    if (!_opened) {
      return out;
    }
    final List<Object>? entries = _box.get(historyKey) as List<Object>?;
    if (entries == null) {
      return out;
    }
    for (final Object e in entries) {
      if (e is! Map) {
        continue;
      }
      final PreKey? pk = await _preKeyFromMap(e);
      if (pk != null) {
        out.add(pk);
      }
    }
    return out;
  }

  /// Every pre-key we can still decrypt for, newest first.
  static Future<List<PreKey>> loadOpenPreKeys() async {
    final List<PreKey> out = <PreKey>[];
    final PreKey? current = await loadCurrentPreKey();
    if (current != null) {
      out.add(current);
    }
    out.addAll(await loadPreKeyHistory());
    return out;
  }

  /// The pre-key for [epoch] if we still hold it (else null).
  static Future<PreKey?> preKeyForEpoch(int epoch) async {
    for (final PreKey pk in await loadOpenPreKeys()) {
      if (pk.epoch == epoch) {
        return pk;
      }
    }
    return null;
  }

  static Future<void> _saveHistory(List<PreKey> history) async {
    if (!_opened) {
      return;
    }
    final List<Object> entries = <Object>[];
    for (final PreKey pk in history) {
      entries.add(await _preKeyToMap(pk));
    }
    await _box.put(historyKey, entries);
  }

  // ------------------------------------------- per-peer outbound state

  static Future<OutboundDmState?> loadOutbound(String peerId) async {
    if (!_opened) {
      return null;
    }
    final Map? raw = _box.get(outPrefix + peerId);
    return raw == null ? null : await _outboundFromMap(raw);
  }

  static Future<void> saveOutbound(String peerId, OutboundDmState state) async {
    if (!_opened) {
      return;
    }
    await _box.put(outPrefix + peerId, await _outboundToMap(state));
  }

  static Future<void> clearOutbound(String peerId) async {
    if (!_opened) {
      return;
    }
    await _box.delete(outPrefix + peerId);
  }

  // ------------------------------------------- per-peer inbound state

  static Future<InboundDmState?> loadInbound(String peerId) async {
    if (!_opened) {
      return null;
    }
    final Map? raw = _box.get(inPrefix + peerId);
    return raw == null ? null : await _inboundFromMap(raw);
  }

  static Future<void> saveInbound(String peerId, InboundDmState state) async {
    if (!_opened) {
      return;
    }
    await _box.put(inPrefix + peerId, await _inboundToMap(state));
  }

  static Future<void> clearInbound(String peerId) async {
    if (!_opened) {
      return;
    }
    await _box.delete(inPrefix + peerId);
  }

  // ----------------------------------------------------------- helpers

  static Future<Map> _preKeyToMap(PreKey pk) async {
    return <String, Object>{
      'seed': await _seal(pk.seed),
      'pub': await _seal(pk.publicKey),
      'epoch': pk.epoch,
    };
  }

  static Future<PreKey?> _preKeyFromMap(Map raw) async {
    final int? epoch = raw['epoch'] as int?;
    final Uint8List? seed = await _unseal(raw['seed'] as String?);
    final Uint8List? pub = await _unseal(raw['pub'] as String?);
    if (epoch == null || seed == null || pub == null) {
      return null;
    }
    return PreKey(seed, pub, epoch);
  }

  static Future<Map> _outboundToMap(OutboundDmState s) async {
    return <String, Object>{
      'ephPriv': await _seal(s.ephemeralPriv),
      'ephPub': await _seal(s.ephemeralPub),
      'theirEpoch': s.theirPreKeyEpoch,
      'chain': await _seal(s.chainKey),
      'next': s.nextIndex,
    };
  }

  static Future<OutboundDmState?> _outboundFromMap(Map raw) async {
    final int? theirEpoch = raw['theirEpoch'] as int?;
    final int? next = raw['next'] as int?;
    final Uint8List? ephPriv = await _unseal(raw['ephPriv'] as String?);
    final Uint8List? ephPub = await _unseal(raw['ephPub'] as String?);
    final Uint8List? chain = await _unseal(raw['chain'] as String?);
    if (theirEpoch == null ||
        next == null ||
        ephPriv == null ||
        ephPub == null ||
        chain == null) {
      return null;
    }
    return OutboundDmState(
      ephemeralPriv: ephPriv,
      ephemeralPub: ephPub,
      theirPreKeyEpoch: theirEpoch,
      chainKey: chain,
      nextIndex: next,
    );
  }

  static Future<Map> _inboundToMap(InboundDmState s) async {
    final List<Object> skipped = <Object>[];
    for (final MapEntry<int, Uint8List> e in s.skipped.entries) {
      skipped.add(<String, Object>{'i': e.key, 'k': await _seal(e.value)});
    }
    return <String, Object>{
      'theirEphPub': await _seal(s.theirEphPub),
      'myEpoch': s.myPreKeyEpoch,
      'chain': await _seal(s.recvChainKey),
      'next': s.recvN,
      'skipped': skipped,
    };
  }

  static Future<InboundDmState?> _inboundFromMap(Map raw) async {
    final int? myEpoch = raw['myEpoch'] as int?;
    final int? next = raw['next'] as int?;
    final Uint8List? theirEphPub = await _unseal(raw['theirEphPub'] as String?);
    final Uint8List? chain = await _unseal(raw['chain'] as String?);
    if (myEpoch == null ||
        next == null ||
        theirEphPub == null ||
        chain == null) {
      return null;
    }
    final Map<int, Uint8List> skipped = <int, Uint8List>{};
    final List<Object>? entries = raw['skipped'] as List<Object>?;
    if (entries != null) {
      for (final Object e in entries) {
        if (e is! Map) {
          continue;
        }
        final Map entry = e;
        final int? i = entry['i'] as int?;
        final Uint8List? k = await _unseal(entry['k'] as String?);
        if (i != null && k != null && skipped.length < maxSkipped) {
          skipped[i] = k;
        }
      }
    }
    return InboundDmState(
      theirEphPub: theirEphPub,
      myPreKeyEpoch: myEpoch,
      recvChainKey: chain,
      recvN: next,
      skipped: skipped,
    );
  }

  static Future<String> _seal(Uint8List plain) async {
    return base64Encode(
      await TeaCrypto.sealBytes(key: LocalVault.dbKey, plaintext: plain),
    );
  }

  static Future<Uint8List?> _unseal(String? sealed) async {
    if (sealed == null) {
      return null;
    }
    try {
      final Uint8List bytes = Uint8List.fromList(base64Decode(sealed));
      return await TeaCrypto.openBytes(key: LocalVault.dbKey, sealed: bytes);
    } on Object {
      return null;
    }
  }
}

/// One epoch of my rotating X25519 pre-key.
class PreKey {
  const PreKey(this.seed, this.publicKey, this.epoch);

  /// 32-byte X25519 private seed (sealed at rest by the store).
  final Uint8List seed;
  final Uint8List publicKey;
  final int epoch;
}

/// Outbound (my → peer) ratchet state inside one session.
class OutboundDmState {
  const OutboundDmState({
    required this.ephemeralPriv,
    required this.ephemeralPub,
    required this.theirPreKeyEpoch,
    required this.chainKey,
    required this.nextIndex,
  });

  /// Session ephemeral private seed — deleted when the session ends.
  final Uint8List ephemeralPriv;
  final Uint8List ephemeralPub;

  /// Epoch of the peer's pre-key this session is bound to.
  final int theirPreKeyEpoch;

  /// Current outbound chain state; message index [nextIndex] uses it next.
  final Uint8List chainKey;
  final int nextIndex;

  OutboundDmState advance(Uint8List nextChainKey) {
    return OutboundDmState(
      ephemeralPriv: ephemeralPriv,
      ephemeralPub: ephemeralPub,
      theirPreKeyEpoch: theirPreKeyEpoch,
      chainKey: nextChainKey,
      nextIndex: nextIndex + 1,
    );
  }
}

/// Inbound (peer → me) ratchet state inside one session.
class InboundDmState {
  const InboundDmState({
    required this.theirEphPub,
    required this.myPreKeyEpoch,
    required this.recvChainKey,
    required this.recvN,
    required this.skipped,
  });

  /// The peer's session ephemeral public key — identifies the session.
  final Uint8List theirEphPub;

  /// Epoch of MY pre-key the peer sealed to (from the wire header).
  final int myPreKeyEpoch;

  /// Current inbound chain state; the next unseen index is [recvN].
  final Uint8List recvChainKey;
  final int recvN;

  /// index → message key for out-of-order delivery (bounded).
  final Map<int, Uint8List> skipped;

  /// State after opening index [next] − 1: new chain, advanced counter, and
  /// the skip window merged with the pass-through keys from this walk.
  InboundDmState advanced({
    required Uint8List chain,
    required int next,
    required List<DmSkippedKey> added,
  }) {
    final Map<int, Uint8List> merged = <int, Uint8List>{};
    for (final MapEntry<int, Uint8List> e in skipped.entries) {
      if (e.key >= next) {
        merged[e.key] = e.value;
      }
    }
    for (final DmSkippedKey k in added) {
      merged[k.index] = k.messageKey;
    }
    // Keep the window bounded; when over, drop the *furthest future* indices
    // (least likely to still arrive).
    while (merged.length > DmSessionStore.maxSkipped) {
      int highest = -1;
      for (final int i in merged.keys) {
        if (i > highest) {
          highest = i;
        }
      }
      merged.remove(highest);
    }
    return InboundDmState(
      theirEphPub: theirEphPub,
      myPreKeyEpoch: myPreKeyEpoch,
      recvChainKey: chain,
      recvN: next,
      skipped: merged,
    );
  }

  /// State for a *brand-new* session opened by [theirEphPub]: message index
  /// [openedThrough] − 1 just succeeded, so the next unseen index is
  /// [openedThrough] with the walk-advanced chain.
  factory InboundDmState.fresh({
    required Uint8List theirEphPub,
    required int myPreKeyEpoch,
    required Uint8List recvChainKey,
    required int openedThrough,
  }) {
    return InboundDmState(
      theirEphPub: theirEphPub,
      myPreKeyEpoch: myPreKeyEpoch,
      recvChainKey: recvChainKey,
      recvN: openedThrough,
      skipped: const <int, Uint8List>{},
    );
  }
}
