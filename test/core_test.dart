import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show SimpleKeyPair;
import 'package:flutter_test/flutter_test.dart';
import 'package:spill_the_tea/core/crypto/dm_ratchet.dart';
import 'package:spill_the_tea/core/crypto/tea_crypto.dart';
import 'package:spill_the_tea/core/utils/qr_payload.dart';
import 'package:spill_the_tea/core/utils/sanitizer.dart';
import 'package:spill_the_tea/mesh/message_envelope.dart';
import 'package:spill_the_tea/mesh/protocol.dart';
import 'package:spill_the_tea/models/peer.dart';

void main() {
  group('TeaCrypto', () {
    test('identity + session is deterministic on both sides', () async {
      final SimpleKeyPair aSign = await TeaCrypto.newSignKeyPair();
      final SimpleKeyPair aDh = await TeaCrypto.newDhKeyPair();
      final SimpleKeyPair bDh = await TeaCrypto.newDhKeyPair();

      final Uint8List aSignPub = await TeaCrypto.publicKeyBytes(aSign);
      final Uint8List aDhPub = await TeaCrypto.publicKeyBytes(aDh);
      final Uint8List bDhPub = await TeaCrypto.publicKeyBytes(bDh);

      final Uint8List kA = await TeaCrypto.deriveSessionKey(
        myDhPair: aDh,
        theirDhPub: bDhPub,
        myDhPub: aDhPub,
      );
      final Uint8List kB = await TeaCrypto.deriveSessionKey(
        myDhPair: bDh,
        theirDhPub: aDhPub,
        myDhPub: bDhPub,
      );

      expect(kA, kB);
      expect(kA.length, 32);

      final Uint8List sig = await TeaCrypto.sign(
        keyPair: aSign,
        message: aDhPub,
      );
      expect(
        await TeaCrypto.verifySignature(
          message: aDhPub,
          signature: sig,
          publicKey: aSignPub,
        ),
        isTrue,
      );
    });

    test('sealing round-trips and tamper is detected', () async {
      final Uint8List key = TeaCrypto.randomBytes(32);
      final Uint8List sealed = await TeaCrypto.sealText(key: key, text: 'هاي');
      expect(sealed.length, greaterThan(16 + 16));

      final String? opened = await TeaCrypto.openText(key: key, sealed: sealed);
      expect(opened, 'هاي');

      final Uint8List tampered = Uint8List.fromList(sealed);
      tampered[tampered.length ~/ 2] ^= 0x01;
      expect(await TeaCrypto.openText(key: key, sealed: tampered), isNull);
    });
  });

  group('Hello packets', () {
    test('build + parse verifies identity', () async {
      final SimpleKeyPair sign = await TeaCrypto.newSignKeyPair();
      final SimpleKeyPair dh = await TeaCrypto.newDhKeyPair();
      final Uint8List signPub = await TeaCrypto.publicKeyBytes(sign);
      final Uint8List dhPub = await TeaCrypto.publicKeyBytes(dh);

      final Uint8List hello = await buildHello(
        signKeyPair: sign,
        signPublicKey: signPub,
        dhPublicKey: dhPub,
        displayName: 'أبو الجاي',
      );

      final HelloIdentity? parsed = await parseHello(hello);
      expect(parsed, isNotNull);
      expect(parsed!.displayName, 'أبو الجاي');
      expect(parsed.dhPublicKey, dhPub);

      final Uint8List bad = Uint8List.fromList(hello);
      bad[bad.length - 1] ^= 0x40;
      await expectLater(parseHello(bad), throwsFormatException);
    });
  });

  group('Message envelopes', () {
    test('build + parse + tamper detection', () {
      final List<int> env = MessageEnvelopeCodec.build(
        msgId: TeaCrypto.randomBytes(16),
        kind: 0,
        hopLimit: 3,
        fromShortId: 'aabbccdd11223344',
        toShortId: '',
        utcMs: DateTime.now().millisecondsSinceEpoch,
        sealedBody: Uint8List.fromList(List<int>.generate(40, (int i) => i)),
      );
      final ParsedMessageEnvelope? parsed =
          MessageEnvelopeCodec.parse(Uint8List.fromList(env));
      expect(parsed, isNotNull);
      expect(parsed!.kind, 0);
      expect(parsed.fromShortId, 'aabbccdd11223344');
      expect(parsed.sealedBody.length, 40);

      final Uint8List hostile = Uint8List.fromList(env);
      hostile[0] = 0x07; // unknown opcode
      expect(MessageEnvelopeCodec.parse(hostile), isNull);
    });
  });

  group('Sanitizer + QR', () {
    test('display names are bounded and cleaned', () {
      final String long = 'م' * 80;
      expect(SafeInput.sanitizeName(long).length, lessThanOrEqualTo(96));
    });

    test('qr payload round-trips public keys only', () async {
      final SimpleKeyPair sign = await TeaCrypto.newSignKeyPair();
      final SimpleKeyPair dh = await TeaCrypto.newDhKeyPair();
      final Uint8List signPub = await TeaCrypto.publicKeyBytes(sign);
      final Uint8List dhPub = await TeaCrypto.publicKeyBytes(dh);
      final Peer peer = Peer(
        id: 'test-peer',
        displayName: 'حسن',
        signPublicKey: signPub,
        dhPublicKey: dhPub,
        shortId: '1234abcd',
        firstSeenAt: DateTime.now(),
        lastSeenAt: DateTime.now(),
      );

      final String payload = QrPayload.build(peer: peer);
      expect(payload.startsWith('SPTEA:1:'), isTrue);
      final QrIdentity? parsed = QrPayload.parse(payload);
      expect(parsed, isNotNull);
      expect(parsed!.displayName, 'حسن');
      expect(parsed.dhPublicKey, dhPub);
      expect(parsed.signPublicKey, signPub);

      expect(QrPayload.parse('garbage qr'), isNull);
      expect(QrPayload.parse('SPTEA:1:broken'), isNull);
    });
  });

  group('V2 DM ratchet', () {
    test('both sides derive the same root and direction chains', () async {
      final SimpleKeyPair aStatic = await TeaCrypto.newDhKeyPair();
      final SimpleKeyPair bStatic = await TeaCrypto.newDhKeyPair();
      final SimpleKeyPair bPre = await TeaCrypto.newEphemeralDhPair();
      final SimpleKeyPair aEph = await TeaCrypto.newEphemeralDhPair();
      final Uint8List aStaticPub = await TeaCrypto.publicKeyBytes(aStatic);
      final Uint8List bStaticPub = await TeaCrypto.publicKeyBytes(bStatic);
      final Uint8List bPrePub = await TeaCrypto.publicKeyBytes(bPre);
      final Uint8List aEphPub = await TeaCrypto.publicKeyBytes(aEph);

      // Sender uses static + its one-time ephemeral; receiver uses static +
      // its pre-key. The X3DH DH set is symmetric, so roots must converge.
      final Uint8List rootA = await TeaCrypto.deriveDmRoot(
        myStaticPair: aStatic,
        myEphemeralPair: aEph,
        theirPreKeyPub: bPrePub,
        theirStaticPub: bStaticPub,
      );
      final Uint8List rootB = await TeaCrypto.deriveDmRoot(
        myStaticPair: bStatic,
        myEphemeralPair: bPre,
        theirPreKeyPub: aEphPub,
        theirStaticPub: aStaticPub,
      );
      expect(rootA, rootB);

      final Uint8List chainA =
          await TeaCrypto.dmDirectionChain(root: rootA, initiator: true);
      final Uint8List chainB =
          await TeaCrypto.dmDirectionChain(root: rootB, initiator: true);
      expect(chainA, chainB);

      // The other direction must never match the initiating chain.
      final Uint8List resp =
          await TeaCrypto.dmDirectionChain(root: rootA, initiator: false);
      expect(chainA == resp, isFalse);
    });

    test('chain steps forward one-way with distinct keys', () async {
      final SimpleKeyPair aStatic = await TeaCrypto.newDhKeyPair();
      final SimpleKeyPair bStatic = await TeaCrypto.newDhKeyPair();
      final SimpleKeyPair bPre = await TeaCrypto.newEphemeralDhPair();
      final SimpleKeyPair aEph = await TeaCrypto.newEphemeralDhPair();

      final Uint8List root = await TeaCrypto.deriveDmRoot(
        myStaticPair: aStatic,
        myEphemeralPair: aEph,
        theirPreKeyPub: await TeaCrypto.publicKeyBytes(bPre),
        theirStaticPub: await TeaCrypto.publicKeyBytes(bStatic),
      );
      final Uint8List chain =
          await TeaCrypto.dmDirectionChain(root: root, initiator: true);
      final DmRatchetStep s0 =
          await TeaCrypto.dmRatchetStep(chainKey: chain, step: 0);
      final DmRatchetStep s1 =
          await TeaCrypto.dmRatchetStep(chainKey: s0.nextChainKey, step: 1);
      final DmRatchetStep s2 =
          await TeaCrypto.dmRatchetStep(chainKey: s1.nextChainKey, step: 2);

      expect(s0.messageKey.length, 32);
      expect(s0.messageKey == s1.messageKey, isFalse);
      expect(s1.messageKey == s2.messageKey, isFalse);

      // A message sealed at index 1 is undecryptable with neighbour keys.
      final Uint8List sealed1 =
          await TeaCrypto.sealText(key: s1.messageKey, text: 'one');
      expect(await TeaCrypto.openText(key: s0.messageKey, sealed: sealed1),
          isNull);
      expect(await TeaCrypto.openText(key: s2.messageKey, sealed: sealed1),
          isNull);
      expect(
          await TeaCrypto.openText(key: s1.messageKey, sealed: sealed1), 'one');
    });

    test('walk returns intermediates for out-of-order delivery', () async {
      final SimpleKeyPair aStatic = await TeaCrypto.newDhKeyPair();
      final SimpleKeyPair bStatic = await TeaCrypto.newDhKeyPair();
      final SimpleKeyPair bPre = await TeaCrypto.newEphemeralDhPair();
      final SimpleKeyPair aEph = await TeaCrypto.newEphemeralDhPair();

      final Uint8List root = await TeaCrypto.deriveDmRoot(
        myStaticPair: aStatic,
        myEphemeralPair: aEph,
        theirPreKeyPub: await TeaCrypto.publicKeyBytes(bPre),
        theirStaticPub: await TeaCrypto.publicKeyBytes(bStatic),
      );
      final Uint8List chain =
          await TeaCrypto.dmDirectionChain(root: root, initiator: true);

      // Fast-forward straight to index 2 — keys 0 and 1 must be retained.
      final DmWalkResult walk =
          await DmRatchet.walk(chainKey: chain, fromIndex: 0, toIndex: 2);
      expect(walk.intermediates.length, 2);
      final Uint8List mk0 = walk.intermediates[0].messageKey;
      final Uint8List mk1 = walk.intermediates[1].messageKey;

      final Uint8List sealed0 =
          await TeaCrypto.sealText(key: mk0, text: 'zero');
      final Uint8List sealed1 = await TeaCrypto.sealText(key: mk1, text: 'one');
      final Uint8List sealed2 =
          await TeaCrypto.sealText(key: walk.messageKey, text: 'two');

      // Deliver in scrambled order.
      expect(await TeaCrypto.openText(key: walk.messageKey, sealed: sealed2),
          'two');
      expect(await TeaCrypto.openText(key: mk1, sealed: sealed1), 'one');
      expect(await TeaCrypto.openText(key: mk0, sealed: sealed0), 'zero');
    });

    test('forward secrecy: long-term keys alone cannot open a captured DM',
        () async {
      final SimpleKeyPair aStatic = await TeaCrypto.newDhKeyPair();
      final SimpleKeyPair bStatic = await TeaCrypto.newDhKeyPair();
      final SimpleKeyPair bPre = await TeaCrypto.newEphemeralDhPair();
      final SimpleKeyPair aEph = await TeaCrypto.newEphemeralDhPair();
      final Uint8List aStaticPub = await TeaCrypto.publicKeyBytes(aStatic);
      final Uint8List bStaticPub = await TeaCrypto.publicKeyBytes(bStatic);
      final Uint8List bPrePub = await TeaCrypto.publicKeyBytes(bPre);
      final Uint8List aEphPub = await TeaCrypto.publicKeyBytes(aEph);

      // Honest seal, then honest open by the real receiver.
      final Uint8List root = await TeaCrypto.deriveDmRoot(
        myStaticPair: aStatic,
        myEphemeralPair: aEph,
        theirPreKeyPub: bPrePub,
        theirStaticPub: bStaticPub,
      );
      final Uint8List chain =
          await TeaCrypto.dmDirectionChain(root: root, initiator: true);
      final Uint8List mk0 =
          (await TeaCrypto.dmRatchetStep(chainKey: chain, step: 0)).messageKey;
      final Uint8List sealed =
          await TeaCrypto.sealText(key: mk0, text: 'سرّ كامل');

      final Uint8List rootReceiver = await TeaCrypto.deriveDmRoot(
        myStaticPair: bStatic,
        myEphemeralPair: bPre,
        theirPreKeyPub: aEphPub,
        theirStaticPub: aStaticPub,
      );
      final Uint8List chainReceiver =
          await TeaCrypto.dmDirectionChain(root: rootReceiver, initiator: true);
      final Uint8List mk0Receiver =
          (await TeaCrypto.dmRatchetStep(chainKey: chainReceiver, step: 0))
              .messageKey;
      expect(await TeaCrypto.openText(key: mk0Receiver, sealed: sealed),
          'سرّ كامل');

      // Attacker has BOTH long-term private keys + the captured public header
      // but NOT the deleted one-time ephemeral private, so any ephemeral it
      // can invent derives a different root and the AEAD tag rejects it.
      final SimpleKeyPair evilEph = await TeaCrypto.newEphemeralDhPair();
      final Uint8List rootEvil = await TeaCrypto.deriveDmRoot(
        myStaticPair: aStatic,
        myEphemeralPair: evilEph,
        theirPreKeyPub: bPrePub,
        theirStaticPub: bStaticPub,
      );
      final Uint8List chainEvil =
          await TeaCrypto.dmDirectionChain(root: rootEvil, initiator: true);
      final Uint8List evilKey =
          (await TeaCrypto.dmRatchetStep(chainKey: chainEvil, step: 0))
              .messageKey;
      expect(await TeaCrypto.openText(key: evilKey, sealed: sealed), isNull);

      // Rotation: once the epoch-1 pre-key private is deleted, the *current*
      // pre-key alone cannot open the old capture either.
      final SimpleKeyPair bPre2 = await TeaCrypto.newEphemeralDhPair();
      final Uint8List rootRotated = await TeaCrypto.deriveDmRoot(
        myStaticPair: bStatic,
        myEphemeralPair: bPre2,
        theirPreKeyPub: aEphPub,
        theirStaticPub: aStaticPub,
      );
      final Uint8List chainRotated =
          await TeaCrypto.dmDirectionChain(root: rootRotated, initiator: true);
      final Uint8List rotatedKey =
          (await TeaCrypto.dmRatchetStep(chainKey: chainRotated, step: 0))
              .messageKey;
      expect(await TeaCrypto.openText(key: rotatedKey, sealed: sealed), isNull);
    });

    // @@v2@@
  });

  group('Peer registry hardening', () {
    test('serialization round-trips a verified peer', () {
      final Peer peer = Peer(
        id: 'peer-a',
        displayName: 'أبو الجاي',
        signPublicKey: Uint8List(32),
        dhPublicKey: Uint8List(32),
        shortId: 'aabbccdd11223344',
        firstSeenAt: DateTime.fromMillisecondsSinceEpoch(1000),
        lastSeenAt: DateTime.fromMillisecondsSinceEpoch(2000),
        preKeyPublic: Uint8List(32),
        preKeyEpoch: 4,
      );

      final Peer? back = Peer.fromJson(peer.toJson());
      expect(back, isNotNull);
      expect(back!.id, 'peer-a');
      expect(back.displayName, 'أبو الجاي');
      expect(back.signPublicKey, Uint8List(32));
      expect(back.dhPublicKey, Uint8List(32));
      expect(back.preKeyEpoch, 4);
    });

    test('malformed key material is rejected outright', () {
      final Map<String, Object> valid = <String, Object>{
        'id': 'peer-b',
        'name': 'حسن',
        'sign': base64Encode(Uint8List(32)),
        'dh': base64Encode(Uint8List(32)),
        'short': 'aabbccdd11223344',
        'first': 1,
        'last': 2,
      };
      expect(Peer.fromJson(valid), isNotNull);

      // Short DH key — this used to reach X25519 and throw mid-send.
      expect(
        Peer.fromJson(<String, Object>{
          ...valid,
          'dh': base64Encode(Uint8List(5)),
        }),
        isNull,
      );
      // Oversized signing key.
      expect(
        Peer.fromJson(<String, Object>{
          ...valid,
          'sign': base64Encode(Uint8List(64)),
        }),
        isNull,
      );
      // Undecodable base64.
      expect(Peer.fromJson(<String, Object>{...valid, 'dh': 'not base64!!'}),
          isNull);
      // Missing identity fields stay rejected too.
      expect(Peer.fromJson(<String, Object>{'id': 'peer-c'}), isNull);
    });

    test('a malformed pre-key is dropped without losing the peer', () {
      final Map<String, Object> json = <String, Object>{
        'id': 'peer-d',
        'name': 'زميل',
        'sign': base64Encode(Uint8List(32)),
        'dh': base64Encode(Uint8List(32)),
        'short': 'aabbccdd11223344',
        'first': 1,
        'last': 2,
        'pre': base64Encode(Uint8List(9)),
        'preEpoch': 7,
      };

      final Peer? peer = Peer.fromJson(json);
      expect(peer, isNotNull);
      expect(peer!.preKeyPublic, isNull);
      expect(peer.preKeyEpoch, 0);
      // …so the send path falls back to the legacy sealed session.
    });
  });
}
