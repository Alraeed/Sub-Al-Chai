import 'dart:collection';
import 'dart:typed_data';

import '../core/utils/safe_log.dart';
import 'ble_constants.dart';

/// Frame format on the wire:
///   [0x53 | 0x54 | 0x21 | seq(1) | fragIndex(1) | fragCount(1) | payload…]
/// where payload is a slice of the reassembled logical packet.
///
/// A logical packet is at most [maxPacketBytes]; a message envelope inside it
/// is validated again by [MessageEnvelope].
class Fragmenter {
  /// Writable bytes available per frame (already MTU-aware).
  final int maxFramePayload;

  const Fragmenter(this.maxFramePayload);

  static const int frameHeaderLength = 2 + 1 + 1 + 1 + 1;

  /// Split a logical packet into frames for one link.
  List<Uint8List> framePacket(int seq, Uint8List packet) {
    if (packet.length > MessageEnvelope.maxPacketBytes) {
      throw ArgumentError('packet too large: ${packet.length}');
    }
    if (packet.isEmpty) {
      return <Uint8List>[];
    }
    final int usable = maxFramePayload <= 0 ? 1 : maxFramePayload;
    final int count = 1 + ((packet.length - 1) ~/ usable);
    if (count > 255) {
      throw ArgumentError('too many fragments');
    }
    final List<Uint8List> frames = <Uint8List>[];
    for (int index = 0; index < count; index++) {
      final int start = index * usable;
      final int end =
          (start + usable > packet.length) ? packet.length : start + usable;
      final Uint8List chunk = Uint8List.sublistView(packet, start, end);
      final Uint8List frame = Uint8List(frameHeaderLength + chunk.length);
      frame[0] = BleConstants.magicByte0;
      frame[1] = BleConstants.magicByte1;
      frame[2] = BleConstants.frameOpData;
      frame[3] = seq & 0xFF;
      frame[4] = index & 0xFF;
      frame[5] = count & 0xFF;
      frame.setAll(frameHeaderLength, chunk);
      frames.add(frame);
    }
    return frames;
  }
}

/// Reassembles frames per (linkKey, seq) with a TTL and hard size cap.
class FrameAssembler {
  FrameAssembler();

  final LinkedHashMap<String, _Assembly> _pending =
      LinkedHashMap<String, _Assembly>();

  final Map<String, DateTime> _seen = <String, DateTime>{};

  /// Feed a raw frame; if it completes a packet, the packet bytes are
  /// returned (and the assembly purged). All bounds are enforced here.
  Uint8List? push(Uint8List frame) {
    if (frame.length < 6 ||
        frame[0] != BleConstants.magicByte0 ||
        frame[1] != BleConstants.magicByte1 ||
        frame[2] != BleConstants.frameOpData) {
      SafeLog.info('assemble', 'dropping malformed frame (${frame.length})');
      return null;
    }
    final int seq = frame[3];
    final int index = frame[4];
    final int count = frame[5];
    if (count == 0 || index >= count) {
      SafeLog.info('assemble', 'dropping frame with bad frag math');
      return null;
    }
    final Uint8List chunk = Uint8List.sublistView(
      frame,
      Fragmenter.frameHeaderLength,
    );
    if (chunk.length > MessageEnvelope.maxFrameChunkBytes) {
      SafeLog.info('assemble', 'chunk too large');
      return null;
    }

    final DateTime now = DateTime.now();
    _purge(now);
    if (count == 1) {
      if (chunk.isEmpty || chunk.length > MessageEnvelope.maxPacketBytes) {
        return null;
      }
      return Uint8List.fromList(chunk);
    }

    final String key = '$seq:$count';
    _Assembly? assembly = _pending[key];
    if (assembly == null) {
      if (_pending.length >= BleConstants.maxAssemblerEntries) {
        SafeLog.info('assemble', 'assembler saturated; dropping earliest');
        _pending.remove(_pending.keys.first);
      }
      assembly = _Assembly(count);
      _pending[key] = assembly;
    }
    assembly.put(index, chunk);
    if (assembly.isComplete) {
      final Uint8List end = assembly.finish();
      _pending.remove(key);
      return end;
    }
    return null;
  }

  /// Record a message id we have already seen (for relay dedup).
  bool markSeen(String dedupKey, DateTime now) {
    final DateTime? existing = _seen[dedupKey];
    if (existing != null && now.difference(existing).inSeconds < 90) {
      return false;
    }
    _seen[dedupKey] = now;
    if (_seen.length > 512) {
      _seen.remove(_seen.keys.first);
    }
    return true;
  }

  void _purge(DateTime now) {
    _pending.removeWhere(
      (String key, _Assembly a) =>
          now.difference(a.createdAt).compareTo(BleConstants.assemblerTtl) > 0,
    );
  }
}

class _Assembly {
  _Assembly(this.total)
      : _chunks = List<Uint8List?>.filled(total, null),
        _filled = 0,
        createdAt = DateTime.now();

  final int total;
  final List<Uint8List?> _chunks;
  int _filled;
  final DateTime createdAt;

  bool get isComplete => _filled == total;

  void put(int index, Uint8List chunk) {
    if (_chunks[index] == null) {
      _chunks[index] = Uint8List.fromList(chunk);
      _filled++;
    }
  }

  Uint8List finish() {
    int size = 0;
    for (final Uint8List? c in _chunks) {
      if (c != null) {
        size += c.length;
      }
    }
    if (size > MessageEnvelope.maxPacketBytes) {
      throw StateError('assembled packet over cap');
    }
    final Uint8List out = Uint8List(size);
    int at = 0;
    for (final Uint8List? c in _chunks) {
      if (c != null) {
        out.setAll(at, c);
        at += c.length;
      }
    }
    return out;
  }
}

/// Logical packet caps shared by sender and receiver — sanity enforced on
/// both ends so a hostile peer cannot allocate unbounded buffers.
abstract final class MessageEnvelope {
  static const int maxPacketBytes = 8 * 1024;
  static const int maxFrameChunkBytes = 512;
}
