import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/time_format.dart';
import '../../l10n/app_strings.dart';
import '../../mesh/mesh_service.dart';
import '../../models/peer.dart';
import '../../services/messaging_service.dart';
import '../../storage/local_vault.dart';
import '../../theme/app_palette.dart';
import '../../widgets/avatars.dart';
import 'chat_screen.dart';

/// المواضيع — the scroll of conversations (neighborhood + direct).
class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  @override
  void initState() {
    super.initState();
    _refreshSoon();
  }

  Future<void> _refreshSoon() async {
    final MessagingService messaging = context.read<MessagingService>();
    await messaging.refresh();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final MessagingService messaging = context.watch<MessagingService>();
    final List<ThreadSummary> threads = messaging.threads;

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _refreshSoon,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 96),
          children: <Widget>[
            Text(
              AppStrings.chatsTitle,
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 18),
            if (threads.isEmpty)
              _emptyState(context)
            else
              ...threads.map((ThreadSummary t) => _threadTile(context, t)),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        children: <Widget>[
          const Icon(Icons.local_cafe_outlined,
              size: 56, color: AppPalette.brass),
          const SizedBox(height: 14),
          Text(AppStrings.emptyChats,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            AppStrings.emptyChatsHint,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _threadTile(BuildContext context, ThreadSummary thread) {
    final bool isNeighborhood =
        thread.threadId == MeshService.neighborhoodThread;
    final Peer? peer =
        isNeighborhood ? null : LocalVault.peerById(thread.threadId);
    final String avatarLabel = peer?.displayName ?? AppStrings.appName;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppPalette.lapisMid.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openThread(context, thread, peer),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: <Widget>[
                PeerAvatar(label: avatarLabel),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        thread.title,
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${thread.isOutgoing ? AppStrings.youPrefix : ''}${thread.preview}',
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      TimeFormat.listTime(thread.lastUtcMs),
                      style: const TextStyle(
                          fontSize: 11, color: AppPalette.ivoryDim),
                    ),
                    if (thread.unread > 0) ...<Widget>[
                      const SizedBox(height: 4),
                      Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: AppPalette.turquoise,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${thread.unread}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppPalette.ground,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openThread(BuildContext context, ThreadSummary thread, Peer? peer) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ChatScreen(
        threadId: thread.threadId,
        title: thread.title,
        peer: peer,
      ),
    ));
  }
}
