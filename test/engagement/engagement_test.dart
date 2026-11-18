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
import 'package:workplace_app/features/engagement/application/engagement_providers.dart';
import 'package:workplace_app/features/engagement/data/engagement_repository.dart';
import 'package:workplace_app/features/engagement/domain/home_sidebar.dart';
import 'package:workplace_app/features/feed/data/feed_repository.dart';
import 'package:workplace_app/features/feed/domain/feed_post.dart';
import 'package:workplace_app/features/feed/domain/person.dart';
import 'package:workplace_app/features/feed/domain/poll.dart';
import 'package:workplace_app/features/feed/presentation/animated_emoji.dart';

import '../chat/chat_test.dart' show FakeChatRepository;
import '../feed/fake_feed_repository.dart';
import '../phase6/fakes.dart';

class _SignedIn extends AuthStatusController {
  @override
  AuthStatus build() => AuthStatus.signedIn;
}

class _FakeEngagement implements EngagementRepository {
  final List<(String, bool)> going = [];
  final List<(String, KudosBadge, String?)> kudos = [];

  @override
  Future<void> setGoing(
    String eventId,
    String myId, {
    required bool going,
  }) async => this.going.add((eventId, going));

  @override
  Future<void> sendKudos({
    required String fromId,
    required String toId,
    required KudosBadge badge,
    String? message,
  }) async => kudos.add((toId, badge, message));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _me = MyProfile(
  id: 'me',
  fullName: 'Owner',
  phone: '+201065111122',
  role: 'employee',
);
const _sara = Person(
  id: '00000000-0000-0000-0000-0000000000a1',
  fullName: 'Sara Ali',
);
const _omar = Person(id: 'omar', fullName: 'Omar Khaled');

final _sidebar = HomeSidebar(
  myBirthdaySet: false,
  birthdays: [Celebration(person: _omar, day: DateTime.now(), daysUntil: 0)],
  anniversaries: [
    Celebration(person: _sara, day: DateTime.now(), daysUntil: 2, years: 3),
  ],
  newJoiners: const [Person(id: 'karim', fullName: 'Karim Youssef')],
  events: [
    CompanyEvent(
      id: 'e1',
      title: 'FIFA tournament',
      kind: 'tournament',
      startsAt: DateTime.now().add(const Duration(days: 2)),
      location: 'Game room',
      goingCount: 3,
      going: const [_sara, _omar],
    ),
  ],
  heroes: const [(_omar, 4), (_sara, 2)],
  kudos: [
    Kudos(
      id: 'k1',
      from: _sara,
      to: _omar,
      badge: KudosBadge.helpful,
      message: 'Fixed the cashier in 5 minutes',
      createdAt: DateTime.now().subtract(const Duration(hours: 1)),
    ),
  ],
);

Future<(FakeFeedRepository, _FakeEngagement)> _pump(
  WidgetTester tester, {
  double width = 1800,
}) async {
  AnimatedEmoji.enabled = false;
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'app_locale': 'en'});
  final prefs = await SharedPreferences.getInstance();
  final feed = FakeFeedRepository(
    posts: [
      FeedPost(
        id: 'poll1',
        author: _sara,
        body: 'Lunch on Thursday is on us',
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
        poll: const Poll(
          question: 'What should we order?',
          total: 3,
          options: [
            PollOption(id: 'o1', label: 'Pizza', votes: 2),
            PollOption(id: 'o2', label: 'Koshari', votes: 1),
          ],
        ),
      ),
    ],
  );
  final engagement = _FakeEngagement();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authStatusProvider.overrideWith(_SignedIn.new),
        myProfileProvider.overrideWith((ref) async => _me),
        chatRepositoryProvider.overrideWithValue(FakeChatRepository()),
        ...phase6Overrides(),
        feedRepositoryProvider.overrideWithValue(feed),
        engagementRepositoryProvider.overrideWithValue(engagement),
        homeSidebarProvider.overrideWith((ref) async => _sidebar),
        onlineCardsProvider.overrideWith((ref) async => const [_sara]),
      ],
      child: const WorkplaceApp(),
    ),
  );
  await tester.pumpAndSettle();
  return (feed, engagement);
}

