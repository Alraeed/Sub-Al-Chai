import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/time_format.dart';
import '../../l10n/app_strings.dart';
import '../../mesh/mesh_service.dart';
import '../../models/peer.dart';
import '../../theme/app_palette.dart';
import '../../widgets/avatars.dart';
import '../../widgets/mesh_orbit_painter.dart';
import '../chat/chat_screen.dart';
import '../qr/qr_code_screen.dart';
import '../qr/qr_scan_screen.dart';

/// The presence radar — warm lanterns, not a network diagnostic.
class RadarView extends StatefulWidget {
  const RadarView({super.key});

  @override
  State<RadarView> createState() => _RadarViewState();
}

class _RadarViewState extends State<RadarView>
    with SingleTickerProviderStateMixin {
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

  @override
  Widget build(BuildContext context) {
    final MeshService mesh = context.watch<MeshService>();
    final List<Peer> peers = mesh.onlinePeers;

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
            const SizedBox(height: 18),
            _orbitCard(context, mesh, peers),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openMyQr(context),
                    icon: const Icon(Icons.qr_code_2, size: 20),
                    label: const Text(AppStrings.myCard),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _openScanner(context),
                    icon: const Icon(Icons.center_focus_weak, size: 20),
                    label: const Text(AppStrings.scanFriend),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (peers.isEmpty)
              _emptyView(context)
            else
              ...peers.map((Peer p) => _peerTile(context, p)),
          ],
        ),
      ),
    );
  }

  Widget _orbitCard(
    BuildContext context,
    MeshService mesh,
    List<Peer> peers,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppPalette.lapisMid.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppPalette.dividerGold, width: 0.8),
      ),
      child: Column(
        children: <Widget>[
          AspectRatio(
            aspectRatio: 1.1,
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (BuildContext context, Widget? _) {
                return CustomPaint(
                  painter: MeshOrbitPainter(
                    peerCount: peers.length,
                    pulse: _pulse.value,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: mesh.bleOn
                      ? AppPalette.turquoise
                      : AppPalette.pomegranate,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                mesh.bleOn
                    ? AppStrings.meshPulseActive
                    : AppStrings.meshPulseInactive,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(width: 14),
              Text(
                '${peers.length} ${AppStrings.peersOnline}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyView(BuildContext context) {
    return Column(
      children: <Widget>[
        const SizedBox(height: 8),
        Text(
          AppStrings.noNearby,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          AppStrings.emptyChatsHint,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _peerTile(BuildContext context, Peer peer) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppPalette.lapisMid.withValues(alpha: 0.6),
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
                        '${AppStrings.talkTo} · ${TimeFormat.listTime(peer.lastSeenAt.millisecondsSinceEpoch)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chat_bubble_outline,
                  size: 22,
                  color: AppPalette.goldLight.withValues(alpha: 0.9),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

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