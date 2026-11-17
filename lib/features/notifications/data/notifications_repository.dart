import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_bootstrap.dart';
import '../../feed/domain/person.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.target,
    required this.createdAt,
    this.actor,
    this.preview,
    this.readAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as String,
        type: json['type'] as String,
        actor: json['actor'] is Map
            ? Person.fromJson(Map<String, dynamic>.from(json['actor'] as Map))
            : null,
        target: json['target'] is Map
            ? Map<String, dynamic>.from(json['target'] as Map)
            : const {},
        preview: json['preview'] as String?,
        readAt: json['read_at'] == null
            ? null
            : DateTime.parse(json['read_at'] as String).toLocal(),
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      );

  final String id;

  /// mention, comment, reply, reaction, announcement, group_invite, report_update
  final String type;
  final Person? actor;

  /// What to open, e.g. {"post_id": "..."} or {"group_id": "..."}.
  final Map<String, dynamic> target;
  final String? preview;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get isRead => readAt != null;
  String? get postId => target['post_id'] as String?;
  String? get groupId => target['group_id'] as String?;
}

class NotificationsRepository {
  NotificationsRepository(SupabaseClient client) : _clientOrNull = client;
  NotificationsRepository.withoutClient() : _clientOrNull = null;

  final SupabaseClient? _clientOrNull;
  SupabaseClient get _client => _clientOrNull!;

  Future<List<AppNotification>> list({DateTime? before}) async {
    final rows = await _client.rpc<List<dynamic>>(
      'list_notifications',
      params: {'p_before': before?.toUtc().toIso8601String(), 'p_limit': 50},
    );
    return rows
        .map(
          (r) => AppNotification.fromJson(Map<String, dynamic>.from(r as Map)),
        )
        .toList();
  }

  Future<int> unreadCount() async =>
      await _client.rpc<int>('unread_notification_count');

  Future<void> markRead([List<String>? ids]) =>
      _client.rpc<void>('mark_notifications_read', params: {'p_ids': ids});

  /// Fires when a notification for me is created (RLS: only my rows).
  RealtimeChannel watch(void Function(Map<String, dynamic> row) onNew) {
    final channel = _client.channel('my-notifications');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'notifications',
      callback: (payload) => onNew(payload.newRecord),
    );
    return channel..subscribe();
  }

  Future<void> stop(RealtimeChannel channel) => _client.removeChannel(channel);
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) => NotificationsRepository(ref.watch(supabaseClientProvider)),
);
