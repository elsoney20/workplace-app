import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/my_profile.dart';
import '../../feed/data/feed_repository.dart';
import '../../feed/domain/feed_scope.dart';
import '../../feed/domain/person.dart';
import '../../feed/presentation/feed_view.dart';
import '../../feed/presentation/person_avatar.dart';
import '../data/groups_repository.dart';
import '../domain/work_group.dart';
import 'group_form_dialog.dart';

/// One group: its feed, members and settings.
class GroupScreen extends ConsumerWidget {
  const GroupScreen({super.key, required this.groupId});

  final String groupId;

  static const String routePath = '/groups/:id';
  static const String routeName = 'group';
  static String pathFor(String id) => '/groups/$id';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final group = ref.watch(groupProvider(groupId));
    final me = ref.watch(myProfileProvider).value;

    return switch ((group, me)) {
      (AsyncData(value: final g?), final MyProfile me) => _GroupBody(
        group: g,
        me: me,
      ),
      (AsyncData(value: null), _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(l10n.groupNotFound)),
      ),
      (AsyncError(), _) => Scaffold(
        appBar: AppBar(),
        body: Center(
          child: TextButton.icon(
            onPressed: () => ref.invalidate(groupProvider(groupId)),
            icon: const Icon(Icons.refresh),
            label: Text('${l10n.errorNetwork}\n${l10n.retry}'),
          ),
        ),
      ),
      _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }
}

enum _GroupAction { mute, unmute, leave, edit, delete }

class _GroupBody extends ConsumerWidget {
  const _GroupBody({required this.group, required this.me});

  final WorkGroup group;
  final MyProfile me;

