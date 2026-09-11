import 'dart:async';

import 'package:flutter/foundation.dart';

import '../l10n/app_strings.dart';
import '../mesh/mesh_service.dart';
import '../models/peer.dart';
import '../models/stored_message.dart';
import '../storage/local_vault.dart';

/// Watches mesh events and builds the conversation list (threads + previews)
/// by decrypting only the latest message of each thread on demand.
class MessagingService extends ChangeNotifier {
  MessagingService._();

  static MessagingService? _instance;

  static MessagingService getInstance() {
    return _instance ??= MessagingService._();
  }

  StreamSubscription<MeshUiEvent>? _subscription;

  List<ThreadSummary> _threads = <ThreadSummary>[];

  List<ThreadSummary> get threads => List<ThreadSummary>.unmodifiable(_threads);

  void attach(MeshService mesh) {
    _subscription ??= mesh.events.listen((MeshUiEvent event) {
      unawaited(refresh());
    });
  }

  Future<void> refresh() async {
    final List<StoredMessage> all = <StoredMessage>[];
    for (final Peer peer in LocalVault.allPeers()) {
      all.addAll(LocalVault.messagesFor(peer.id));
    }
    all.addAll(LocalVault.messagesFor(MeshService.neighborhoodThread));

    final Map<String, List<StoredMessage>> byThread = <String, List<StoredMessage>>{};
    for (final StoredMessage m in all) {
      byThread.putIfAbsent(m.threadId, () => <StoredMessage>[]).add(m);
    }

    final List<ThreadSummary> out = <ThreadSummary>[];
    for (final MapEntry<String, List<StoredMessage>> entry in byThread.entries) {
      final List<StoredMessage> msgs = entry.value;
      msgs.sort((StoredMessage a, StoredMessage b) => a.utcMs.compareTo(b.utcMs));
      final StoredMessage latest = msgs.last;
      final String? preview = await LocalVault.openText(latest);
      final int unread = msgs
          .where((StoredMessage m) => !m.isOutgoing && m.status != 'read')
          .length;
      out.add(
        ThreadSummary(
          threadId: entry.key,
          title: entry.key == MeshService.neighborhoodThread
              ? '${AppStrings.appName} (${AppStrings.nearbyTitle})'
              : (LocalVault.peerById(entry.key)?.displayName ?? 'رفيج'),
          preview: preview ?? '…',
          lastUtcMs: latest.utcMs,
          isOutgoing: latest.isOutgoing,
          unread: unread,
        ),
      );
    }
    out.sort((ThreadSummary a, ThreadSummary b) => b.lastUtcMs.compareTo(a.lastUtcMs));
    _threads = out;
    notifyListeners();
  }

  /// Full decrypted conversation for one thread.
  Future<List<DecryptedMessage>> loadThread(String threadId) async {
    final List<StoredMessage> msgs = LocalVault.messagesFor(threadId);
    msgs.sort((StoredMessage a, StoredMessage b) => a.utcMs.compareTo(b.utcMs));
    final List<DecryptedMessage> out = <DecryptedMessage>[];
    for (final StoredMessage m in msgs) {
      final String? text = await LocalVault.openText(m);
      if (text == null) {
        continue; // corrupted / undecryptable entries are skipped silently
      }
      out.add(
        DecryptedMessage(
          id: m.id,
          threadId: m.threadId,
          isOutgoing: m.isOutgoing,
          kind: m.kind,
          fromShortId: m.fromShortId,
          toShortId: m.toShortId,
          utcMs: m.utcMs,
          text: text,
          status: m.status,
        ),
      );
    }
    return out;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    super.dispose();
  }
}

class ThreadSummary {
  const ThreadSummary({
    required this.threadId,
    required this.title,
    required this.preview,
    required this.lastUtcMs,
    required this.isOutgoing,
    required this.unread,
  });

  final String threadId;
  final String title;
  final String preview;
  final int lastUtcMs;
  final bool isOutgoing;
  final int unread;
}