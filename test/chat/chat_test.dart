import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workplace_app/app.dart';
import 'package:workplace_app/core/l10n/locale_controller.dart';
import 'package:workplace_app/features/auth/application/auth_providers.dart';
import 'package:workplace_app/features/auth/domain/auth_status.dart';
import 'package:workplace_app/features/auth/domain/my_profile.dart';
import 'package:workplace_app/features/chat/data/chat_repository.dart';
import 'package:workplace_app/features/chat/domain/chat_message.dart';
import 'package:workplace_app/features/chat/domain/conversation.dart';
import 'package:workplace_app/features/feed/data/feed_repository.dart';
import 'package:workplace_app/features/feed/domain/person.dart';
import 'package:workplace_app/features/feed/presentation/animated_emoji.dart';

import '../feed/fake_feed_repository.dart';
import '../phase6/fakes.dart';

class _SignedIn extends AuthStatusController {
  @override
  AuthStatus build() => AuthStatus.signedIn;
}

class _NoopChannel implements RealtimeChannel {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

const _me = MyProfile(
  id: 'me',
  fullName: 'Owner',
  phone: '+20100',
  role: 'admin',
);
const _sara = Person(id: 'sara', fullName: 'Sara Ali');

class FakeChatRepository extends ChatRepository {
  FakeChatRepository() : super.withoutClient();

  final List<String> sent = [];
  final List<String> seenCalls = [];
  final List<(String, String)> reactions = [];
  void Function(Set<String>)? presence;

  late final List<ChatMessage> messages = [
    ChatMessage(
      id: 'm2',
      conversationId: 'c1',
      sender: const Person(id: 'me', fullName: 'Owner'),
      body: 'See you at 10',
      createdAt: DateTime.now().subtract(const Duration(minutes: 1)),
      recipientCount: 1,
      deliveredCount: 1,
      seenCount: 1,
    ),
    ChatMessage(
      id: 'm1',
      conversationId: 'c1',
      sender: _sara,
      body: 'Meeting tomorrow?',
      createdAt: DateTime.now().subtract(const Duration(minutes: 3)),
      reactions: const {
        '👍': ['me'],
      },
    ),
  ];

  @override
  Future<List<Conversation>> listConversations() async => [
    Conversation(
      id: 'c1',
      isGroup: false,
      memberCount: 2,
      otherPerson: _sara,
      unreadCount: 2,
      lastMessageAt: DateTime.now(),
      lastMessage: const LastMessage(
        body: 'Meeting tomorrow?',
        senderId: 'sara',
        senderName: 'Sara Ali',
        deleted: false,
        hasAttachment: false,
      ),
    ),
  ];

  @override
  Future<void> markDelivered(String conversationId) async {}

  /// Live inbox callback; marking seen fires it like the real database does.
  void Function()? inbox;

  @override
  Future<void> markSeen(String conversationId) async {
    seenCalls.add(conversationId);
    inbox?.call();
  }

  @override
  Future<List<ChatMessage>> fetchMessages(
    String conversationId, {
    DateTime? before,
  }) async => before == null ? messages : const [];

  @override
  Future<String> send({
    required String conversationId,
    required String senderId,
    required String body,
    String? replyToId,
    List<PendingUpload> uploads = const [],
  }) async {
    sent.add(body);
    messages.insert(
      0,
      ChatMessage(
        id: 'm${messages.length + 1}',
        conversationId: conversationId,
        sender: const Person(id: 'me', fullName: 'Owner'),
        body: body,
        createdAt: DateTime.now(),
        recipientCount: 1,
      ),
    );
    return 'new';
  }

  @override
  Future<void> addReaction(
    String messageId,
    String profileId,
    String emoji,
  ) async => reactions.add((messageId, emoji));

  @override
  Future<void> removeReaction(
    String messageId,
    String profileId,
    String emoji,
  ) async => reactions.add((messageId, '-$emoji'));

  @override
  RealtimeChannel watchInbox(void Function() onChange) {
    inbox = onChange;
    return _NoopChannel();
  }

