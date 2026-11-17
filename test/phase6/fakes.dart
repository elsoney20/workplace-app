import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workplace_app/features/directory/data/directory_repository.dart';
import 'package:workplace_app/features/feed/domain/person.dart';
import 'package:workplace_app/features/moderation/data/moderation_repository.dart';
import 'package:workplace_app/features/notifications/application/desktop_notifier.dart';
import 'package:workplace_app/features/notifications/data/notifications_repository.dart';
import 'package:workplace_app/features/search/data/search_repository.dart';

class _NoopChannel implements RealtimeChannel {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

const sara = Person(id: 'sara', fullName: 'Sara Ali', jobTitle: 'Designer');

class FakeNotificationsRepository extends NotificationsRepository {
  FakeNotificationsRepository({List<AppNotification>? items})
    : items = items ?? [],
      super.withoutClient();

  final List<AppNotification> items;

  @override
  Future<List<AppNotification>> list({DateTime? before}) async =>
      List.of(items);

  @override
  Future<int> unreadCount() async =>
      items.where((n) => n.readAt == null).length;

  @override
  Future<void> markRead([List<String>? ids]) async {
    for (var i = 0; i < items.length; i++) {
      final n = items[i];
      if (ids == null || ids.contains(n.id)) {
        items[i] = AppNotification(
          id: n.id,
          type: n.type,
          target: n.target,
          createdAt: n.createdAt,
          actor: n.actor,
          preview: n.preview,
          readAt: DateTime.now(),
        );
      }
    }
  }

  @override
  RealtimeChannel watch(void Function(Map<String, dynamic> row) onNew) =>
      _NoopChannel();

  @override
  Future<void> stop(RealtimeChannel channel) async {}
}

class FakeSearchRepository extends SearchRepository {
  FakeSearchRepository() : super.withoutClient();

  @override
  Future<List<SearchHit>> posts(String query) async => [
    SearchHit(
      id: 'p1',
      person: sara,
      body: 'Match on Friday #football',
      createdAt: DateTime.now(),
    ),
  ];

  @override
  Future<List<SearchHit>> messages(String query) async => [
    SearchHit(
      id: 'm1',
      person: sara,
      body: 'See you at the match',
      createdAt: DateTime.now(),
      contextId: 'c1',
      contextTitle: 'Sara Ali',
    ),
  ];
}

class FakeDirectoryRepository extends DirectoryRepository {
  FakeDirectoryRepository() : super.withoutClient();

  String savedVisibility = 'everyone';

  @override
  Future<List<DirectoryEntry>> list({
    String? query,
    String? departmentId,
  }) async => [
    const DirectoryEntry(
      person: sara,
      role: 'employee',
      departmentEn: 'Sales',
      departmentAr: 'المبيعات',
      phone: '+201000000001',
    ),
  ];

  @override
  Future<List<(String, String, String)>> departments() async => [
    ('d1', 'المبيعات', 'Sales'),
  ];

  @override
  Future<MySettings> mySettings() async =>
      MySettings(phoneVisibility: savedVisibility);

  @override
  Future<void> saveSettings(
    String profileId, {
    String? bio,
    required String phoneVisibility,
  }) async {
    savedVisibility = phoneVisibility;
  }
}

class FakeModerationRepository extends ModerationRepository {
  FakeModerationRepository() : super.withoutClient();

  final List<ContentReport> reports = [];
  final List<String> sent = [];

  @override
  Future<void> report({
    String? postId,
    String? commentId,
    required String reason,
  }) async {
    sent.add('${postId ?? commentId}:$reason');
  }

  @override
  Future<List<ContentReport>> list(ReportStatus? status) async =>
      reports.where((r) => r.status == status).toList();

  @override
  Future<void> handle(
    String reportId,
    ReportStatus status, {
    bool deleteContent = false,
  }) async {
    final i = reports.indexWhere((r) => r.id == reportId);
    final r = reports[i];
    reports[i] = ContentReport(
      id: r.id,
      status: status,
      reason: r.reason,
      createdAt: r.createdAt,
      reporter: r.reporter,
      postId: r.postId,
      content: r.content,
      contentAuthor: r.contentAuthor,
      contentDeleted: deleteContent || r.contentDeleted,
    );
  }
}

/// Overrides every Phase 6 repository so widget tests never touch Supabase.
List<Override> phase6Overrides({
  FakeNotificationsRepository? notifications,
  FakeModerationRepository? moderation,
  FakeDirectoryRepository? directory,
}) => [
  notificationsRepositoryProvider.overrideWithValue(
    notifications ?? FakeNotificationsRepository(),
  ),
  searchRepositoryProvider.overrideWithValue(FakeSearchRepository()),
  directoryRepositoryProvider.overrideWithValue(
    directory ?? FakeDirectoryRepository(),
  ),
  moderationRepositoryProvider.overrideWithValue(
    moderation ?? FakeModerationRepository(),
  ),
  desktopNotifierProvider.overrideWithValue(DesktopNotifier(enabled: false)),
];
