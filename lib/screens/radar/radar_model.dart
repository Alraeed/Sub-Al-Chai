import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;

import '../../l10n/app_strings.dart';
import '../../models/peer.dart';

/// One lantern on the neighborhood map.
///
/// A peer is either **linked** (we hold a live GATT link to it right now) or
/// **away** (we met it before and know when we last saw it). Nothing here is a
/// place: the mesh has no way to know where anybody is, so the map only ever
/// claims link state and history.
class RadarPeer {
  const RadarPeer({required this.peer, required this.linked});

  /// The stored identity behind this lantern, carried along so the UI can open
  /// the conversation without a second lookup.
  final Peer peer;

  /// Whether a live link exists right now. Decided by the caller from the live
  /// link tables — never from the peer's cached `isOnline` flag, which stays
  /// true in the vault across restarts.
  final bool linked;

  String get id => peer.id;

  String get name => peer.displayName;

  /// Six-character handle used in pairing copy.
  String get code => peer.friendlyCode;

  int get lastSeenAtMs => peer.lastSeenAt.millisecondsSinceEpoch;

  @override
  bool operator ==(Object other) {
    return other is RadarPeer &&
        other.linked == linked &&
        other.id == id &&
        other.name == name &&
        other.code == code &&
        other.lastSeenAtMs == lastSeenAtMs;
  }

  @override
  int get hashCode => Object.hash(id, name, code, linked, lastSeenAtMs);
}

/// Everything the map is allowed to claim at one moment.
class RadarSnapshot {
  const RadarSnapshot({
    required this.bleOn,
    required this.scanning,
    required this.advertising,
    required this.relayEnabled,
    required this.peers,
    this.maxHops = 3,
  });

  /// The radio is powered on and we can actually reach someone.
  final bool bleOn;

  /// Discovery is running.
  final bool scanning;

  /// We are advertising, so others can find us.
  final bool advertising;

  /// We carry neighbors' broadcasts onward.
  final bool relayEnabled;

  /// Linked peers first, then peers we know but cannot reach right now.
  final List<RadarPeer> peers;

  /// Protocol cap on broadcast hops (see `MessageLimits.maxHops`).
  final int maxHops;

  List<RadarPeer> get linked =>
      peers.where((RadarPeer p) => p.linked).toList(growable: false);

  List<RadarPeer> get away =>
      peers.where((RadarPeer p) => !p.linked).toList(growable: false);

  bool get hasLinked => peers.any((RadarPeer p) => p.linked);

  bool get anyPeer => peers.isNotEmpty;

  /// Potential broadcast reach, in hops.
  ///
  /// 0 when there is nobody to hand a message to, 1 when we are the only hop
  /// (relaying off means we do not carry it onward), otherwise the protocol
  /// cap. This is a bound, not a measurement.
  int get reachHops => hasLinked ? (relayEnabled ? maxHops : 1) : 0;

  @override
  bool operator ==(Object other) {
    return other is RadarSnapshot &&
        other.bleOn == bleOn &&
        other.scanning == scanning &&
        other.advertising == advertising &&
        other.relayEnabled == relayEnabled &&
        other.maxHops == maxHops &&
        listEquals(other.peers, peers);
  }

  @override
  int get hashCode => Object.hash(
        bleOn,
        scanning,
        advertising,
        relayEnabled,
        maxHops,
        Object.hashAll(peers),
      );
}

/// One placed lantern: a stable bearing plus which ring it belongs on.
class RadarSlot {
  const RadarSlot({
    required this.peer,
    required this.angle,
    required this.innerRing,
  });

  final RadarPeer peer;

  /// Bearing in radians: 0 points straight up, growing clockwise.
  final double angle;

  /// Live links sit on the inner ring; peers we cannot reach sit further out.
  final bool innerRing;
}

/// Placement rules for the map, kept free of painting so they can be tested.
abstract final class RadarLayout {
  /// Fixed number of bearings a lantern can occupy.
  static const int slotCount = 16;

  /// Never draw more lanterns than this — past it the map stops being legible,
  /// and the extra peers are reported in words instead.
  static const int maxLanterns = 12;

  /// Assigns each peer a bearing.
  ///
  /// The bearing comes from the peer's own id, so a lantern keeps its place as
  /// other peers arrive and leave: the map never reshuffles itself just because
  /// the neighborhood churned. Linked peers claim their bearing first, so a
  /// peer we can actually talk to never loses its slot to one we only recall.
  static List<RadarSlot> arrange(List<RadarPeer> peers) {
    final List<RadarPeer> ordered = <RadarPeer>[
      ...peers.where((RadarPeer p) => p.linked),
      ...peers.where((RadarPeer p) => !p.linked),
    ];
    final Set<int> taken = <int>{};
    final List<RadarSlot> out = <RadarSlot>[];
    for (final RadarPeer peer in ordered) {
      if (out.length >= maxLanterns) {
        break;
      }
      final int preferred = bearingIndex(peer.id);
      int slot = preferred;
      for (int probe = 1; probe <= slotCount && taken.contains(slot); probe++) {
        slot = (preferred + probe) % slotCount;
      }
      if (taken.contains(slot)) {
        continue; // every bearing is taken
      }
      taken.add(slot);
      out.add(
        RadarSlot(
          peer: peer,
          angle: -math.pi / 2 + slot * (2 * math.pi / slotCount),
          innerRing: peer.linked,
        ),
      );
    }
    return out;
  }

  /// Deterministic bearing index for one peer id.
  static int bearingIndex(String id) {
    int hash = 0;
    for (final int unit in id.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash % slotCount;
  }

  /// Peers the map cannot show for lack of room.
  static int hiddenCount(int peerCount) {
    return peerCount > maxLanterns ? peerCount - maxLanterns : 0;
  }
}

/// Arabic plural for a small hop count: قفزة / قفزتين / قفزات.
String hopsLabel(int hops) {
  if (hops == 1) {
    return AppStrings.hopSingular;
  }
  if (hops == 2) {
    return AppStrings.hopDual;
  }
  return AppStrings.hopPlural;
}

/// One-line, screen-reader summary of the map — built only from real state.
String describeRadar(RadarSnapshot snapshot) {
  if (!snapshot.bleOn) {
    return AppStrings.radarSummaryRadioOff;
  }
  if (!snapshot.anyPeer) {
    return AppStrings.radarSummaryAlone;
  }
  final StringBuffer out = StringBuffer(AppStrings.radarSummaryPrefix);
  out.write(' ${snapshot.linked.length} ${AppStrings.linkedPeers}');
  final int away = snapshot.away.length;
  if (away > 0) {
    out.write('، $away ${AppStrings.awayPeers}');
  }
  out.write(
    '، ${snapshot.relayEnabled ? AppStrings.relayActive : AppStrings.relayPaused}',
  );
  if (snapshot.reachHops > 0) {
    out.write(
      '، ${AppStrings.reachTitle} ${snapshot.reachHops} '
      '${hopsLabel(snapshot.reachHops)}',
    );
  }
  return out.toString();
}
