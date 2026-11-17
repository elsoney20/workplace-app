import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workplace_app/app.dart';
import 'package:workplace_app/core/l10n/locale_controller.dart';
import 'package:workplace_app/features/auth/application/auth_providers.dart';
import 'package:workplace_app/features/auth/domain/auth_status.dart';
import 'package:workplace_app/features/auth/domain/my_profile.dart';
import 'package:workplace_app/features/chat/data/chat_repository.dart';
import 'package:workplace_app/features/feed/data/feed_repository.dart';
import 'package:workplace_app/features/feed/domain/feed_post.dart';
import 'package:workplace_app/features/feed/presentation/animated_emoji.dart';
import 'package:workplace_app/features/moderation/data/moderation_repository.dart';
import 'package:workplace_app/features/notifications/data/notifications_repository.dart';

import '../chat/chat_test.dart' show FakeChatRepository;
import '../feed/fake_feed_repository.dart';
import 'fakes.dart';

class _SignedIn extends AuthStatusController {
  @override
  AuthStatus build() => AuthStatus.signedIn;
}

const _me = MyProfile(
  id: 'me',
  fullName: 'Owner',
  phone: '+20100',
  role: 'admin',
);

Future<void> _pump(
  WidgetTester tester, {
  FakeNotificationsRepository? notifications,
  FakeModerationRepository? moderation,
  FakeFeedRepository? feed,
  String locale = 'en',
}) async {
  AnimatedEmoji.enabled = false;
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'app_locale': locale});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authStatusProvider.overrideWith(_SignedIn.new),
        myProfileProvider.overrideWith((ref) async => _me),
        ...phase6Overrides(
          notifications: notifications,
          moderation: moderation,
        ),
        feedRepositoryProvider.overrideWithValue(feed ?? FakeFeedRepository()),
        chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
      ],
      child: const WorkplaceApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'the bell shows unread notifications and opening it marks them read',
    (tester) async {
      final notifications = FakeNotificationsRepository(
        items: [
          AppNotification(
            id: 'n1',
            type: 'mention',
            target: const {'post_id': 'p1'},
            createdAt: DateTime.now(),
            actor: sara,
            preview: 'Hi @[Owner](me)',
          ),
        ],
      );
      await _pump(tester, notifications: notifications);
      expect(
        find.descendant(
          of: find.byKey(const Key('openNotifications')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('openNotifications')));
      await tester.pumpAndSettle();
      expect(find.text('Sara Ali mentioned you'), findsOneWidget);
      await tester.tap(find.byKey(const Key('markAllRead')));
      await tester.pumpAndSettle();
      expect(notifications.items.single.readAt, isNotNull);
    },
  );

  testWidgets('search finds people, posts and my messages', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('openSearch')));
    await tester.pumpAndSettle();
    expect(find.text('Type at least 2 letters.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('searchField')), 'match');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Sara Ali'), findsOneWidget);
    await tester.tap(find.text('Posts'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Match on Friday'), findsOneWidget);
    await tester.tap(find.text('Messages'));
    await tester.pumpAndSettle();
    expect(find.textContaining('See you at the match'), findsOneWidget);
  });

  testWidgets('directory shows the phone only when allowed', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('openDirectory')));
    await tester.pumpAndSettle();
    expect(find.text('Sara Ali'), findsOneWidget);
    await tester.tap(find.text('Sara Ali'));
    await tester.pumpAndSettle();
    expect(find.textContaining('+201000000001'), findsOneWidget);
  });

  testWidgets('reporting a post and handling it in the reports screen', (
    tester,
  ) async {
    final moderation = FakeModerationRepository();
    final feed = FakeFeedRepository(
      posts: [
        FeedPost(
          id: 'p9',
          author: sara,
          body: 'Bad post',
          createdAt: DateTime.now(),
        ),
      ],
    );
    await _pump(tester, moderation: moderation, feed: feed);
    await tester.tap(find.byKey(const Key('postMenu-p9')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reportPost-p9')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('reportReason')), 'Rude');
    await tester.tap(find.byKey(const Key('reportSend')));
    await tester.pumpAndSettle();
    expect(moderation.sent, ['p9:Rude']);
    expect(find.text('Thanks. A moderator will review it.'), findsOneWidget);

    moderation.reports.add(
      ContentReport(
        id: 'r1',
        status: ReportStatus.open,
        reason: 'Rude',
        createdAt: DateTime.now(),
        reporter: sara,
        postId: 'p9',
        content: 'Bad post',
        contentAuthor: sara,
      ),
    );
    await tester.tap(find.byKey(const Key('openReports')));
    await tester.pumpAndSettle();
    expect(find.text('Bad post'), findsOneWidget);
    await tester.tap(find.byKey(const Key('deleteReported-r1')));
    await tester.pumpAndSettle();
    expect(moderation.reports.single.status, ReportStatus.resolved);
    expect(moderation.reports.single.contentDeleted, isTrue);
    expect(find.text('No open reports.'), findsOneWidget);
  });

  testWidgets('home works in Arabic with the new buttons', (tester) async {
    await _pump(tester, locale: 'ar');
    expect(find.byKey(const Key('openNotifications')), findsOneWidget);
    expect(find.byKey(const Key('openReports')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
