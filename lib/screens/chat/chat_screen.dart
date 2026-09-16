import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/time_format.dart';
import '../../l10n/app_strings.dart';
import '../../mesh/mesh_service.dart';
import '../../models/peer.dart';
import '../../models/stored_message.dart';
import '../../services/messaging_service.dart';
import '../../storage/local_vault.dart';
import '../../theme/app_palette.dart';
import '../../widgets/avatars.dart';

/// Conversation screen for one thread: neighborhood broadcast or DM.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.threadId,
    required this.title,
    this.peer,
  });

  final String threadId;
  final String title;
  final Peer? peer;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  List<DecryptedMessage> _messages = <DecryptedMessage>[];
  StreamSubscription<MeshUiEvent>? _sub;
  bool _sending = false;

  bool get _isNeighborhood => widget.threadId == MeshService.neighborhoodThread;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = context.read<MeshService>().events.listen((MeshUiEvent event) {
      if (event.type == 1 && event.threadId == widget.threadId) {
        unawaited(_load());
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final List<DecryptedMessage> msgs =
        await context.read<MessagingService>().loadThread(widget.threadId);
    if (!mounted) {
      return;
    }
    setState(() => _messages = msgs);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) {
      return;
    }
    Future<void>(() {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    if (_sending) {
      return;
    }
    final String text = _input.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.errorNoMessage)),
      );
      return;
    }
    setState(() => _sending = true);
    final MeshService mesh = context.read<MeshService>();
    if (_isNeighborhood) {
      await mesh.sendBroadcast(text);
    } else {
      final Peer? peer = widget.peer;
      if (peer == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.peerLeft)),
        );
        setState(() => _sending = false);
        return;
      }
      await mesh.sendDirect(text, peer);
    }
    if (!mounted) {
      return;
    }
    _input.clear();
    setState(() => _sending = false);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (!_isNeighborhood) PeerAvatar(label: widget.title, radius: 15),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                widget.title,
                style: const TextStyle(fontSize: 17),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: _messages.isEmpty
                ? _emptyConversation(context)
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    itemCount: _messages.length,
                    itemBuilder: (BuildContext context, int index) {
                      return _bubble(context, _messages[index]);
                    },
                  ),
          ),
          _composer(context),
        ],
      ),
    );
  }

  Widget _emptyConversation(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          _isNeighborhood
              ? AppStrings.neighborhoodTopicHint
              : AppStrings.dmTopicHint,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }

  Widget _bubble(BuildContext context, DecryptedMessage m) {
    final bool mine = m.isOutgoing;
    return Align(
      alignment: mine ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: min(MediaQuery.of(context).size.width * 0.78, 440),
        ),
        decoration: BoxDecoration(
          color: mine ? AppPalette.lapisHigh : AppPalette.lapisMid,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 4 : 16),
            bottomRight: Radius.circular(mine ? 16 : 4),
          ),
          border: Border.all(color: AppPalette.dividerGold, width: 0.6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (_isNeighborhood && !mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  _nameFor(m.fromShortId),
                  style: const TextStyle(
                      fontSize: 11, color: AppPalette.turquoise),
                ),
              ),
            Text(
              m.text,
              style: const TextStyle(
                fontFamily: 'Parastoo',
                fontSize: 16,
                height: 1.45,
                color: AppPalette.ivory,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  TimeFormat.chatTime(m.utcMs),
                  style: const TextStyle(
                      fontSize: 10.5, color: AppPalette.ivoryDim),
                ),
                if (mine) ...<Widget>[
                  const SizedBox(width: 5),
                  Icon(
                    _statusIcon(m.status),
                    size: 13,
                    color: m.status == 'failed'
                        ? AppPalette.pomegranate
                        : AppPalette.gold,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _nameFor(String shortId) {
    // Broadcast sender name lookup — shortId is public, never sensitive.
    String label = shortId;
    try {
      for (final Peer p in LocalVault.allPeers()) {
        if (p.shortId == shortId || p.friendlyCode == shortId) {
          label = p.displayName;
          break;
        }
      }
    } on Object {
      // keep the shortId fallback
    }
    return label;
  }

  IconData _statusIcon(String status) {
    if (status == 'failed') {
      return Icons.error_outline;
    }
    if (status == 'delivered' || status == 'sent') {
      return Icons.done_all;
    }
    return Icons.schedule;
  }

  Widget _composer(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        color: AppPalette.lapisMid.withValues(alpha: 0.9),
        child: Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration:
                    InputDecoration(hintText: AppStrings.chatHint),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppPalette.ground,
                      ),
                    )
                  : const Icon(Icons.send_rounded, size: 20),
              style: IconButton.styleFrom(
                backgroundColor: AppPalette.gold,
                foregroundColor: AppPalette.ground,
                disabledBackgroundColor:
                    AppPalette.brass.withValues(alpha: 0.5),
                padding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
