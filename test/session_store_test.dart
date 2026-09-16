import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:spill_the_tea/core/crypto/dm_ratchet.dart';
import 'package:spill_the_tea/core/crypto/tea_crypto.dart';
import 'package:spill_the_tea/mesh/session_store.dart';
import 'package:spill_the_tea/storage/local_vault.dart';

/// At-rest guarantees for the v2 DM session store: rotating pre-keys and
/// per-peer ratchet state must round-trip, stay sealed, and disappear
/// completely on wipe.
void main() {
  late Directory dir;

  setUpAll(() {
    dir = Directory.systemTemp.createTempSync('tea_sessions');
    Hive.init(dir.path);
  });

  setUp(() async {
    await LocalVault.open(TeaCrypto.randomBytes(32));
    await DmSessionStore.open();
  });

  tearDown(() async {
    await DmSessionStore.wipe();
    await LocalVault.wipe();
  });

  tearDownAll(() async {
    await Hive.close();
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });
  test('pre-keys rotate, older epochs stay open, history stays capped',
      () async {
    final PreKey first = await DmSessionStore.rotatePreKey();
    expect(first.epoch, 1);
    expect(first.publicKey.length, 32);
    expect(first.seed.length, 32);

    for (int i = 0; i < 6; i++) {
      await DmSessionStore.rotatePreKey();
    }

    final PreKey? current = await DmSessionStore.loadCurrentPreKey();
    expect(current, isNotNull);
    expect(current!.epoch, 7);
    expect(current.publicKey.length, 32);

    final List<PreKey> open = await DmSessionStore.loadOpenPreKeys();
    expect(open.length, DmSessionStore.preKeyHistoryCap + 1);
    expect(await DmSessionStore.preKeyForEpoch(7), isNotNull);
    expect(await DmSessionStore.preKeyForEpoch(6), isNotNull);
    // Epoch 1 has aged out of the bounded history window.
    expect(await DmSessionStore.preKeyForEpoch(1), isNull);
  });

  test('a rotated pre-key is genuinely fresh key material', () async {
    final PreKey a = await DmSessionStore.rotatePreKey();
    final PreKey b = await DmSessionStore.rotatePreKey();
    expect(a.publicKey, isNot(b.publicKey));
    expect(a.seed, isNot(b.seed));
  });

  test('pre-key secrets are sealed on disk, never stored raw', () async {
    final PreKey pk = await DmSessionStore.rotatePreKey();
    final Box<dynamic> box = Hive.box<dynamic>(DmSessionStore.boxName);
    final Map<dynamic, dynamic> raw =
        box.get(DmSessionStore.currentKey) as Map<dynamic, dynamic>;
    final String storedSeed = raw['seed'] as String;

    expect(storedSeed, isNot(base64Encode(pk.seed)));
    // nonce(12) + seed(32) + tag(16) — proof it went through AES-GCM.
    expect(base64Decode(storedSeed).length, 12 + 32 + 16);
  });

  test('outbound and inbound ratchet state round-trip sealed', () async {
    const String peerId = 'peer-round-trip';
    final Uint8List chain = TeaCrypto.randomBytes(32);
    final Uint8List ephPriv = TeaCrypto.randomBytes(32);
    final Uint8List ephPub = TeaCrypto.randomBytes(32);

    await DmSessionStore.saveOutbound(
      peerId,
      OutboundDmState(
        ephemeralPriv: ephPriv,
        ephemeralPub: ephPub,
        theirPreKeyEpoch: 3,
        chainKey: chain,
        nextIndex: 5,
      ),
    );
    final OutboundDmState? out = await DmSessionStore.loadOutbound(peerId);
    expect(out, isNotNull);
    expect(out!.chainKey, chain);
    expect(out.ephemeralPriv, ephPriv);
    expect(out.ephemeralPub, ephPub);
    expect(out.theirPreKeyEpoch, 3);
    expect(out.nextIndex, 5);

    final Uint8List skippedKey = TeaCrypto.randomBytes(32);
    final Uint8List theirEph = TeaCrypto.randomBytes(32);
    await DmSessionStore.saveInbound(
      peerId,
      InboundDmState(
        theirEphPub: theirEph,
        myPreKeyEpoch: 2,
        recvChainKey: chain,
        recvN: 4,
        skipped: <int, Uint8List>{3: skippedKey},
      ),
    );
    final InboundDmState? inb = await DmSessionStore.loadInbound(peerId);
    expect(inb, isNotNull);
    expect(inb!.theirEphPub, theirEph);
    expect(inb.myPreKeyEpoch, 2);
    expect(inb.recvN, 4);
    expect(inb.skipped[3], skippedKey);

    // Advancing past a skipped index drops that key from the window.
    final InboundDmState advanced = inb.advanced(
      chain: TeaCrypto.randomBytes(32),
      next: 5,
      added: const <DmSkippedKey>[],
    );
    expect(advanced.skipped.containsKey(3), isFalse);
    expect(advanced.recvN, 5);
  });
  test('wipe() removes the box and leaves every accessor safe', () async {
    const String peerId = 'peer-wipe';
    await DmSessionStore.rotatePreKey();
    await DmSessionStore.saveOutbound(
      peerId,
      OutboundDmState(
        ephemeralPriv: TeaCrypto.randomBytes(32),
        ephemeralPub: TeaCrypto.randomBytes(32),
        theirPreKeyEpoch: 1,
        chainKey: TeaCrypto.randomBytes(32),
        nextIndex: 0,
      ),
    );
    expect(Hive.isBoxOpen(DmSessionStore.boxName), isTrue);

    await DmSessionStore.wipe();

    expect(DmSessionStore.isOpen, isFalse);
    expect(Hive.isBoxOpen(DmSessionStore.boxName), isFalse);
    expect(await DmSessionStore.loadCurrentPreKey(), isNull);
    expect(await DmSessionStore.loadPreKeyHistory(), isEmpty);
    expect(await DmSessionStore.loadOpenPreKeys(), isEmpty);
    expect(await DmSessionStore.preKeyForEpoch(1), isNull);
    expect(await DmSessionStore.loadOutbound(peerId), isNull);
    expect(await DmSessionStore.loadInbound(peerId), isNull);

    // Writing while closed must be a silent no-op, never a throw.
    await DmSessionStore.saveOutbound(
      peerId,
      OutboundDmState(
        ephemeralPriv: TeaCrypto.randomBytes(32),
        ephemeralPub: TeaCrypto.randomBytes(32),
        theirPreKeyEpoch: 1,
        chainKey: TeaCrypto.randomBytes(32),
        nextIndex: 0,
      ),
    );
    await DmSessionStore.saveInbound(
      peerId,
      InboundDmState(
        theirEphPub: TeaCrypto.randomBytes(32),
        myPreKeyEpoch: 1,
        recvChainKey: TeaCrypto.randomBytes(32),
        recvN: 0,
        skipped: const <int, Uint8List>{},
      ),
    );
    await DmSessionStore.clearOutbound(peerId);
    await DmSessionStore.clearInbound(peerId);

    // Rotating while closed fails loudly so the mesh can fall back to v1.
    await expectLater(
      DmSessionStore.rotatePreKey(),
      throwsA(isA<StateError>()),
    );

    // The store is usable again afterwards (post-erase re-onboarding).
    await DmSessionStore.open();
    expect(DmSessionStore.isOpen, isTrue);
    final PreKey after = await DmSessionStore.rotatePreKey();
    expect(after.epoch, 1);
  });
}
