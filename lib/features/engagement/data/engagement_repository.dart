import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_bootstrap.dart';
import '../../feed/domain/person.dart';
import '../domain/home_sidebar.dart';

/// Birthdays, events, kudos (the database re-checks every permission).
class EngagementRepository {
  EngagementRepository(this._client);

  final SupabaseClient _client;

  Future<HomeSidebar> fetchSidebar() async {
    final json = await _client.rpc<Map<String, dynamic>>('get_home_sidebar');
    return HomeSidebar.fromJson(json);
  }

  Future<List<Person>> fetchPeople(Iterable<String> ids) async {
    if (ids.isEmpty) return const [];
    final rows = await _client.rpc<List<dynamic>>(
      'get_people',
      params: {'p_ids': ids.toList()},
    );
    return [
      for (final r in rows)
        Person.fromJson(Map<String, dynamic>.from(r as Map)),
    ];
  }

  Future<void> setGoing(String eventId, String myId, {required bool going}) =>
      going
      ? _client.from('event_attendees').insert({
          'event_id': eventId,
          'profile_id': myId,
        })
      : _client
            .from('event_attendees')
            .delete()
            .eq('event_id', eventId)
            .eq('profile_id', myId);

  Future<void> createEvent({
    required String title,
    required String kind,
    required DateTime startsAt,
    DateTime? endsAt,
    String? location,
    String? description,
  }) => _client.from('events').insert({
    'title': title,
    'kind': kind,
    'starts_at': startsAt.toUtc().toIso8601String(),
    'ends_at': endsAt?.toUtc().toIso8601String(),
    'location': location,
    'description': description,
  });

  Future<void> deleteEvent(String id) =>
      _client.from('events').delete().eq('id', id);

  Future<void> sendKudos({
    required String fromId,
    required String toId,
    required KudosBadge badge,
    String? message,
  }) => _client.from('kudos').insert({
    'from_id': fromId,
    'to_id': toId,
    'badge': badge.name,
    'message': (message == null || message.trim().isEmpty)
        ? null
        : message.trim(),
  });

  Future<DateTime?> myBirthday() async {
    final v = await _client.rpc<dynamic>('get_my_birthday');
    return v is String ? DateTime.parse(v) : null;
  }

  Future<void> setMyBirthday(DateTime? day) => _client.rpc<void>(
    'set_my_birthday',
    params: {
      'p_birthday': day == null
          ? null
          : '${day.year.toString().padLeft(4, '0')}-'
                '${day.month.toString().padLeft(2, '0')}-'
                '${day.day.toString().padLeft(2, '0')}',
    },
  );
}

final engagementRepositoryProvider = Provider<EngagementRepository>(
  (ref) => EngagementRepository(ref.watch(supabaseClientProvider)),
);
