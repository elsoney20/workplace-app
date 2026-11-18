import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_bootstrap.dart';
import '../domain/work_group.dart';

/// Groups reads and writes. RLS + triggers enforce who may do what.
class GroupsRepository {
  GroupsRepository(SupabaseClient client) : _clientOrNull = client;

  /// For tests that replace every method.
  GroupsRepository.withoutClient() : _clientOrNull = null;

  final SupabaseClient? _clientOrNull;
  SupabaseClient get _client => _clientOrNull!;

  Future<List<WorkGroup>> listGroups({
    String? query,
    bool onlyMine = false,
  }) async {
    final rows = await _client.rpc<List<dynamic>>(
      'list_groups',
      params: {'p_query': query, 'p_only_mine': onlyMine},
    );
    return rows
        .map((r) => WorkGroup.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<WorkGroup?> getGroup(String id) async {
    final all = await listGroups();
    return all.where((g) => g.id == id).firstOrNull;
  }

  Future<List<GroupMember>> listMembers(String groupId) async {
    final rows = await _client.rpc<List<dynamic>>(
      'get_group_members',
      params: {'p_group_id': groupId},
    );
    return rows
        .map((r) => GroupMember.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<String> createGroup({
    required String name,
    String? description,
    required GroupPrivacy privacy,
  }) async {
    final id = await _client.rpc<String>(
      'create_group',
      params: {
        'p_name': name,
        'p_description': description,
        'p_privacy': privacy.name,
      },
    );
    return id;
  }

  Future<void> updateGroup(
    String id, {
    required String name,
    String? description,
    required GroupPrivacy privacy,
  }) => _client
      .from('groups')
      .update({
        'name': name,
        'description': description,
        'privacy': privacy.name,
      })
      .eq('id', id);

  Future<void> deleteGroup(String id) =>
      _client.from('groups').delete().eq('id', id);

  Future<void> join(String groupId, String profileId) => _client
      .from('group_members')
      .insert({'group_id': groupId, 'profile_id': profileId});

  Future<void> addMember(String groupId, String profileId) =>
      join(groupId, profileId);

  Future<void> removeMember(String groupId, String profileId) => _client
      .from('group_members')
      .delete()
      .eq('group_id', groupId)
      .eq('profile_id', profileId);

  Future<void> setRole(String groupId, String profileId, GroupRole role) =>
      _client
          .from('group_members')
          .update({'role': role.name})
          .eq('group_id', groupId)
          .eq('profile_id', profileId);

  Future<void> setMuted(
    String groupId,
    String profileId, {
    required bool muted,
  }) => _client
      .from('group_members')
      .update({'muted': muted})
      .eq('group_id', groupId)
      .eq('profile_id', profileId);
}

final groupsRepositoryProvider = Provider<GroupsRepository>(
  (ref) => GroupsRepository(ref.watch(supabaseClientProvider)),
);

final myGroupsProvider = FutureProvider.autoDispose<List<WorkGroup>>(
  (ref) => ref.watch(groupsRepositoryProvider).listGroups(onlyMine: true),
);

final allGroupsProvider = FutureProvider.autoDispose<List<WorkGroup>>(
  (ref) => ref.watch(groupsRepositoryProvider).listGroups(),
);

final groupProvider = FutureProvider.autoDispose.family<WorkGroup?, String>(
  (ref, id) => ref.watch(groupsRepositoryProvider).getGroup(id),
);

final groupMembersProvider = FutureProvider.autoDispose
    .family<List<GroupMember>, String>(
      (ref, id) => ref.watch(groupsRepositoryProvider).listMembers(id),
    );
