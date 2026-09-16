import 'dart:typed_data';

import '../core/utils/sanitizer.dart';
import '../models/stored_message.dart';
import 'fragmenter.dart';
import 'protocol.dart';

/// End-to-end sealed message envelope carried inside a logical packet.
///
/// layout: op(1) msgId(16) kind(1) hop(1) from(8) to(8) ts(8) [kind body]
/// `body` is nonce|ciphertext|mac sealed with the recipient session key,
/// so relay nodes can carry it without ever reading it.
///
/// Kind-dependent body headers:
///  * kind 0/1 (legacy): body starts directly with the sealed bytes;
///  * kind 2 (v2 DM):    escrowPub(32) dmIndex(4) preKeyEpoch(4) | sealed;
///  * kind 3 (announce): prePub(32) preEpoch(4) — public pre-key card.
abstract final class MessageEnvelopeCodec {
  static const int overhead = 1 + 16 + 1 + 1 + 8 + 8 + 8;

  static List<int> build({
    required Uint8List msgId,
    required int kind,
    required int hopLimit,
    required String fromShortId,
    required String toShortId,
    required int utcMs,
    required Uint8List sealedBody,
    Uint8List? escrowPub,
    int dmIndex = 0,
    int preKeyEpoch = 0,
  }) {
    final Uint8List from = shortWire(fromShortId);
    final Uint8List to = shortWire(toShortId);
    final int extra = kind == MessageKinds.directV2
        ? 32 + 4 + 4
        : (kind == MessageKinds.preKeyAnnounce ? 32 + 4 : 0);
    final int total = overhead + extra + sealedBody.length;
    if (total > MessageEnvelope.maxPacketBytes) {
      throw ArgumentError('envelope too large: $total');
    }
    final bool needsHeader =
        kind == MessageKinds.directV2 || kind == MessageKinds.preKeyAnnounce;
    if (needsHeader && (escrowPub == null || escrowPub.length != 32)) {
      throw ArgumentError('v2 envelope requires a 32-byte escrow public key');
    }
    if (kind == MessageKinds.directV2 && dmIndex < 0) {
      throw ArgumentError('dm index out of range');
    }
    final Uint8List out = Uint8List(total);
    int at = 0;
    out[at++] = Opcodes.message;
    out.setAll(at, msgId);
    at += 16;
    out[at++] = kind & 0xFF;
    out[at++] = hopLimit & 0xFF;
    out.setAll(at, from);
    at += 8;
    out.setAll(at, to);
    at += 8;
    writeInt64be(out, at, utcMs);
    at += 8;
    if (needsHeader) {
      out.setAll(at, escrowPub as Uint8List);
      at += 32;
      writeInt32be(
          out, at, kind == MessageKinds.directV2 ? dmIndex : preKeyEpoch);
      at += 4;
      if (kind == MessageKinds.directV2) {
        writeInt32be(out, at, preKeyEpoch);
        at += 4;
      }
    }
    out.setAll(at, sealedBody);
    return out;
  }

  /// Strictly parsed; returns null for non-message packets, throws
  /// [FormatException] for anything claiming to be a message but exceeding
  /// any bound.
  static ParsedMessageEnvelope? parse(Uint8List packet) {
    if (!SafeInput.isReasonableMessageEnvelope(packet)) {
      throw const FormatException('message envelope out of bounds');
    }
    if (packet[0] != Opcodes.message) {
      return null;
    }
    if (packet.length < overhead) {
      throw const FormatException('message envelope truncated');
    }
    int at = 1;
    final Uint8List msgId = Uint8List.fromList(
      Uint8List.sublistView(packet, at, at + 16),
    );
    at += 16;
    final int kind = packet[at++];
    final int hopLimit = packet[at++];
    if (hopLimit > MessageLimits.maxHops) {
      throw const FormatException('hop limit out of range');
    }
    final Uint8List from = Uint8List.fromList(
      Uint8List.sublistView(packet, at, at + 8),
    );
    at += 8;
    final Uint8List to = Uint8List.fromList(
      Uint8List.sublistView(packet, at, at + 8),
    );
    at += 8;
    final int utcMs = readInt64be(packet, at);
    at += 8;
    if (utcMs <= 0 || utcMs > DateTime.now().millisecondsSinceEpoch + 120000) {
      throw const FormatException('message timestamp out of range');
    }

    final Uint8List escrowPub;
    final int? dmIndex;
    final int? preKeyEpoch;
    final Uint8List sealedBody;
    final int mac = 16;
    if (kind == MessageKinds.directV2) {
      if (packet.length < at + 32 + 4 + 4 + 12 + mac) {
        throw const FormatException('v2 dm envelope truncated');
      }
      escrowPub =
          Uint8List.fromList(Uint8List.sublistView(packet, at, at + 32));
      at += 32;
      final int index = readInt32be(packet, at);
      at += 4;
      if (index < 0) {
        throw const FormatException('v2 dm index out of range');
      }
      dmIndex = index;
      preKeyEpoch = readInt32be(packet, at);
      at += 4;
      sealedBody = Uint8List.fromList(Uint8List.sublistView(packet, at));
    } else if (kind == MessageKinds.preKeyAnnounce) {
      if (packet.length < at + 32 + 4) {
        throw const FormatException('pre-key announce truncated');
      }
      escrowPub =
          Uint8List.fromList(Uint8List.sublistView(packet, at, at + 32));
      at += 32;
      preKeyEpoch = readInt32be(packet, at);
      at += 4;
      dmIndex = null;
      sealedBody = Uint8List.fromList(Uint8List.sublistView(packet, at));
    } else if (kind == MessageKinds.broadcast || kind == MessageKinds.direct) {
      escrowPub = Uint8List(0);
      dmIndex = null;
      preKeyEpoch = null;
      sealedBody = Uint8List.fromList(Uint8List.sublistView(packet, at));
      if (sealedBody.length < 12 + mac) {
        throw const FormatException('sealed body too small');
      }
    } else {
      throw const FormatException('unknown message kind');
    }
    return ParsedMessageEnvelope(
      msgId: msgId,
      kind: kind,
      hopLimit: hopLimit,
      fromShortId: shortToHex(from),
      toShortId: shortToHex(to),
      utcMs: utcMs,
      sealedBody: sealedBody,
      escrowPub: escrowPub,
      dmIndex: dmIndex,
      preKeyEpoch: preKeyEpoch,
    );
  }

