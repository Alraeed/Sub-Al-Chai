import 'dart:convert';
import 'dart:typed_data';

/// A verified neighbor in the صب الجاي mesh.
///
/// The long-term identity is a 64-byte public object: 32-byte Ed25519 signing
/// key (authenticates every hello/heartbeat) + 32-byte X25519 key (derives
/// the session secret over GATT). Only the public half ever leaves the device.
class Peer {
  const Peer({
    required this.id,
    required this.displayName,
    required this.signPublicKey,
    required this.dhPublicKey,
    required this.shortId,
    required this.firstSeenAt,
    required this.lastSeenAt,
    this.isOnline = false,
  });

  /// Stable identifier: base64 of signPubKey | dhPubKey.
  final String id;

  /// Display name, sanitized, ≤ 48 chars.
  final String displayName;

  final Uint8List signPublicKey;
  final Uint8List dhPublicKey;

  /// Short stable handle used on the wire protocol (8 bytes, hex).
  final String shortId;

  final DateTime firstSeenAt;
  final DateTime lastSeenAt;
  final bool isOnline;

  /// Very short human-friendly token for pairing abbreviations.
  String get friendlyCode {
    final String idx = shortId;
    return idx.length >= 6 ? idx.substring(idx.length - 6) : idx;
  }

  Peer copyWith({bool? isOnline, DateTime? lastSeenAt}) {
    return Peer(
      id: id,
      displayName: displayName,
      signPublicKey: signPublicKey,
      dhPublicKey: dhPublicKey,
      shortId: shortId,
      firstSeenAt: firstSeenAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      isOnline: isOnline ?? this.isOnline,
    );
  }

  Map<String, Object> toJson() {
    return <String, Object>{
      'id': id,
      'name': displayName,
      'sign': _b64(signPublicKey),
      'dh': _b64(dhPublicKey),
      'short': shortId,
      'first': firstSeenAt.millisecondsSinceEpoch,
      'last': lastSeenAt.millisecondsSinceEpoch,
    };
  }

  static Peer? fromJson(Map<dynamic, dynamic> json) {
    try {
      final String? id = json['id'] as String?;
      final String? name = json['name'] as String?;
      final String? sign = json['sign'] as String?;
      final String? dh = json['dh'] as String?;
      if (id == null ||
          name == null ||
          sign == null ||
          dh == null ||
          name.isEmpty) {
        return null;
      }
      final Uint8List? signBytes = _fromB64(sign);
      final Uint8List? dhBytes = _fromB64(dh);
      if (signBytes == null || dhBytes == null) {
        return null;
      }
      final String short =
          json['short'] as String? ?? _deriveShort(signBytes, dhBytes);
      final int first = json['first'] as int? ?? 0;
      final int last = json['last'] as int? ?? first;
      return Peer(
        id: id,
        displayName: name,
        signPublicKey: signBytes,
        dhPublicKey: dhBytes,
        shortId: short,
        firstSeenAt: DateTime.fromMillisecondsSinceEpoch(first),
        lastSeenAt: DateTime.fromMillisecondsSinceEpoch(last),
      );
    } on Object {
      return null;
    }
  }

  static String _deriveShort(Uint8List sign, Uint8List dh) {
    // Deterministic 16-hex-char handle (8 bytes) from the public material —
    // identical convention to shortToHex in the mesh protocol.
    final Uint8List combined = Uint8List(sign.length + dh.length);
    combined.setAll(0, sign);
    combined.setAll(sign.length, dh);
    final StringBuffer sb = StringBuffer();
    final int n = combined.length > 8 ? 8 : combined.length;
    for (int i = 0; i < n; i++) {
      sb.write(combined[i].toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static String _b64(Uint8List bytes) => base64Encode(bytes);

  static Uint8List? _fromB64(String value) {
    try {
      return Uint8List.fromList(base64Decode(value));
    } on Object {
      return null;
    }
  }
}