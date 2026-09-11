import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show SimpleKeyPair;
import 'package:flutter_test/flutter_test.dart';
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

      // Signing both ways.
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

      // A corrupted signature must be rejected.
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
      final ParsedMessageEnvelope? parsed = MessageEnvelopeCodec.parse(
        Uint8List.fromList(env),
      );
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
      expect(SafeInput.sanitizeName('  علي \u0000  '), 'علي');
      expect(SafeInput.sanitizeName(''), 'رفيج');
      final String long = 'م' * 80;
      expect(
        SafeInput.sanitizeName(long).length,
        lessThanOrEqualTo(48 * 2),
      );
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
}