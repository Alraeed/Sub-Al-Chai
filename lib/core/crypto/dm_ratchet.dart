import 'dart:typed_data';

import 'tea_crypto.dart';

/// Pure forward-only walker for the v2 DM symmetric chain.
///
/// Given a chain seed, steps [fromIndex]..[toIndex] and returns:
///  * the message key at [toIndex] (seals/opens that message),
///  * the advanced chain state to persist for the next step,
///  * every intermediate (index → message key) pair, so the caller can keep a
///    bounded skip window and later open out-of-order deliveries.
///
/// All bounds are enforced here; the wire index is treated as hostile.
class DmRatchet {
  DmRatchet._();

  /// Walk depth cap — a single fast-forward may never exceed this.
  static const int maxWalkSteps = TeaCrypto.maxDmChainSteps;

  static Future<DmWalkResult> walk({
    required Uint8List chainKey,
    required int fromIndex,
    required int toIndex,
  }) async {
    if (fromIndex < 0 || toIndex < fromIndex) {
      throw const FormatException('ratchet walk out of order');
    }
    final int span = toIndex - fromIndex;
    if (span > maxWalkSteps) {
      throw const FormatException('ratchet walk too deep');
    }
    final List<DmSkippedKey> intermediates = <DmSkippedKey>[];
    Uint8List ck = Uint8List.fromList(chainKey);
    Uint8List mk = Uint8List(0);
    for (int i = fromIndex; i <= toIndex; i++) {
      final DmRatchetStep step =
          await TeaCrypto.dmRatchetStep(chainKey: ck, step: i);
      mk = step.messageKey;
      if (i < toIndex) {
        // Later (out-of-order) message keys we pass through on the way:
        // remember them so a straggler at index i can still be opened.
        intermediates.add(DmSkippedKey(i, step.messageKey));
      }
      ck = step.nextChainKey;
    }
    return DmWalkResult(mk, ck, intermediates);
  }
}

/// Result of a [DmRatchet.walk].
class DmWalkResult {
  const DmWalkResult(this.messageKey, this.nextChainKey, this.intermediates);

  final Uint8List messageKey;
  final Uint8List nextChainKey;
  final List<DmSkippedKey> intermediates;
}

/// One intermediate message key passed on the way to a later index.
class DmSkippedKey {
  const DmSkippedKey(this.index, this.messageKey);

  final int index;
  final Uint8List messageKey;
}
