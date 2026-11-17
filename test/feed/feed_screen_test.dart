import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workplace_app/app.dart';
import 'package:workplace_app/core/l10n/locale_controller.dart';
import 'package:workplace_app/features/chat/data/chat_repository.dart';
import 'package:workplace_app/features/auth/application/auth_providers.dart';
import 'package:workplace_app/features/auth/domain/auth_status.dart';
import 'package:workplace_app/features/auth/domain/my_profile.dart';
import 'package:workplace_app/features/feed/data/feed_repository.dart';
import 'package:workplace_app/features/feed/domain/feed_post.dart';
import 'package:workplace_app/features/feed/domain/person.dart';
import 'package:workplace_app/features/feed/presentation/animated_emoji.dart';

import 'fake_feed_repository.dart';
import '../chat/chat_test.dart' show FakeChatRepository;

class _SignedIn extends AuthStatusController {
  @override
  AuthStatus build() => AuthStatus.signedIn;
}

const _owner = MyProfile(
  id: 'owner',
  fullName: 'Owner',
  phone: '+201065111122',
  role: 'admin',
);
const _sara = Person(
  id: '00000000-0000-0000-0000-0000000000a1',
  fullName: 'Sara Ali',
  jobTitle: 'Sales',
);

Future<FakeFeedRepository> _pump(
  WidgetTester tester, {
  String locale = 'en',
  MyProfile me = _owner,
}) async {
  AnimatedEmoji.enabled = false;
  tester.view.physicalSize = const Size(1200, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'app_locale': locale});
  final prefs = await SharedPreferences.getInstance();
  final repo = FakeFeedRepository(
    pinned: [
      FeedPost(
        id: 'ann',
        author: const Person(id: 'owner', fullName: 'Owner'),
        body: 'Office closed Thursday',
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        isAnnouncement: true,
        isPinned: true,
        seenCount: 12,
        audienceCount: 100,
      ),
    ],
    posts: [
      FeedPost(
        id: 'p1',
        author: _sara,
        body:
            'Great quarter #Sales thanks @[Owner](00000000-0000-0000-0000-0000000000ff)',
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
        reactions: const {'👍': 3, '❤️': 1},
        commentCount: 2,
      ),
      FeedPost(
        id: 'p2',
        author: _sara,
        body: 'Lunch at 2',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authStatusProvider.overrideWith(_SignedIn.new),
        myProfileProvider.overrideWith((ref) async => me),
        chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
        feedRepositoryProvider.overrideWithValue(repo),
      ],
      child: const WorkplaceApp(),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('feed shows the pinned announcement first, then posts', (
    tester,
  ) async {
    final repo = await _pump(tester);

    expect(find.text('Office closed Thursday'), findsOneWidget);
    expect(find.textContaining('Announcement'), findsOneWidget);
    expect(find.text('Seen by 12 of 100'), findsOneWidget);
    expect(find.text('2 comments'), findsOneWidget);
    expect(find.text('4'), findsOneWidget); // reaction total
    expect(find.text('Lunch at 2'), findsOneWidget);
    expect(repo.seen, ['ann'], reason: 'announcement is reported as seen');
    final announcementY = tester
        .getTopLeft(find.text('Office closed Thursday'))
        .dy;
    expect(
      announcementY,
      lessThan(tester.getTopLeft(find.text('Lunch at 2')).dy),
    );
  });

  testWidgets('tapping a hashtag filters the feed', (tester) async {
    await _pump(tester);

    await tester.tap(find.widgetWithText(ActionChip, '#sales'));
    await tester.pumpAndSettle();

    expect(find.text('Posts with #sales'), findsOneWidget);
    expect(find.text('Lunch at 2'), findsNothing);
    await tester.tap(find.byKey(const Key('clearHashtag')));
    await tester.pumpAndSettle();
    expect(find.text('Lunch at 2'), findsOneWidget);
  });

  testWidgets('writing a post with an @mention saves the mention markup', (
    tester,
  ) async {
    final repo = await _pump(tester);

    await tester.tap(find.byKey(const Key('openComposer')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('announcementSwitch')),
      findsOneWidget,
      reason: 'admins can announce',
    );

    await tester.enterText(
      find.byKey(const Key('postTextField')),
      'Welcome @Sa',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sara Ali').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('postTextField')),
      '${tester.widget<TextField>(find.byKey(const Key('postTextField'))).controller!.text}to #Sales',
    );
    await tester.tap(find.byKey(const Key('submitPostButton')));
    await tester.pumpAndSettle();

    expect(repo.created.single, 'Welcome @[Sara Ali](${_sara.id}) to #Sales');
    expect(find.text('Welcome @Sara Ali to #Sales'), findsOneWidget);
  });

  testWidgets('employees cannot make announcements', (tester) async {
    await _pump(
      tester,
      me: const MyProfile(
        id: 'e1',
        fullName: 'Sara',
        phone: '+20100',
        role: 'employee',
      ),
    );

    await tester.tap(find.byKey(const Key('openComposer')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('announcementSwitch')), findsNothing);
  });

  testWidgets('reacting picks an emoji from the reaction bar', (tester) async {
    final repo = await _pump(tester);

    await tester.tap(find.byKey(const Key('reactButton-p2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('😂').last);
    await tester.pumpAndSettle();

    expect(repo.reactions.single, ('p2', '😂'));
  });

  testWidgets('feed works in Arabic (right to left)', (tester) async {
    await _pump(tester, locale: 'ar');

    expect(find.text('إعلان رسمي · مثبّت'), findsOneWidget);
    expect(find.text('تعليقين'), findsOneWidget);
    final context = tester.element(find.text('Lunch at 2'));
    expect(Directionality.of(context), TextDirection.rtl);
  });
}
