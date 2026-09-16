import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/time_format.dart';
import '../../l10n/app_strings.dart';
import '../../mesh/mesh_service.dart';
import '../../models/peer.dart';
import '../../models/stored_message.dart';
import '../../storage/local_vault.dart';
import '../../theme/app_palette.dart';
import '../../widgets/avatars.dart';
import '../../widgets/mesh_orbit_painter.dart';
import '../chat/chat_screen.dart';
import '../qr/qr_code_screen.dart';
import '../qr/qr_scan_screen.dart';
import 'radar_model.dart';

/// الجوار — who is reachable right now.
///
/// The map shows link state and history, never location: bearings are assigned
/// from each peer's own id, so lanterns hold their place while the neighborhood
/// churns, and the reach ring states the protocol's hop bound rather than
/// pretending to measure distance.
class RadarView extends StatefulWidget {
  const RadarView({super.key});

  @override
  State<RadarView> createState() => _RadarViewState();
}

class _RadarViewState extends State<RadarView>
    with SingleTickerProviderStateMixin {
  /// How many remembered peers we are willing to list below the map.
  static const int _maxAway = 12;

  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
      lowerBound: 0,
      upperBound: 1,
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  /// Lanterns: live links from the mesh, then peers we know but cannot reach.
  List<RadarPeer> _lanterns(MeshService mesh) {
    final List<Peer> online = mesh.onlinePeers;
    final List<RadarPeer> out = <RadarPeer>[
      for (final Peer peer in online) RadarPeer(peer: peer, linked: true),
    ];
    if (!LocalVault.isOpen) {
      // Mid-erase or failed bootstrap: we have nothing remembered to show.
      return out;
    }
    final Set<String> linkedIds = online.map((Peer p) => p.id).toSet();
    int added = 0;
    for (final Peer peer in LocalVault.allPeers()) {
      if (added >= _maxAway) {
        break;
      }
      if (linkedIds.contains(peer.id)) {
        continue;
      }
      out.add(RadarPeer(peer: peer, linked: false));
      added++;
    }
    return out;
  }

  RadarSnapshot _snapshot(MeshService mesh) {
    return RadarSnapshot(
      bleOn: mesh.bleOn,
      scanning: mesh.isScanning,
      advertising: mesh.isAdvertising,
      relayEnabled: mesh.relayEnabled,
      peers: _lanterns(mesh),
      maxHops: MessageLimits.maxHops,
    );
  }

  @override
  Widget build(BuildContext context) {
    final MeshService mesh = context.watch<MeshService>();
    final RadarSnapshot snapshot = _snapshot(mesh);
    final String? error = mesh.lastError;

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: mesh.refreshPresence,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 96),
          children: <Widget>[
            Text(
              AppStrings.nearbyTitle,
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 4),
            Text(
              AppStrings.nearbySubtitle,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            _mapCard(context, snapshot),
            const SizedBox(height: 18),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openMyQr(context),
                    icon: const Icon(Icons.qr_code_2, size: 20),
                    label: Text(AppStrings.myCard),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _openScanner(context),
                    icon: const Icon(Icons.center_focus_weak, size: 20),
                    label: Text(AppStrings.scanFriend),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            if (!snapshot.bleOn)
              _radioOffCard(context, mesh)
            else if (error != null)
              _errorBanner(context, mesh)
            else if (!snapshot.anyPeer)
              _emptyView(context, snapshot)
            else
              ..._lanternSections(context, snapshot),
          ],
        ),
      ),
    );
  }
