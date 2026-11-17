import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import '../../auth/application/auth_providers.dart';
import '../data/chat_repository.dart';
import '../domain/chat_message.dart';
import '../domain/conversation.dart';

/// Bumped on every live change in my chats; screens listen and reload.
class ChatInbox extends Notifier<int> {
  Timer? _debounce;

  @override
  int build() {
    final repo = ref.watch(chatRepositoryProvider);
    final channel = repo.watchInbox(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), () => state++);
    });
    ref.onDispose(() {
      _debounce?.cancel();
      unawaited(repo.stop(channel).catchError((_) => 'error'));
    });
    return 0;
  }
}

final chatInboxProvider = NotifierProvider<ChatInbox, int>(ChatInbox.new);

/// My chats, newest first. New messages are marked "delivered" (✓✓ grey)
/// as soon as they reach this list.
final conversationsProvider = FutureProvider<List<Conversation>>((ref) async {
  ref.watch(chatInboxProvider);
  final repo = ref.watch(chatRepositoryProvider);
  final list = await repo.listConversations();
  for (final c in list.where((c) => c.unreadCount > 0)) {
    unawaited(repo.markDelivered(c.id).catchError((_) {}));
  }
  return list;
});

/// Total unread messages (badge on the Chats button).
final unreadChatsProvider = Provider<int>((ref) {
  final list = ref.watch(conversationsProvider).value ?? const [];
  return list.where((c) => !c.muted).fold(0, (sum, c) => sum + c.unreadCount);
});

/// Who is online right now (profile ids).
class OnlinePeople extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    final me = ref.watch(myProfileProvider).value;
    if (me == null) return const {};
    final repo = ref.watch(chatRepositoryProvider);
    final channel = repo.presenceChannel(me.id, (ids) => state = ids);
    ref.onDispose(
      () => unawaited(repo.stop(channel).catchError((_) => 'error')),
    );
    return const {};
  }
}

final onlinePeopleProvider = NotifierProvider<OnlinePeople, Set<String>>(
  OnlinePeople.new,
);

/// Messages of one chat, newest first, with paging and live updates.
class ChatState {
  const ChatState({
    this.messages = const [],
    this.hasMore = true,
    this.loadingMore = false,
  });

  final List<ChatMessage> messages;
  final bool hasMore;
  final bool loadingMore;

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? hasMore,
    bool? loadingMore,
  }) => ChatState(
    messages: messages ?? this.messages,
    hasMore: hasMore ?? this.hasMore,
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

class ChatController extends AsyncNotifier<ChatState> {
  ChatController(this.conversationId);

  final String conversationId;

  ChatRepository get _repo => ref.read(chatRepositoryProvider);

  @override
  Future<ChatState> build() async {
    final repo = ref.watch(chatRepositoryProvider);
    // Reload when something changes in my chats.
    ref.listen(chatInboxProvider, (_, _) => unawaited(refresh()));
    final messages = await repo.fetchMessages(conversationId);
    _markSeenIfNew(messages);
    return ChatState(
      messages: messages,
      hasMore: messages.length == ChatRepository.pageSize,
    );
  }

  /// Newest message from someone else that I already marked as seen.
  DateTime? _seenUpTo;

  /// Marks the chat seen only when a message from someone else arrived
  /// since the last time. Marking seen writes to the database, which sends
  /// a live update, which refreshes this chat: calling it on every refresh
  /// made an endless loop that froze the app.
  void _markSeenIfNew(List<ChatMessage> messages) {
    final me = ref.read(myProfileProvider).value?.id;
    DateTime? newest;
    for (final m in messages) {
      if (m.pending || m.sender.id == me) continue;
      if (newest == null || m.createdAt.isAfter(newest)) newest = m.createdAt;
    }
    if (newest == null) return;
    final upTo = _seenUpTo;
    if (upTo != null && !newest.isAfter(upTo)) return;
    _seenUpTo = newest;
    unawaited(_repo.markSeen(conversationId).catchError((_) {}));
  }

  Future<void> refresh() async {
    final current = state.value;
    try {
      final latest = await _repo.fetchMessages(conversationId);
      final oldest = latest.isEmpty ? null : latest.last.createdAt;
      final older = current == null || oldest == null
          ? const <ChatMessage>[]
          : current.messages
                .where((m) => !m.pending && m.createdAt.isBefore(oldest))
                .toList();
      final pending =
          current?.messages
              .where((m) => m.pending && !latest.any((l) => l.body == m.body))
              .toList() ??
          [];
      state = AsyncData(
        (current ?? const ChatState()).copyWith(
          messages: [...pending, ...latest, ...older],
          hasMore: older.isNotEmpty
              ? current!.hasMore
              : latest.length == ChatRepository.pageSize,
        ),
      );
      _markSeenIfNew(latest);
    } catch (_) {
      // Keep what we have.
    }
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null ||
        !current.hasMore ||
        current.loadingMore ||
        current.messages.isEmpty) {
      return;
    }
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final older = await _repo.fetchMessages(
        conversationId,
        before: current.messages.lastWhere((m) => !m.pending).createdAt,
      );
      final latest = state.value ?? current;
      final known = latest.messages.map((m) => m.id).toSet();
      state = AsyncData(
        latest.copyWith(
          messages: [
            ...latest.messages,
            ...older.where((m) => !known.contains(m.id)),
          ],
          hasMore: older.length == ChatRepository.pageSize,
          loadingMore: false,
        ),
      );
    } catch (_) {
      state = AsyncData((state.value ?? current).copyWith(loadingMore: false));
    }
  }

  /// Shows the message right away (⏱), then sends it.
  void addPending(ChatMessage message) {
    final current = state.value ?? const ChatState();
    state = AsyncData(
      current.copyWith(messages: [message, ...current.messages]),
    );
  }

  void removePending(String tempId) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        messages: current.messages.where((m) => m.id != tempId).toList(),
      ),
    );
  }
}

final chatControllerProvider = AsyncNotifierProvider.autoDispose
    .family<ChatController, ChatState, String>(ChatController.new);

/// "Sara is typing…" for one chat. Holds names that typed in the last 4 s.
class TypingState extends Notifier<Map<String, String>> {
  TypingState(this.conversationId);

  final String conversationId;
  RealtimeChannel? _channel;
  final Map<String, Timer> _timers = {};
  DateTime _lastSent = DateTime(2000);

  @override
  Map<String, String> build() {
    final repo = ref.watch(chatRepositoryProvider);
    final me = ref.watch(myProfileProvider).value;
    _channel = repo.typingChannel(conversationId, (id, name) {
      if (id == me?.id) return;
      _timers[id]?.cancel();
      _timers[id] = Timer(const Duration(seconds: 4), () {
        state = {...state}..remove(id);
      });
      state = {...state, id: name};
    });
    ref.onDispose(() {
      for (final t in _timers.values) {
        t.cancel();
      }
      final channel = _channel;
      if (channel != null) {
        unawaited(repo.stop(channel).catchError((_) => 'error'));
      }
    });
    return const {};
  }

  /// Called while I type; sends at most one signal every 2 seconds.
  void iAmTyping() {
    final me = ref.read(myProfileProvider).value;
    final channel = _channel;
    if (me == null || channel == null) return;
    final now = DateTime.now();
    if (now.difference(_lastSent) < const Duration(seconds: 2)) return;
    _lastSent = now;
    unawaited(
      ref
          .read(chatRepositoryProvider)
          .sendTyping(channel, me.id, me.fullName)
          .catchError((_) {}),
    );
  }
}

final typingProvider = NotifierProvider.autoDispose
    .family<TypingState, Map<String, String>, String>(TypingState.new);
