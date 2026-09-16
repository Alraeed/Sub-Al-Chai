import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:spill_the_tea/l10n/app_strings.dart';
import 'package:spill_the_tea/models/peer.dart';
import 'package:spill_the_tea/screens/radar/radar_model.dart';

Peer _peer(String id, {DateTime? lastSeen}) {
  return Peer(
    id: id,
    displayName: 'صاحب $id',
    signPublicKey: Uint8List(32),
    dhPublicKey: Uint8List(32),
    shortId: 'aabbccdd11223344',
    firstSeenAt: DateTime.fromMillisecondsSinceEpoch(1000),
    lastSeenAt: lastSeen ?? DateTime.fromMillisecondsSinceEpoch(2000),
  );
}

RadarPeer _radar(Peer peer, {required bool linked}) =>
    RadarPeer(peer: peer, linked: linked);

RadarSnapshot _snap({
  bool bleOn = true,
  bool relay = true,
  List<RadarPeer>? peers,
  int maxHops = 3,
}) {
  return RadarSnapshot(
    bleOn: bleOn,
    scanning: true,
    advertising: true,
    relayEnabled: relay,
    peers: peers ?? <RadarPeer>[],
    maxHops: maxHops,
  );
}

void main() {
  group('RadarLayout', () {
    test('bearings are stable while the peer list churns', () {
      final List<RadarPeer> peers = <RadarPeer>[
        for (int i = 0; i < 5; i++) _radar(_peer('p$i'), linked: false),
      ];
      final Map<String, double> first = <String, double>{
        for (final RadarSlot s in RadarLayout.arrange(peers))
          s.peer.id: s.angle,
      };

      // A new peer arrives; the existing five must keep their bearings.
      final List<RadarPeer> churned = <RadarPeer>[
        ...peers,
        _radar(_peer('p-new'), linked: false),
      ];
      final Map<String, double> second = <String, double>{
        for (final RadarSlot s in RadarLayout.arrange(churned))
          s.peer.id: s.angle,
      };
      for (final MapEntry<String, double> e in first.entries) {
        expect(second[e.key], e.value);
      }
    });

    test('linked peers claim their bearing before away peers', () {
      // Two peers hash to the same preferred slot; the linked one wins.
      final RadarPeer away = _radar(_peer('away-same-slot'), linked: false);
      final RadarPeer linked = _radar(_peer('linked-same-slot'), linked: true);
      final List<RadarSlot> slots =
          RadarLayout.arrange(<RadarPeer>[away, linked]);
      expect(slots.length, 2);
      final RadarSlot linkedSlot =
          slots.firstWhere((RadarSlot s) => s.peer.id == linked.id);
      expect(linkedSlot.innerRing, isTrue);
      final RadarSlot awaySlot =
          slots.firstWhere((RadarSlot s) => s.peer.id == away.id);
      expect(awaySlot.innerRing, isFalse);
      // Both got a slot (collision resolves, never silent loss).
      expect(slots.map((RadarSlot s) => s.peer.id).toSet().length, 2);
    });

    test('the map never draws more lanterns than is legible', () {
      final List<RadarPeer> many = <RadarPeer>[
        for (int i = 0; i < 40; i++) _radar(_peer('p$i'), linked: i.isEven),
      ];
      expect(RadarLayout.arrange(many).length, RadarLayout.maxLanterns);
      expect(RadarLayout.hiddenCount(40), 40 - RadarLayout.maxLanterns);
      expect(RadarLayout.hiddenCount(5), 0);
    });
  });

  group('RadarSnapshot', () {
    test('reach is 0 with no one to hand a message to', () {
      expect(_snap().reachHops, 0);
    });

    test('reach is 1 when we are the only hop (relay off)', () {
      final RadarSnapshot s = _snap(
        relay: false,
        peers: <RadarPeer>[_radar(_peer('a'), linked: true)],
      );
      expect(s.reachHops, 1);
    });

    test('reach follows the protocol cap across relays', () {
      final RadarSnapshot s = _snap(
        relay: true,
        peers: <RadarPeer>[_radar(_peer('a'), linked: true)],
      );
      expect(s.reachHops, 3);
    });

    test('reach ignores away-only memories', () {
      final RadarSnapshot s = _snap(
        relay: true,
        peers: <RadarPeer>[_radar(_peer('a'), linked: false)],
      );
      expect(s.reachHops, 0);
    });
  });

  group('hopsLabel', () {
    test('Arabic plurals for one, two, many', () {
      expect(hopsLabel(1), AppStrings.hopSingular);
      expect(hopsLabel(2), AppStrings.hopDual);
      expect(hopsLabel(3), AppStrings.hopPlural);
    });
  });

  group('describeRadar', () {
    test('radio off', () {
      expect(
          describeRadar(_snap(bleOn: false)), AppStrings.radarSummaryRadioOff);
    });

    test('alone', () {
      expect(describeRadar(_snap()), AppStrings.radarSummaryAlone);
    });

    test('with a linked peer and relay, the summary counts both rings', () {
      final String summary = describeRadar(
        _snap(peers: <RadarPeer>[_radar(_peer('a'), linked: true)]),
      );
      expect(summary, contains('1 ${AppStrings.linkedPeers}'));
      expect(summary, contains(AppStrings.relayActive));
      expect(summary, contains('${AppStrings.reachTitle} 3'));
    });
  });
}
