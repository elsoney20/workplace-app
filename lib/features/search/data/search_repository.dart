import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_bootstrap.dart';
import '../../feed/domain/person.dart';

/// One search hit: a post (company or group feed) or a chat message.
class SearchHit {
  const SearchHit({
    required this.id,
    required this.person,
    required this.body,
    required this.createdAt,
    this.contextId,
    this.contextTitle,
  });

  final String id;
  final Person person;
  final String body;
  final DateTime createdAt;

  /// Group id (posts) or conversation id (messages).
  final String? contextId;
  final String? contextTitle;
}

class SearchRepository {
  SearchRepository(SupabaseClient client) : _clientOrNull = client;
  SearchRepository.withoutClient() : _clientOrNull = null;

  final SupabaseClient? _clientOrNull;
  SupabaseClient get _client => _clientOrNull!;

  static const int minLength = 2;

  Future<List<SearchHit>> posts(String query) async {
    final rows = await _client.rpc<List<dynamic>>(
      'search_posts',
      params: {'p_query': query},
    );
    return [
      for (final r in rows.cast<Map>())
        SearchHit(
          id: r['id'] as String,
          person: Person.fromJson(
            Map<String, dynamic>.from(r['author'] as Map),
          ),
          body: r['body'] as String? ?? '',
          createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
          contextId: r['group_id'] as String?,
          contextTitle: r['group_name'] as String?,
        ),
    ];
  }

  /// Only ever searches the caller's own chats (database rule).
  Future<List<SearchHit>> messages(String query) async {
    final rows = await _client.rpc<List<dynamic>>(
      'search_messages',
      params: {'p_query': query},
    );
    return [
      for (final r in rows.cast<Map>())
        SearchHit(
          id: r['id'] as String,
          person: Person.fromJson(
            Map<String, dynamic>.from(r['sender'] as Map),
          ),
          body: r['body'] as String? ?? '',
          createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
          contextId: r['conversation_id'] as String?,
          contextTitle: r['conversation_title'] as String?,
        ),
    ];
  }
}

final searchRepositoryProvider = Provider<SearchRepository>(
  (ref) => SearchRepository(ref.watch(supabaseClientProvider)),
);
