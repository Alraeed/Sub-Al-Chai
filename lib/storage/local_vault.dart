import 'dart:convert';
import 'dart:typed_data';

import 'package:hive_ce/hive.dart';

import '../core/crypto/tea_crypto.dart';
import '../models/peer.dart';
import '../models/stored_message.dart';

/// Encrypted-at-rest vault backed by Hive.
///
/// Hive boxes contain ONLY base64 ciphertext; the [dbKey] that can open them
/// lives in hardware-backed secure storage. Plaintext never touches disk.
class LocalVault {
  LocalVault._();

  static const String peersBoxName = 'peers';
  static const String messagesBoxName = 'messages';
  static const String metaBoxName = 'meta_v1';

  static late Box<Map> _peers;
  static late Box<Map> _messages;
  static late Box<Map> _meta;

  static Uint8List _dbKey = Uint8List(0);

  static bool get isOpen => _peers.isOpen;

  static Future<void> open(Uint8List dbKey) async {
    _dbKey = dbKey;
    _peers = await Hive.openBox<Map>(peersBoxName);
    _messages = await Hive.openBox<Map>(messagesBoxName);
    _meta = await Hive.openBox<Map>(metaBoxName);
  }

  /// Removes ALL local data (no secure storage touch).
  static Future<void> wipe() async {
    await _peers.clear();
    await _messages.clear();
    await _meta.clear();
    for (final String name in <String>[
      peersBoxName,
      messagesBoxName,
      metaBoxName,
    ]) {
      if (Hive.isBoxOpen(name)) {
        await Hive.deleteBoxFromDisk(name);
      }
    }
  }

  // ------------------------------------------------------------------ Peers

  static List<Peer> allPeers() {
    final List<Peer> out = <Peer>[];
    for (final Map value in _peers.values) {
      final Peer? peer = Peer.fromJson(value);
      if (peer != null) {
        out.add(peer);
      }
    }
    out.sort((Peer a, Peer b) => b.lastSeenAt.compareTo(a.lastSeenAt));
    return out;
  }

  static Peer? peerById(String peerId) {
    final Map? raw = _peers.get(peerId);
    return raw == null ? null : Peer.fromJson(raw);
  }

  static Future<void> upsertPeer(Peer peer) {
    return _peers.put(peer.id, peer.toJson());
  }

  static Future<void> removePeer(String peerId) {
    return _peers.delete(peerId);
  }

  // ------------------------------------------------------------------ Msgs

  static List<StoredMessage> messagesFor(String threadId) {
    final List<StoredMessage> out = <StoredMessage>[];
    for (final Map value in _messages.values) {
      final StoredMessage? m = StoredMessage.fromJson(value);
      if (m != null && m.threadId == threadId) {
        out.add(m);
      }
    }
    out.sort((StoredMessage a, StoredMessage b) => a.utcMs.compareTo(b.utcMs));
    return out;
  }

  static Future<String> saveMessage({
    required String threadId,
    required bool isOutgoing,
    required int kind,
    required String fromShortId,
    required String toShortId,
    required String text,
    required String status,
    int hops = 0,
  }) async {
    final String messageId = TeaCrypto.randomBytes(16).map(
      (int b) => b.toRadixString(16).padLeft(2, '0'),
    ).join();
    final Uint8List sealed = await TeaCrypto.sealText(
      key: _dbKey,
      text: text,
    );
    final StoredMessage stored = StoredMessage(
      id: messageId,
      threadId: threadId,
      isOutgoing: isOutgoing,
      kind: kind,
      fromShortId: fromShortId,
      toShortId: toShortId,
      utcMs: DateTime.now().millisecondsSinceEpoch,
      sealed: base64Encode(sealed),
      status: status,
      hops: hops,
    );
    await _messages.put(stored.id, stored.toJson());
    return stored.id;
  }

  static Future<void> markStatus(String messageId, String status) async {
    final Map? raw = _messages.get(messageId);
    if (raw == null) {
      return;
    }
    final StoredMessage? stored = StoredMessage.fromJson(raw);
    if (stored == null) {
      return;
    }
    await _messages.put(stored.id, stored.copyWith(status: status).toJson());
  }

  /// Decrypt one stored message for display. Returns null on any failure.
  static Future<String?> openText(StoredMessage message) async {
    final Uint8List? sealed = base64DecodeSafe(message.sealed);
    if (sealed == null) {
      return null;
    }
    return TeaCrypto.openText(key: _dbKey, sealed: sealed);
  }

  /// Persist a *relayed* copy without ever decrypting it (it belongs to a
  /// peer, not us) — reseal with our dbKey as an extra at-rest layer.
  static Future<void> saveRelayedCopy({
    required String threadId,
    required String messageIdHex,
    required int kind,
    required String fromShortId,
    required String toShortId,
    required int utcMs,
    required Uint8List sealedBody,
    int hops = 0,
  }) async {
    final Uint8List doubleSealed = await TeaCrypto.sealBytes(
      key: _dbKey,
      plaintext: sealedBody,
    );
    final StoredMessage stored = StoredMessage(
      id: messageIdHex,
      threadId: threadId,
      isOutgoing: false,
      kind: kind,
      fromShortId: fromShortId,
      toShortId: toShortId,
      utcMs: utcMs,
      sealed: base64Encode(doubleSealed),
      status: 'relayed',
      hops: hops,
    );
    if (_messages.containsKey(stored.id)) {
      return;
    }
    await _messages.put(stored.id, stored.toJson());
  }

  // ------------------------------------------------------------------ Meta

  static Future<Map?> readMeta(String key) async {
    return _meta.get(key);
  }

  static Future<void> writeMeta(String key, Map value) {
    return _meta.put(key, value);
  }

  static Uint8List? base64DecodeSafe(String value) {
    try {
      return Uint8List.fromList(base64Decode(value));
    } on Object {
      return null;
    }
  }
}