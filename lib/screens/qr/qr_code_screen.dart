import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/utils/qr_payload.dart';
import '../../l10n/app_strings.dart';
import '../../mesh/mesh_service.dart';
import '../../models/peer.dart';
import '../../services/app_bootstrap.dart';
import '../../theme/app_palette.dart';
import '../../widgets/avatars.dart';
import '../onboarding/onboarding_screen.dart' show copyToClipboard;

/// بطاقتي — my public identity card as a QR code (public keys only).
class QrCodeScreen extends StatelessWidget {
  const QrCodeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppBootstrap bootstrap = context.watch<AppBootstrap>();
    final MeshService mesh = context.watch<MeshService>();
    final String name = bootstrap.displayName ?? AppStrings.appName;

    final Peer? self = mesh.selfPeer;
    final String payload = self == null ? '' : QrPayload.build(peer: self);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.myCard)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
        child: Column(
          children: <Widget>[
            PeerAvatar(label: name, radius: 26),
            const SizedBox(height: 10),
            Text(name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${AppStrings.friendlyCode}: ${mesh.myFriendlyCode}',
              style: const TextStyle(color: AppPalette.turquoise, fontSize: 13),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppPalette.lapisMid.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppPalette.dividerGold, width: 0.8),
              ),
              child: QrImageView(
                data: payload,
                version: QrVersions.auto,
                size: 260,
                backgroundColor: AppPalette.lapisMid,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: AppPalette.gold,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: AppPalette.goldLight,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              AppStrings.myCardHint,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: payload.isEmpty
                  ? null
                  : () => copyToClipboard(context, payload),
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('انسخ بطاقتي'),
            ),
          ],
        ),
      ),
    );
  }
}