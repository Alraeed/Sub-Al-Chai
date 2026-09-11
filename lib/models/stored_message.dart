import 'dart:typed_data';

/// A message stored on this device. Only ciphertext (sealed with the local
/// database key) is ever written to disk.
class StoredMessage {
  const StoredMessage({
    required this.id,
    required this.threadId,
    required this.isOutgoing,
    required this.kind,
    required this.fromShortId,
    required this.toShortId,
    required this.utcMs,
    required this.sealed,
    required this.status,
    this.hops = 0,
  });

  /// Random 16-byte message id, hex-encoded.
  final String id;

  /// Conversation key: a peer id for DMs, or the topic token for broadcasts.
  final String threadId;

  final bool isOutgoing;

  /// 0 = neighborhood broadcast, 1 = direct.
  final int kind;

  /// Sender short id (8 bytes, hex).
  final String fromShortId;

  /// Recipient short id; empty for broadcasts.
  final String toShortId;

  final int utcMs;

  /// base64 of the AES-GCM sealed message (ciphertext only, dbKey protected).
  final String sealed;

  /// sent / delivered / failed / relayed.
  final String status;

  final int hops;

  StoredMessage copyWith({String? status}) {
    return StoredMessage(
      id: id,
      threadId: threadId,
      isOutgoing: isOutgoing,
      kind: kind,
      fromShortId: fromShortId,
      toShortId: toShortId,
      utcMs: utcMs,
      sealed: sealed,
      status: status ?? this.status,
      hops: hops,
    );
  }

  Map<String, Object> toJson() {
    return <String, Object>{
      'id': id,
      'thread': threadId,
      'out': isOutgoing ? 1 : 0,
      'kind': kind,
      'from': fromShortId,
      'to': toShortId,
      'ts': utcMs,
      'sealed': sealed,
      'status': status,
      'hops': hops,
    };
  }

  static StoredMessage? fromJson(Map<dynamic, dynamic> json) {
    try {
      final String? id = json['id'] as String?;
      final String? thread = json['thread'] as String?;
      final int? out = json['out'] as int?;
      final int? kind = json['kind'] as int?;
      final String? from = json['from'] as String?;
      final String? to = json['to'] as String?;
      final int? ts = json['ts'] as int?;
      final String? sealed = json['sealed'] as String?;
      final String? status = json['status'] as String?;
      if (id == null ||
          thread == null ||
          out == null ||
          kind == null ||
          from == null ||
          to == null ||
          ts == null ||
          sealed == null ||
          status == null) {
        return null;
      }
      return StoredMessage(
        id: id,
        threadId: thread,
        isOutgoing: out == 1,
        kind: kind,
        fromShortId: from,
        toShortId: to,
        utcMs: ts,
        sealed: sealed,
        status: status,
        hops: json['hops'] as int? ?? 0,
      );
    } on Object {
      return null;
    }
  }
}

/// A decrypted, UI-facing snapshot of a message.
class DecryptedMessage {
  const DecryptedMessage({
    required this.id,
    required this.threadId,
    required this.isOutgoing,
    required this.kind,
    required this.fromShortId,
    required this.toShortId,
    required this.utcMs,
    required this.text,
    required this.status,
  });

  final String id;
  final String threadId;
  final bool isOutgoing;
  final int kind;
  final String fromShortId;
  final String toShortId;
  final int utcMs;
  final String text;
  final String status;
}

/// Sensible caps, enforced everywhere (never trust the wire).
abstract final class MessageLimits {
  static const int maxTextBytes = 1024;
  static const int maxDisplayNameBytes = 48;
  static const int maxHops = 3;
  static const int maxAssembledPacketBytes = 8 * 1024;
  static const int maxPeers = 96;
  static const int seenTtlSeconds = 90;
}

String hexEncode(Uint8List bytes) {
  final StringBuffer sb = StringBuffer();
  for (final int b in bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

Uint8List? hexDecode(String hex) {
  final String clean = hex.trim();
  if (clean.isEmpty || clean.length.isOdd) {
    return null;
  }
  try {
    final Uint8List out = Uint8List(clean.length ~/ 2);
    for (int i = 0; i < out.length; i++) {
      out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  } on Object {
    return null;
  }
}