  @override
  RealtimeChannel typingChannel(
    String conversationId,
    void Function(String, String) onTyping,
  ) => _NoopChannel();

  @override
  RealtimeChannel presenceChannel(
    String profileId,
    void Function(Set<String>) onChange,
  ) {
    presence = onChange;
    return _NoopChannel();
  }

  @override
  Future<void> sendTyping(
    RealtimeChannel channel,
    String profileId,
    String name,
  ) async {}

  @override
  Future<void> stop(RealtimeChannel channel) async {}
}

Future<FakeChatRepository> _pump(
  WidgetTester tester, {
  String locale = 'en',
}) async {
  AnimatedEmoji.enabled = false;
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'app_locale': locale});
  final prefs = await SharedPreferences.getInstance();
  final chat = FakeChatRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authStatusProvider.overrideWith(_SignedIn.new),
        myProfileProvider.overrideWith((ref) async => _me),
        ...phase6Overrides(),
        feedRepositoryProvider.overrideWithValue(FakeFeedRepository()),
        chatRepositoryProvider.overrideWithValue(chat),
      ],
      child: const WorkplaceApp(),
    ),
  );
  await tester.pumpAndSettle();
  return chat;
}

void main() {
  testWidgets('home shows the unread chat badge and the chat list', (
    tester,
  ) async {
    final chat = await _pump(tester);
    expect(
      find.descendant(
        of: find.byKey(const Key('openChats')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );

    chat.presence!({'sara'});
    await tester.tap(find.byKey(const Key('openChats')));
    await tester.pumpAndSettle();
    expect(find.text('Sara Ali'), findsOneWidget);
    expect(find.text('Meeting tomorrow?'), findsOneWidget);
  });

  testWidgets(
    'opening a chat marks it seen and shows blue ticks on my seen message',
    (tester) async {
      final chat = await _pump(tester);
      chat.presence!({'sara'});
      await tester.tap(find.byKey(const Key('openChats')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat-c1')));
      await tester.pumpAndSettle();

      expect(chat.seenCalls, contains('c1'));
      expect(find.text('Meeting tomorrow?'), findsOneWidget);
      expect(find.byKey(const Key('seenTicks')), findsOneWidget);
      expect(find.text('Online'), findsOneWidget);
    },
  );

  testWidgets('marking seen does not loop when my message is still unseen', (
    tester,
  ) async {
    final chat = await _pump(tester);
    chat.messages.insert(
      0,
      ChatMessage(
        id: 'm3',
        conversationId: 'c1',
        sender: const Person(id: 'me', fullName: 'Owner'),
        body: 'Are you there?',
        createdAt: DateTime.now(),
        recipientCount: 1,
      ),
    );
    await tester.tap(find.byKey(const Key('openChats')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-c1')).last);
    // Several live updates arrive; each one refreshes the chat.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tester.pumpAndSettle();
    expect(chat.seenCalls.length, 1);
  });

  testWidgets('sending a message with Enter', (tester) async {
    final chat = await _pump(tester);
    await tester.tap(find.byKey(const Key('openChats')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-c1')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('messageField')),
      'On my way 🚗',
    );
    await tester.tap(find.byKey(const Key('sendMessageButton')));
    await tester.pumpAndSettle();

    expect(chat.sent, ['On my way 🚗']);
    expect(find.text('On my way 🚗'), findsOneWidget);
  });

  testWidgets('tapping a reaction chip removes my reaction', (tester) async {
    final chat = await _pump(tester);
    await tester.tap(find.byKey(const Key('openChats')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-c1')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('👍'));
    await tester.pumpAndSettle();
    expect(chat.reactions, [('m1', '-👍')]);
  });

  testWidgets('chat works in Arabic', (tester) async {
    await _pump(tester, locale: 'ar');
    await tester.tap(find.byKey(const Key('openChats')));
    await tester.pumpAndSettle();
    expect(find.text('الدردشة'), findsOneWidget);
  });
}
