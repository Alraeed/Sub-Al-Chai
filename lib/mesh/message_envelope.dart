import 'dart:typed_data';

import '../core/utils/sanitizer.dart';
import '../models/stored_message.dart';
import 'fragmenter.dart';
import 'protocol.dart';

/// End-to-end sealed message envelope carried inside a logical packet.
///
/// layout: op(1) msgId(16) kind(1) hop(1) from(8) to(8) ts(8) body(n)
/// `body` is nonce|ciphertext|mac sealed with the recipient session key,
/// so relay nodes can carry it without ever reading it.
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
  }) {
    final Uint8List from = shortWire(fromShortId);
    final Uint8List to = shortWire(toShortId);
    final int total = overhead + sealedBody.length;
    if (total > MessageEnvelope.maxPacketBytes) {
      throw ArgumentError('envelope too large: $total');
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
    final Uint8List sealedBody = Uint8List.fromList(
      Uint8List.sublistView(packet, at),
    );
    final int mac = 16;
    if (sealedBody.length < 12 + mac) {
      throw const FormatException('sealed body too small');
    }
    return ParsedMessageEnvelope(
      msgId: msgId,
      kind: kind,
      hopLimit: hopLimit,
      fromShortId: shortToHex(from),
      toShortId: shortToHex(to),
      utcMs: utcMs,
      sealedBody: sealedBody,
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
  });

  final Uint8List msgId;
  final int kind;
  final int hopLimit;
  final String fromShortId;
  final String toShortId;
  final int utcMs;
  final Uint8List sealedBody;

  /// Stable dedup key for relay flood protection (16-byte msg id, hex).
  String get dedupKey {
    final StringBuffer sb = StringBuffer();
    for (final int b in msgId) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}