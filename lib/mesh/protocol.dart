import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../core/crypto/tea_crypto.dart';
import '../core/utils/safe_log.dart';
import '../core/utils/sanitizer.dart';

/// Signed identity hello — the on-wire “business card”.
///
/// layout: op(1) ver(1) nameLen(1) name signPub(32) dhPub(32) ts(8) sig(64)
/// Everything before `sig` is Ed25519-signed with `signPub`.
abstract final class TeaPackets {
  static const int identityBase = 1 + 1 + 1 + 32 + 32 + 8 + 64;
}

/// Build this device's hello packet.
Future<Uint8List> buildHello({
  required SimpleKeyPair signKeyPair,
  required Uint8List signPublicKey,
  required Uint8List dhPublicKey,
  required String displayName,
}) async {
  final Uint8List name = utf8.encode(truncateUtf8(displayName, 48));
  final Uint8List packet = Uint8List(TeaPackets.identityBase + name.length);

  int at = 0;
  packet[at++] = Opcodes.identity;
  packet[at++] = 0x01; // protocol version
  packet[at++] = name.length & 0xFF;
  packet.setAll(at, name);
  at += name.length;
  packet.setAll(at, signPublicKey);
  at += 32;
  packet.setAll(at, dhPublicKey);
  at += 32;
  writeInt64be(packet, at, DateTime.now().millisecondsSinceEpoch);
  at += 8;

  final Uint8List toSign = Uint8List.sublistView(packet, 0, at);
  final Signature signature = await Ed25519().sign(toSign, keyPair: signKeyPair);
  packet.setAll(at, signature.bytes);
  return packet;
}

/// Parse + verify a hello packet; returns the identity on success.
///
/// Throws [FormatException] on malformed input or a bad signature.
Future<HelloIdentity?> parseHello(Uint8List packet) async {
  if (packet.length < TeaPackets.identityBase ||
      packet.length > TeaPackets.identityBase + 48) {
    SafeLog.info('protocol', 'hello length out of range: ${packet.length}');
    throw const FormatException('identity length out of range');
  }
  int at = 0;
  if (packet[at++] != Opcodes.identity) {
    throw const FormatException('not an identity packet');
  }
  if (packet[at++] != 0x01) {
    throw const FormatException('unsupported protocol version');
  }
  final int nameLen = packet[at++];
  if (nameLen > 48 || at + nameLen + 32 + 32 + 8 + 64 != packet.length) {
    throw const FormatException('identity layout mismatch');
  }
  final Uint8List nameBytes = Uint8List.fromList(
    Uint8List.sublistView(packet, at, at + nameLen),
  );
  at += nameLen;
  final Uint8List signPublicKey = Uint8List.fromList(
    Uint8List.sublistView(packet, at, at + 32),
  );
  at += 32;
  final Uint8List dhPublicKey = Uint8List.fromList(
    Uint8List.sublistView(packet, at, at + 32),
  );
  at += 32;
  final int tsMs = readInt64be(packet, at);
  at += 8;
  final int now = DateTime.now().millisecondsSinceEpoch;
  if (tsMs <= 0 || tsMs > now + 60000) {
    throw const FormatException('identity timestamp out of range');
  }
  final Uint8List signature = Uint8List.fromList(
    Uint8List.sublistView(packet, at, at + 64),
  );

  final Uint8List toVerify = Uint8List.sublistView(packet, 0, at);
  final bool ok = await TeaCrypto.verifySignature(
    message: toVerify,
    signature: signature,
    publicKey: signPublicKey,
  );
  if (!ok) {
    SafeLog.info('protocol', 'hello signature rejected');
    throw const FormatException('identity signature verification failed');
  }

  final String name;
  try {
    name = utf8.decode(nameBytes, allowMalformed: false);
  } on FormatException {
    throw const FormatException('name is not valid UTF-8');
  }
  return HelloIdentity(
    displayName: SafeInput.sanitizeName(name),
    signPublicKey: signPublicKey,
    dhPublicKey: dhPublicKey,
    tsMs: tsMs,
  );
}

class HelloIdentity {
  const HelloIdentity({
    required this.displayName,
    required this.signPublicKey,
    required this.dhPublicKey,
    required this.tsMs,
  });

  final String displayName;
  final Uint8List signPublicKey;
  final Uint8List dhPublicKey;
  final int tsMs;
}

// ------------------------------------------------------------------ Utils

int readInt64be(Uint8List bytes, int at) {
  if (at + 8 > bytes.length) {
    throw const FormatException('int64 out of bounds');
  }
  int value = 0;
  for (int i = 0; i < 8; i++) {
    value = value * 256 + (bytes[at + i] & 0xFF);
  }
  return value;
}

void writeInt64be(Uint8List bytes, int at, int value) {
  for (int i = 0; i < 8; i++) {
    bytes[at + 7 - i] = value & 0xFF;
    value = value >> 8;
  }
}

/// 8 raw-byte short id helpers (hex string <-> wire bytes).
String shortToHex(Uint8List bytes) {
  final int n = bytes.length > 8 ? 8 : bytes.length;
  final StringBuffer sb = StringBuffer();
  for (int i = 0; i < n; i++) {
    sb.write(bytes[i].toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

String last8Hex(String hex) {
  return hex.length >= 8 ? hex.substring(hex.length - 8) : hex.padLeft(8, '0');
}