import 'dart:convert';
import 'dart:typed_data';

import '../../models/stored_message.dart';

/// Every byte that arrives over Bluetooth is treated as hostile until it
/// passes [SafeInput] checks. On failure the packet is dropped.
abstract final class SafeInput {
  /// Sanitize a peer display name: cap length, strip control chars.
  static String sanitizeName(String raw) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return 'رفيج';
    }
    final List<int> units = trimmed.runes
        .where((int r) => r >= 0x20 && r != 0x7F)
        .toList(growable: false);
    String out = String.fromCharCodes(units).trim();
    final List<int> bytes = utf8.encode(out);
    if (bytes.length > MessageLimits.maxDisplayNameBytes) {
      out = truncateUtf8(out, MessageLimits.maxDisplayNameBytes);
    }
    return out;
  }

  /// Sanitize message text before sealing.
  static String sanitizeText(String raw) {
    final String trimmed = raw.replaceAll('\r\n', '\n').trim();
    if (trimmed.isEmpty) {
      throw const FormatException('empty message');
    }
    final List<int> bytes = utf8.encode(trimmed);
    if (bytes.length > MessageLimits.maxTextBytes) {
      throw const FormatException('message exceeds byte limit');
    }
    return trimmed;
  }

  /// Bounds-check an inbound identity payload before any parsing.
  static bool isReasonableIdentityPayload(Uint8List payload) {
    if (payload.length < (1 + 1 + 1 + 64 + 64)) {
      return false;
    }
    return payload.length <= 512;
  }

  /// Bounds-check a full reassembled message envelope.
  static bool isReasonableMessageEnvelope(Uint8List payload) {
    return payload.length >= 1 + 16 + 1 + 1 + 1 + 8 + 8 + 1 &&
        payload.length <= MessageLimits.maxAssembledPacketBytes;
  }

  /// Whitelist of wire opcodes we know how to handle.
  static bool knowOpcode(int opcode) {
    return opcode == Opcodes.identity ||
        opcode == Opcodes.message ||
        opcode == Opcodes.heartbeat;
  }
}

/// Wire opcodes (whitelist).
abstract final class Opcodes {
  static const int identity = 0x01;
  static const int message = 0x02;
  static const int heartbeat = 0x03;
}

/// Truncate a UTF-8 string to [maxBytes] without splitting a code point.
String truncateUtf8(String value, int maxBytes) {
  final List<int> full = utf8.encode(value);
  if (full.length <= maxBytes) {
    return value;
  }
  List<int> cut = full.sublist(0, maxBytes);
  while (cut.isNotEmpty && !_endsAtBoundary(cut)) {
    cut = cut.sublist(0, cut.length - 1);
  }
  return utf8.decode(cut);
}

/// Whether [bytes] ends exactly on a UTF-8 code-point boundary.
bool _endsAtBoundary(List<int> bytes) {
  int i = bytes.length - 1;
  int continuations = 0;
  while (i >= 0 && (bytes[i] & 0xC0) == 0x80) {
    continuations++;
    i--;
  }
  if (i < 0) {
    return false; // trailing continuation bytes with no lead byte
  }
  final int lead = bytes[i];
  if (lead < 0x80) {
    return true; // ASCII — always a boundary
  }
  final int expected;
  if (lead >= 0xC0 && lead <= 0xDF) {
    expected = 1;
  } else if (lead >= 0xE0 && lead <= 0xEF) {
    expected = 2;
  } else if (lead >= 0xF0 && lead <= 0xF7) {
    expected = 3;
  } else {
    return false;
  }
  return continuations == expected;
}