// ------------------------------------------------------------------ map

  Widget _mapCard(BuildContext context, RadarSnapshot snapshot) {
    // Only rebuild with the pulse while the radio is actually awake.
    final Widget map = snapshot.bleOn
        ? AnimatedBuilder(
            animation: _pulse,
            builder: (BuildContext context, Widget? _) {
              return CustomPaint(
                painter:
                    MeshOrbitPainter(snapshot: snapshot, pulse: _pulse.value),
              );
            },
          )
        : CustomPaint(
            painter: MeshOrbitPainter(snapshot: snapshot, pulse: 0),
          );

    final int hidden = RadarLayout.hiddenCount(snapshot.peers.length);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: AppPalette.lapisMid.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppPalette.dividerGold, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            AppStrings.mapTitle,
            style: const TextStyle(
              color: AppPalette.goldLight,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          AspectRatio(
            aspectRatio: 1.05,
            child: Semantics(
              image: true,
              label: describeRadar(snapshot),
              child: map,
            ),
          ),
          const SizedBox(height: 8),
          // Says plainly what the map is: link state, not whereabouts.
          Text(
            AppStrings.mapCaption,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            runSpacing: 8,
            children: <Widget>[
              _legendDot(
                label: AppStrings.me,
                color: AppPalette.goldLight,
              ),
              _legendDot(
                label: '${snapshot.linked.length} ${AppStrings.linkedPeers}',
                color: AppPalette.turquoise,
              ),
              _legendDot(
                label: '${snapshot.away.length} ${AppStrings.awayPeers}',
                color: AppPalette.brass,
                hollow: true,
              ),
              if (snapshot.reachHops > 0)
                _legendDot(
                  label:
                      '${AppStrings.reachTitle} ${snapshot.reachHops} ${hopsLabel(snapshot.reachHops)}',
                  color: AppPalette.gold,
                  hollow: true,
                ),
              if (hidden > 0)
                _legendDot(
                  label: '+$hidden ${AppStrings.hiddenPeers}',
                  color: AppPalette.ivoryDim,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _statusDot(snapshot.bleOn),
              const SizedBox(width: 7),
              Text(
                snapshot.relayEnabled
                    ? AppStrings.relayActive
                    : AppStrings.relayPaused,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (snapshot.scanning) ...<Widget>[
                const SizedBox(width: 14),
                Text(
                  AppStrings.scanningNow,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendDot({
    required String label,
    required Color color,
    bool hollow = false,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hollow ? Colors.transparent : color,
            border: hollow ? Border.all(color: color, width: 1.3) : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 11.5, color: AppPalette.ivoryDim),
        ),
      ],
    );
  }

  Widget _statusDot(bool on) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? AppPalette.turquoise : AppPalette.pomegranate,
      ),
    );
  }

  // ------------------------------------------------------------- states

  /// Bluetooth off: the map is asleep, so say so plainly and offer the retry.
  Widget _radioOffCard(BuildContext context, MeshService mesh) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppPalette.lapisMid.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppPalette.pomegranate.withValues(alpha: 0.55),
          width: 0.9,
        ),
      ),
      child: Column(
        children: <Widget>[
          const Icon(
            Icons.bluetooth_disabled,
            size: 40,
            color: AppPalette.pomegranate,
          ),
          const SizedBox(height: 12),
          Text(
            AppStrings.errorBluetoothOff,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            AppStrings.radioOffHint,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: () => mesh.refreshPresence(),
            icon: const Icon(Icons.refresh, size: 20),
            label: Text(AppStrings.tryAgain),
          ),
        ],
      ),
    );
  }

  Widget _errorBanner(BuildContext context, MeshService mesh) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppPalette.pomegranate.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppPalette.pomegranate.withValues(alpha: 0.5),
          width: 0.8,
        ),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.error_outline,
            size: 20,
            color: AppPalette.pomegranate,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              mesh.lastError ?? AppStrings.errorGeneric,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          TextButton(
            onPressed: () => mesh.refreshPresence(),
            child: Text(AppStrings.tryAgain),
          ),
        ],
      ),
    );
  }

  Widget _emptyView(BuildContext context, RadarSnapshot snapshot) {
    final bool listening = snapshot.scanning;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        children: <Widget>[
          Icon(
            listening ? Icons.radar : Icons.local_cafe_outlined,
            size: 44,
            color: AppPalette.brass,
          ),
          const SizedBox(height: 14),
          Text(
            AppStrings.noNearby,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            listening ? AppStrings.scanningAlone : AppStrings.aloneHint,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
// ------------------------------------------------------------ lanterns

  List<Widget> _lanternSections(BuildContext context, RadarSnapshot snapshot) {
    final List<Widget> out = <Widget>[];
    final List<RadarPeer> linked = snapshot.linked;
    final List<RadarPeer> away = snapshot.away;

    out.add(_sectionHeader(context, AppStrings.linkedPeers, linked.length));
    if (linked.isEmpty) {
      out.add(_hint(context, AppStrings.aloneHint));
    } else {
      out.addAll(linked.map((RadarPeer l) => _peerTile(context, l)));
    }

    if (away.isNotEmpty) {
      out.add(const SizedBox(height: 10));
      out.add(_sectionHeader(context, AppStrings.awayPeers, away.length));
      out.addAll(away.map((RadarPeer l) => _peerTile(context, l)));
    }
    return out;
  }

  Widget _sectionHeader(BuildContext context, String title, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 2),
      child: Row(
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              color: AppPalette.goldLight,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: AppPalette.lapisHigh,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppPalette.dividerGold, width: 0.6),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 11.5,
                color: AppPalette.ivoryDim,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hint(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }

  Widget _peerTile(BuildContext context, RadarPeer lantern) {
    final Peer peer = lantern.peer;
    final bool linked = lantern.linked;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppPalette.lapisMid.withValues(alpha: linked ? 0.6 : 0.35),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openPeerChat(context, peer),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: <Widget>[
                PeerAvatar(label: peer.displayName),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        peer.displayName,
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        linked
                            ? '${AppStrings.talkTo} · ${peer.friendlyCode}'
                            : '${TimeFormat.listTime(lantern.lastSeenAtMs)}'
                                ' · ${peer.friendlyCode}',
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  linked ? Icons.chat_bubble_outline : Icons.history_toggle_off,
                  size: linked ? 22 : 20,
                  color: linked
                      ? AppPalette.goldLight.withValues(alpha: 0.9)
                      : AppPalette.ivoryDim,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------- navigation

  void _openMyQr(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const QrCodeScreen(),
    ));
  }

  void _openScanner(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const QrScanScreen(),
    ));
  }

  void _openPeerChat(BuildContext context, Peer peer) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ChatScreen(
        threadId: peer.id,
        title: peer.displayName,
        peer: peer,
      ),
    ));
  }
}
