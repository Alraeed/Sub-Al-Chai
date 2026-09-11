import 'dart:convert';
import 'dart:typed_data';

import '../../models/peer.dart';
import 'sanitizer.dart';

/// The QR pairing payload — contains ONLY public key material.
///
///   `SPTEA:1:<base64url(signPub(32) | dhPub(32))>:<name>`
///
/// Verified with strict parsing; a QR that fails any check is rejected.
abstract final class QrPayload {
  static const String prefix = 'SPTEA:1:';

  static String build({
    required Peer peer,
  }) {
    final Uint8List combined = Uint8List(64);
    combined.setAll(0, peer.signPublicKey);
    combined.setAll(32, peer.dhPublicKey);
    final String b64 = base64UrlEncode(combined);
    return '$prefix$b64:${_sanitizeName(peer.displayName)}';
  }

  static QrIdentity? parse(String raw) {
    final String trimmed = raw.trim();
    if (!trimmed.startsWith(prefix)) {
      return null;
    }
    final String rest = trimmed.substring(prefix.length);
    final int sep = rest.indexOf(':');
    if (sep <= 0) {
      return null;
    }
    final String b64 = rest.substring(0, sep);
    final String name = rest.substring(sep + 1);
    if (b64.length != 88) {
      return null; // 64 bytes → 86-88 chars base64url (no padding)
    }
    final Uint8List? both = _decodeB64(b64);
    if (both == null || both.length != 64) {
      return null;
    }
    final String safeName = SafeInput.sanitizeName(name);
    if (safeName.isEmpty || safeName == 'رفيج') {
      return null;
    }
    return QrIdentity(
      displayName: safeName,
      signPublicKey: both.sublist(0, 32),
      dhPublicKey: both.sublist(32, 64),
    );
  }

  static Uint8List? _decodeB64(String value) {
    try {
      return Uint8List.fromList(base64Url.decode(value));
    } on FormatException {
      return null;
    }
  }

  static String _sanitizeName(String name) {
    final String clean = name.replaceAll(':', ' ').trim();
    return clean.isEmpty ? 'رفيج' : clean;
  }
}

class QrIdentity {
  const QrIdentity({
    required this.displayName,
    required this.signPublicKey,
    required this.dhPublicKey,
  });

  final String displayName;
  final Uint8List signPublicKey;
  final Uint8List dhPublicKey;
}