  /// Encode a short id as exactly 8 raw bytes. A short id is 16 hex chars
  /// (8 bytes); anything shorter is zero-padded, never throws on hostile input.
  static Uint8List shortWire(String hex) {
    final String clean = hex.trim();
    final Uint8List out = Uint8List(8);
    final int byteCount = (clean.length ~/ 2) > 8 ? 8 : (clean.length ~/ 2);
    for (int i = 0; i < byteCount; i++) {
      try {
        out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
      } on FormatException {
        out[i] = 0;
      }
    }
    return out;
  }
}

class ParsedMessageEnvelope {
  const ParsedMessageEnvelope({
    required this.msgId,
    required this.kind,
    required this.hopLimit,
    required this.fromShortId,
    required this.toShortId,
    required this.utcMs,
    required this.sealedBody,
    this.escrowPub,
    this.dmIndex,
    this.preKeyEpoch,
  });

  final Uint8List msgId;
  final int kind;
  final int hopLimit;
  final String fromShortId;
  final String toShortId;
  final int utcMs;
  final Uint8List sealedBody;

  /// v2 DM: sender's one-time session ephemeral public key;
  /// pre-key announce: the announced public pre-key. Empty otherwise.
  final Uint8List? escrowPub;

  /// v2 DM: chain index of this message (0-based). Null for other kinds.
  final int? dmIndex;

  /// v2 DM: receiver pre-key epoch the sender sealed to.
  /// pre-key announce: announced pre-key epoch. Null otherwise.
  final int? preKeyEpoch;

  bool get isDirectV2 => kind == MessageKinds.directV2;

  bool get isPreKeyAnnounce => kind == MessageKinds.preKeyAnnounce;

  /// Stable dedup key for relay flood protection (16-byte msg id, hex).
  String get dedupKey {
    final StringBuffer sb = StringBuffer();
    for (final int b in msgId) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}

/// Logical message kinds — the byte that switches envelope layouts.
abstract final class MessageKinds {
  /// Neighborhood broadcast (v1 semantics).
  static const int broadcast = 0;

  /// Direct message, legacy deterministic-session seal.
  static const int direct = 1;

  /// Direct message, v2 forward-secret X3DH + chain-ratchet seal.
  static const int directV2 = 2;

  /// Public pre-key announcement (carries escrowPub + epoch, unsealed body).
  static const int preKeyAnnounce = 3;
}

int readInt32be(Uint8List bytes, int at) {
  if (at + 4 > bytes.length) {
    throw const FormatException('int32 out of bounds');
  }
  return ((bytes[at] & 0xFF) << 24) |
      ((bytes[at + 1] & 0xFF) << 16) |
      ((bytes[at + 2] & 0xFF) << 8) |
      (bytes[at + 3] & 0xFF);
}

void writeInt32be(Uint8List bytes, int at, int value) {
  bytes[at] = (value >> 24) & 0xFF;
  bytes[at + 1] = (value >> 16) & 0xFF;
  bytes[at + 2] = (value >> 8) & 0xFF;
  bytes[at + 3] = value & 0xFF;
}