void main() {
  testWidgets('wide screen: cards on both sides of the feed', (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('homeStartColumn')), findsOneWidget);
    expect(find.byKey(const Key('homeEndColumn')), findsOneWidget);
    expect(find.text('FIFA tournament'), findsOneWidget);
    expect(find.textContaining('Birthday today!'), findsOneWidget);
    expect(find.textContaining('3 years with us'), findsOneWidget);
    expect(find.text('Karim Youssef'), findsOneWidget);
    expect(find.text('Heroes of the week'), findsOneWidget);
    expect(find.text('Online now (1)'), findsOneWidget);
    expect(find.text('Fixed the cashier in 5 minutes'), findsOneWidget);
    // Employees cannot create events; the birthday prompt shows.
    expect(find.byKey(const Key('newEventButton')), findsNothing);
    expect(find.byKey(const Key('addMyBirthday')), findsOneWidget);
    // The start column sits before the feed, the end column after it.
    final feedX = tester.getCenter(find.text('Lunch on Thursday is on us')).dx;
    expect(tester.getCenter(find.text('FIFA tournament')).dx, lessThan(feedX));
    expect(
      tester.getCenter(find.text('Heroes of the week')).dx,
      greaterThan(feedX),
    );
  });

  testWidgets('medium screen: one column; narrow: the feed alone', (
    tester,
  ) async {
    await _pump(tester, width: 1300);
    expect(find.byKey(const Key('homeStartColumn')), findsNothing);
    expect(find.byKey(const Key('homeEndColumn')), findsOneWidget);
    await _pump(tester, width: 900);
    expect(find.byKey(const Key('homeEndColumn')), findsNothing);
  });

  testWidgets('switching rail pages keeps the feed (no reload)', (
    tester,
  ) async {
    final (feed, _) = await _pump(tester);
    expect(feed.feedLoads, 1);
    await tester.tap(find.byKey(const Key('openGroups')));
    await tester.pumpAndSettle();
    expect(find.text('Lunch on Thursday is on us'), findsNothing);
    await tester.tap(find.byKey(const Key('openHome')));
    await tester.pumpAndSettle();
    expect(find.text('Lunch on Thursday is on us'), findsOneWidget);
    expect(feed.feedLoads, 1, reason: 'the home page stayed alive');
  });

  testWidgets('I am going to an event', (tester) async {
    final (_, engagement) = await _pump(tester);
    await tester.tap(find.byKey(const Key('going-e1')));
    await tester.pumpAndSettle();
    expect(engagement.going, [('e1', true)]);
  });

  testWidgets('thank a colleague with a badge', (tester) async {
    final (_, engagement) = await _pump(tester);
    await tester.tap(find.byKey(const Key('sendKudosButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('kudosSearch')), 'sa');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('kudosPick-${_sara.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('badge-mvp')));
    await tester.enterText(find.byKey(const Key('kudosMessage')), 'Star!');
    await tester.tap(find.byKey(const Key('kudosSend')));
    await tester.pumpAndSettle();
    expect(engagement.kudos, [(_sara.id, KudosBadge.mvp, 'Star!')]);
  });

  testWidgets('vote in a poll, change it, take it back', (tester) async {
    final (feed, _) = await _pump(tester);
    expect(find.text('What should we order?'), findsOneWidget);
    expect(find.text('67%'), findsNothing, reason: 'results after voting');

    await tester.tap(find.byKey(const Key('pollOption-o2')));
    await tester.pumpAndSettle();
    expect(find.text('50%'), findsNWidgets(2));
    expect(find.text('4 votes'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pollOption-o1')));
    await tester.pumpAndSettle();
    expect(find.text('75%'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pollOption-o1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('3 votes'), findsOneWidget);
    expect(feed.votes, [('poll1', 'o2'), ('poll1', 'o1'), ('poll1', null)]);
  });

  testWidgets('a post with a poll', (tester) async {
    final (feed, _) = await _pump(tester);
    await tester.tap(find.byKey(const Key('openComposer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addPollButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pollQuestion')), 'Coffee?');
    await tester.enterText(find.byKey(const Key('pollOption-0')), 'Yes');
    await tester.tap(find.byKey(const Key('submitPostButton')));
    await tester.pumpAndSettle();
    expect(
      find.text('Write the question and at least 2 choices.'),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const Key('pollOption-1')), 'No');
    await tester.tap(find.byKey(const Key('submitPostButton')));
    await tester.pumpAndSettle();
    expect(feed.createdPolls.single.question, 'Coffee?');
    expect(feed.createdPolls.single.options, ['Yes', 'No']);
  });
}

void shotMain() {}
