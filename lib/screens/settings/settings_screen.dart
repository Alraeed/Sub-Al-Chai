import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_strings.dart';
import '../../mesh/mesh_service.dart';
import '../../services/app_bootstrap.dart';
import '../../theme/app_palette.dart';
import '../../widgets/avatars.dart';

/// الإعدادات — identity, security posture, relay, destructive actions.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppBootstrap bootstrap = context.watch<AppBootstrap>();
    final MeshService mesh = context.watch<MeshService>();
    final String name = bootstrap.displayName ?? AppStrings.appName;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 96),
        children: <Widget>[
          Text(
            AppStrings.settingsTitle,
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 18),
          _identityCard(context, name, mesh),
          const SizedBox(height: 18),
          _section(context, AppStrings.securitySection, <Widget>[
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                AppStrings.securityHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ]),
          const SizedBox(height: 12),
          _section(context, AppStrings.relayMode, <Widget>[
            SwitchListTile(
              value: mesh.relayEnabled,
              onChanged: mesh.setRelayEnabled,
              title: Text(mesh.relayEnabled ? AppStrings.relayOn : AppStrings.relayOff),
              activeTrackColor: AppPalette.turquoise,
              inactiveTrackColor: AppPalette.brass.withValues(alpha: 0.4),
              secondary: const Icon(Icons.sync_alt, color: AppPalette.gold),
            ),
          ]),
          const SizedBox(height: 12),
          _section(context, AppStrings.dangerZone, <Widget>[
            ListTile(
              leading: const Icon(Icons.delete_sweep_outlined, color: AppPalette.pomegranate),
              title: const Text(
                AppStrings.eraseAll,
                style: TextStyle(color: AppPalette.pomegranate),
              ),
              onTap: () => _confirmErase(context),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _identityCard(BuildContext context, String name, MeshService mesh) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.lapisMid.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppPalette.dividerGold, width: 0.8),
      ),
      child: Row(
        children: <Widget>[
          PeerAvatar(label: name, radius: 26),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(name, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  '${AppStrings.friendlyCode}: ${mesh.myFriendlyCode}',
                  style: const TextStyle(color: AppPalette.turquoise, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.lapisMid.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.dividerGold, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Text(
              title,
              style: const TextStyle(
                color: AppPalette.goldLight,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Future<void> _confirmErase(BuildContext context) async {
    final AppBootstrap bootstrap = context.read<AppBootstrap>();
    final bool? proceed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppPalette.lapisHigh,
          title: const Text(AppStrings.eraseAll),
          content: const Text(AppStrings.eraseConfirm),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(AppStrings.cancel),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(
                AppStrings.eraseAll,
                style: TextStyle(color: AppPalette.pomegranate),
              ),
            ),
          ],
        );
      },
    );
    if (proceed != true) {
      return;
    }
    await bootstrap.eraseEverything();
    if (context.mounted) {
      // AppGate in app.dart will switch to onboarding automatically.
      Navigator.of(context).maybePop();
    }
  }
}