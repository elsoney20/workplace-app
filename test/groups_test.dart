import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workplace_app/app.dart';
import 'package:workplace_app/core/l10n/locale_controller.dart';
import 'package:workplace_app/features/auth/application/auth_providers.dart';
import 'package:workplace_app/features/auth/domain/auth_status.dart';
import 'package:workplace_app/features/auth/domain/my_profile.dart';
import 'package:workplace_app/features/feed/data/feed_repository.dart';
import 'package:workplace_app/features/feed/domain/person.dart';
import 'package:workplace_app/features/feed/presentation/animated_emoji.dart';
import 'package:workplace_app/features/groups/data/groups_repository.dart';
import 'package:workplace_app/features/groups/domain/work_group.dart';

import 'feed/fake_feed_repository.dart';

class _SignedIn extends AuthStatusController {
  @override
  AuthStatus build() => AuthStatus.signedIn;
}

class FakeGroupsRepository extends GroupsRepository {
  FakeGroupsRepository() : super.withoutClient();

  final List<WorkGroup> groups = [
    const WorkGroup(
      id: 'g-sales',
      name: 'Sales',
      privacy: GroupPrivacy.private,
      memberCount: 12,
      canModerate: false,
      departmentId: 'd1',
      myRole: GroupRole.member,
    ),
    const WorkGroup(
      id: 'g-football',
      name: 'Football club',
      privacy: GroupPrivacy.public,
      memberCount: 8,
      canModerate: false,
    ),
  ];
  final List<String> joined = [];
  final List<String> created = [];

  @override
  Future<List<WorkGroup>> listGroups({
    String? query,
    bool onlyMine = false,
  }) async => onlyMine ? groups.where((g) => g.isMember).toList() : groups;

  @override
  Future<WorkGroup?> getGroup(String id) async =>
      groups.where((g) => g.id == id).firstOrNull;

  @override
  Future<List<GroupMember>> listMembers(String groupId) async => const [
    GroupMember(Person(id: 'p1', fullName: 'Sara Ali'), GroupRole.owner),
  ];

  @override
  Future<void> join(String groupId, String profileId) async {
    joined.add(groupId);
    final i = groups.indexWhere((g) => g.id == groupId);
    final g = groups[i];
    groups[i] = WorkGroup(
      id: g.id,
      name: g.name,
      privacy: g.privacy,
      memberCount: g.memberCount + 1,
      canModerate: false,
      myRole: GroupRole.member,
    );
  }

  @override
  Future<String> createGroup({
    required String name,
    String? description,
    required GroupPrivacy privacy,
  }) async {
    created.add(name);
    groups.add(
      WorkGroup(
        id: 'g-new',
        name: name,
        privacy: privacy,
        memberCount: 1,
        canModerate: true,
        myRole: GroupRole.owner,
      ),
    );
    return 'g-new';
  }
}

Future<FakeGroupsRepository> _pump(
  WidgetTester tester,
  MyProfile me, {
  String locale = 'en',
}) async {
  AnimatedEmoji.enabled = false;
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'app_locale': locale});
  final prefs = await SharedPreferences.getInstance();
  final groups = FakeGroupsRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authStatusProvider.overrideWith(_SignedIn.new),
        myProfileProvider.overrideWith((ref) async => me),
        feedRepositoryProvider.overrideWithValue(FakeFeedRepository()),
        groupsRepositoryProvider.overrideWithValue(groups),
      ],
      child: const WorkplaceApp(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('openGroups')));
  await tester.pumpAndSettle();
  return groups;
}

const _employee = MyProfile(
  id: 'e1',
  fullName: 'Sara',
  phone: '+20100',
  role: 'employee',
);
const _manager = MyProfile(
  id: 'm1',
  fullName: 'Mona',
  phone: '+20101',
  role: 'manager',
);

void main() {
  testWidgets(
    'my groups lists the department group; discover lists public groups',
    (tester) async {
      await _pump(tester, _employee);

      expect(find.text('Sales'), findsOneWidget);
      expect(find.textContaining('Department'), findsOneWidget);
      expect(
        find.byKey(const Key('createGroupButton')),
        findsNothing,
        reason: 'employees cannot create groups',
      );

      await tester.tap(find.text('Discover'));
      await tester.pumpAndSettle();
      expect(find.text('Football club'), findsOneWidget);
    },
  );

  testWidgets('joining a public group', (tester) async {
    final repo = await _pump(tester, _employee);
    await tester.tap(find.text('Discover'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Football club'));
    await tester.pumpAndSettle();

    expect(find.text('Join the group to post here.'), findsOneWidget);
    expect(find.byKey(const Key('openComposer')), findsNothing);
    await tester.tap(find.byKey(const Key('joinGroupButton')));
    await tester.pumpAndSettle();

    expect(repo.joined, ['g-football']);
    expect(find.byKey(const Key('openComposer')), findsOneWidget);
  });

  testWidgets('managers can create a group', (tester) async {
    final repo = await _pump(tester, _manager);

    await tester.tap(find.byKey(const Key('createGroupButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('groupNameField')),
      'Project X',
    );
    await tester.tap(find.text('Private'));
    await tester.tap(find.byKey(const Key('saveGroupButton')));
    await tester.pumpAndSettle();

    expect(repo.created, ['Project X']);
    expect(repo.groups.last.privacy, GroupPrivacy.private);
    expect(
      find.byKey(const Key('addMembersButton')),
      findsNothing,
      reason: 'members tab not open yet',
    );
    await tester.tap(find.text('Members'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('addMembersButton')), findsOneWidget);
  });

  testWidgets('groups screen works in Arabic', (tester) async {
    await _pump(tester, _employee, locale: 'ar');
    expect(find.text('الجروبات'), findsOneWidget);
    expect(find.textContaining('قسم'), findsOneWidget);
  });
}
