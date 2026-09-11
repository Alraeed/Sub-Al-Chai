import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_strings.dart';
import '../../mesh/mesh_service.dart';
import '../../services/messaging_service.dart';
import '../../theme/app_palette.dart';
import '../chat/chat_list_screen.dart';
import '../radar/radar_view.dart';
import '../settings/settings_screen.dart';

/// Root shell: الحضور (radar) / المواضيع (chats) / الإعدادات (settings).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  StreamSubscription<MeshUiEvent>? _sub;

  @override
  void initState() {
    super.initState();
    final MeshService mesh = context.read<MeshService>();
    final MessagingService messaging = context.read<MessagingService>();
    // Keep the conversation list fresh whenever a message lands.
    _sub = mesh.events.listen((MeshUiEvent event) {
      if (event.type == 1) {
        unawaited(messaging.refresh());
      }
    });
    unawaited(messaging.refresh());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = <Widget>[
      const RadarView(),
      const ChatListScreen(),
      const SettingsScreen(),
    ];
    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: _teaLanternNav(context),
    );
  }

  Widget _teaLanternNav(BuildContext context) {
    final bool anyOnline = context.watch<MeshService>().onlineCount > 0;
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.lapisMid.withValues(alpha: 0.96),
        border: const Border(
          top: BorderSide(color: AppPalette.dividerGold, width: 0.7),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            _navItem(context, 0, Icons.radar_outlined, Icons.radar,
                AppStrings.nearbyTitle),
            _navItem(
              context,
              1,
              Icons.forum_outlined,
              Icons.forum,
              AppStrings.chatsTitle,
              dot: anyOnline,
            ),
            _navItem(
              context,
              2,
              Icons.settings_outlined,
              Icons.settings,
              AppStrings.settingsTitle,
            ),
          ],
        ),
      ),
    );
  }

  Widget _navItem(
    BuildContext context,
    int index,
    IconData icon,
    IconData activeIcon,
    String label, {
    bool dot = false,
  }) {
    final bool selected = _index == index;
    return InkWell(
      onTap: () => setState(() => _index = index),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Icon(
                  selected ? activeIcon : icon,
                  color: selected ? AppPalette.gold : AppPalette.ivoryDim,
                  size: 24,
                ),
                if (dot && !selected)
                  Positioned(
                    top: -2,
                    left: 12,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppPalette.turquoise,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Parastoo',
                fontSize: 11,
                color: selected ? AppPalette.goldLight : AppPalette.ivoryDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