  void _refresh(WidgetRef ref) {
    ref.invalidate(groupProvider(group.id));
    ref.invalidate(groupMembersProvider(group.id));
    ref.invalidate(myGroupsProvider);
    ref.invalidate(allGroupsProvider);
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      _refresh(ref);
    } on PostgrestException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e.message.contains('at least one owner')
                ? l10n.errorLastOwner
                : l10n.errorUnknown,
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.errorUnknown)));
    }
  }

  Future<bool> _confirm(
    BuildContext context,
    String text,
    String action,
  ) async {
    final l10n = AppLocalizations.of(context);
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            content: Text(text),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    _GroupAction action,
  ) async {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(groupsRepositoryProvider);
    switch (action) {
      case _GroupAction.mute:
        await _run(
          context,
          ref,
          () => repo.setMuted(group.id, me.id, muted: true),
        );
      case _GroupAction.unmute:
        await _run(
          context,
          ref,
          () => repo.setMuted(group.id, me.id, muted: false),
        );
      case _GroupAction.leave:
        if (await _confirm(
              context,
              l10n.leaveGroupConfirm(group.name),
              l10n.leaveGroup,
            ) &&
            context.mounted) {
          await _run(context, ref, () => repo.removeMember(group.id, me.id));
        }
      case _GroupAction.edit:
        if (await showGroupFormDialog(context, group: group) != null) {
          _refresh(ref);
        }
      case _GroupAction.delete:
        if (await _confirm(
              context,
              l10n.deleteGroupConfirm(group.name),
              l10n.delete,
            ) &&
            context.mounted) {
          await _run(context, ref, () => repo.deleteGroup(group.id));
          if (context.mounted) context.pop();
        }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final canJoin = !group.isMember && group.privacy == GroupPrivacy.public;
    final actions = <PopupMenuEntry<_GroupAction>>[
      if (group.isMember && !group.muted)
        PopupMenuItem(value: _GroupAction.mute, child: Text(l10n.muteGroup)),
      if (group.isMember && group.muted)
        PopupMenuItem(
          value: _GroupAction.unmute,
          child: Text(l10n.unmuteGroup),
        ),
      if (group.isMember && !group.isDepartment)
        PopupMenuItem(value: _GroupAction.leave, child: Text(l10n.leaveGroup)),
      if (group.canModerate)
        PopupMenuItem(value: _GroupAction.edit, child: Text(l10n.editGroup)),
      if (me.isAdmin && !group.isDepartment)
        PopupMenuItem(
          value: _GroupAction.delete,
          child: Text(l10n.deleteGroup),
        ),
    ];

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(group.name),
              Text(
                l10n.memberCount(group.memberCount),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            if (canJoin)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: FilledButton.icon(
                  key: const Key('joinGroupButton'),
                  onPressed: () => _run(
                    context,
                    ref,
                    () => ref
                        .read(groupsRepositoryProvider)
                        .join(group.id, me.id),
                  ),
                  icon: const Icon(Icons.group_add),
                  label: Text(l10n.joinGroup),
                ),
              ),
            if (actions.isNotEmpty)
              PopupMenuButton<_GroupAction>(
                key: const Key('groupMenu'),
                onSelected: (a) => _onAction(context, ref, a),
                itemBuilder: (_) => actions,
              ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.groupFeedTab),
              Tab(text: l10n.groupMembersTab),
              Tab(text: l10n.groupAboutTab),
            ],
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: TabBarView(
              children: [
                FeedView(
                  me: me,
                  scope: FeedScope(
                    groupId: group.id,
                    canModerate: group.canModerate,
                    canPost: group.isMember || group.canModerate,
                  ),
                  header: group.isMember || group.canModerate
                      ? null
                      : Card(
                          child: ListTile(
                            leading: const Icon(Icons.info_outline),
                            title: Text(l10n.joinToPost),
                          ),
                        ),
                ),
                _MembersTab(
                  group: group,
                  me: me,
                  onChanged: () => _refresh(ref),
                ),
                _AboutTab(group: group),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AboutTab extends StatelessWidget {
  const _AboutTab({required this.group});

  final WorkGroup group;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isPrivate = group.privacy == GroupPrivacy.private;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(group.name, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        if (group.description != null)
          Text(group.description!, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 16),
        ListTile(
          leading: Icon(isPrivate ? Icons.lock_outline : Icons.public),
          title: Text(isPrivate ? l10n.groupPrivate : l10n.groupPublic),
          subtitle: Text(
            isPrivate ? l10n.groupPrivateHint : l10n.groupPublicHint,
          ),
        ),
        if (group.isDepartment)
          ListTile(
            leading: const Icon(Icons.apartment),
            title: Text(l10n.departmentGroup),
            subtitle: Text(l10n.departmentGroupHint),
          ),
      ],
    );
  }
}

enum _MemberAction { moderator, owner, member, remove }

class _MembersTab extends ConsumerWidget {
  const _MembersTab({
    required this.group,
    required this.me,
    required this.onChanged,
  });

  final WorkGroup group;
  final MyProfile me;
  final VoidCallback onChanged;

  String _roleLabel(AppLocalizations l10n, GroupRole role) => switch (role) {
    GroupRole.owner => l10n.roleOwner,
    GroupRole.moderator => l10n.roleModerator,
    GroupRole.member => l10n.roleMember,
  };

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    GroupMember m,
    _MemberAction a,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(groupsRepositoryProvider);
    try {
      switch (a) {
        case _MemberAction.moderator:
          await repo.setRole(group.id, m.person.id, GroupRole.moderator);
        case _MemberAction.owner:
          await repo.setRole(group.id, m.person.id, GroupRole.owner);
        case _MemberAction.member:
          await repo.setRole(group.id, m.person.id, GroupRole.member);
        case _MemberAction.remove:
          await repo.removeMember(group.id, m.person.id);
      }
      onChanged();
    } on PostgrestException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e.message.contains('at least one owner')
                ? l10n.errorLastOwner
                : l10n.errorUnknown,
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.errorUnknown)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final members = ref.watch(groupMembersProvider(group.id));
    final canManageOwners = me.isAdmin || group.isOwner;
    final canAdd = group.canModerate && !group.isDepartment;

    return switch (members) {
      AsyncData(:final value) => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (canAdd)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.tonalIcon(
                key: const Key('addMembersButton'),
                onPressed: () async {
                  await showDialog<void>(
                    context: context,
                    builder: (_) => _AddMembersDialog(
                      group: group,
                      existing: {for (final m in value) m.person.id},
                    ),
                  );
                  onChanged();
                },
                icon: const Icon(Icons.person_add),
                label: Text(l10n.addMembers),
              ),
            ),
          if (group.isDepartment)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                l10n.departmentGroupHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          for (final m in value)
            ListTile(
              leading: PersonAvatar(m.person),
              title: Text(m.person.fullName),
              subtitle: Text(
                [_roleLabel(l10n, m.role), ?m.person.jobTitle].join(' · '),
              ),
              trailing: !group.canModerate || m.person.id == me.id
                  ? null
                  : PopupMenuButton<_MemberAction>(
                      onSelected: (a) => _act(context, ref, m, a),
                      itemBuilder: (_) => [
                        if (m.role != GroupRole.moderator &&
                            (m.role != GroupRole.owner || canManageOwners))
                          PopupMenuItem(
                            value: _MemberAction.moderator,
                            child: Text(l10n.makeModerator),
                          ),
                        if (m.role != GroupRole.owner && canManageOwners)
                          PopupMenuItem(
                            value: _MemberAction.owner,
                            child: Text(l10n.makeOwner),
                          ),
                        if (m.role != GroupRole.member &&
                            (m.role != GroupRole.owner || canManageOwners))
                          PopupMenuItem(
                            value: _MemberAction.member,
                            child: Text(l10n.makeMember),
                          ),
                        if (!group.isDepartment &&
                            (m.role != GroupRole.owner || canManageOwners))
                          PopupMenuItem(
                            value: _MemberAction.remove,
                            child: Text(l10n.removeFromGroup),
                          ),
                      ],
                    ),
            ),
        ],
      ),
      AsyncError() => Center(child: Text(l10n.errorNetwork)),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

/// Search employees and add them to the group.
class _AddMembersDialog extends ConsumerStatefulWidget {
  const _AddMembersDialog({required this.group, required this.existing});

  final WorkGroup group;
  final Set<String> existing;

  @override
  ConsumerState<_AddMembersDialog> createState() => _AddMembersDialogState();
}

class _AddMembersDialogState extends ConsumerState<_AddMembersDialog> {
  List<Person> _results = const [];
  late final Set<String> _added = {...widget.existing};

  Future<void> _search(String q) async {
    try {
      final people = await ref.read(feedRepositoryProvider).searchPeople(q);
      if (mounted) setState(() => _results = people);
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.addMembers),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          children: [
            TextField(
              key: const Key('memberSearchField'),
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: l10n.searchEmployees,
              ),
              onChanged: _search,
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final p in _results)
                    ListTile(
                      leading: PersonAvatar(p),
                      title: Text(p.fullName),
                      subtitle: p.jobTitle == null ? null : Text(p.jobTitle!),
                      trailing: _added.contains(p.id)
                          ? const Icon(Icons.check)
                          : IconButton(
                              icon: const Icon(Icons.person_add_alt),
                              onPressed: () async {
                                try {
                                  await ref
                                      .read(groupsRepositoryProvider)
                                      .addMember(widget.group.id, p.id);
                                  setState(() => _added.add(p.id));
                                } catch (_) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(l10n.errorUnknown),
                                      ),
                                    );
                                  }
                                }
                              },
                            ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.ok),
        ),
      ],
    );
  }
}
