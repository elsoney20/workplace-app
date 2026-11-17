import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../auth/application/auth_providers.dart';
import '../data/groups_repository.dart';
import '../domain/work_group.dart';
import 'group_form_dialog.dart';
import 'group_screen.dart';

/// List of my groups + all groups I can discover.
class GroupsScreen extends ConsumerStatefulWidget {
  const GroupsScreen({super.key});

  static const String routePath = '/groups';
  static const String routeName = 'groups';

  @override
  ConsumerState<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends ConsumerState<GroupsScreen> {
  String _query = '';

  Future<void> _create() async {
    final id = await showGroupFormDialog(context);
    if (id == null || !mounted) return;
    ref.invalidate(myGroupsProvider);
    ref.invalidate(allGroupsProvider);
    context.push(GroupScreen.pathFor(id));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final me = ref.watch(myProfileProvider).value;
    final canCreate = me != null && (me.isAdmin || me.role == 'manager');

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.groupsTitle),
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.myGroups),
              Tab(text: l10n.discoverGroups),
            ],
          ),
        ),
        floatingActionButton: canCreate
            ? FloatingActionButton.extended(
                key: const Key('createGroupButton'),
                onPressed: _create,
                icon: const Icon(Icons.group_add),
                label: Text(l10n.createGroup),
              )
            : null,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: TabBarView(
              children: [
                _GroupList(provider: myGroupsProvider, empty: l10n.groupsEmpty),
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: TextField(
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: l10n.searchGroups,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) =>
                            setState(() => _query = v.trim().toLowerCase()),
                      ),
                    ),
                    Expanded(
                      child: _GroupList(
                        provider: allGroupsProvider,
                        empty: l10n.noGroupsFound,
                        filter: (g) =>
                            _query.isEmpty ||
                            g.name.toLowerCase().contains(_query),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupList extends ConsumerWidget {
  const _GroupList({required this.provider, required this.empty, this.filter});

  final ProviderListenable<AsyncValue<List<WorkGroup>>> provider;
  final String empty;
  final bool Function(WorkGroup)? filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return switch (ref.watch(provider)) {
      AsyncData(:final value) => () {
        final groups = filter == null ? value : value.where(filter!).toList();
        if (groups.isEmpty) return Center(child: Text(empty));
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(myGroupsProvider);
            ref.invalidate(allGroupsProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
            children: [for (final g in groups) GroupTile(group: g)],
          ),
        );
      }(),
      AsyncError() => Center(
        child: TextButton.icon(
          onPressed: () {
            ref.invalidate(myGroupsProvider);
            ref.invalidate(allGroupsProvider);
          },
          icon: const Icon(Icons.refresh),
          label: Text('${l10n.errorNetwork}\n${l10n.retry}'),
        ),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class GroupTile extends StatelessWidget {
  const GroupTile({super.key, required this.group});

  final WorkGroup group;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final icon = group.isDepartment
        ? Icons.apartment
        : group.privacy == GroupPrivacy.private
        ? Icons.lock_outline
        : Icons.groups;
    final kind = group.isDepartment
        ? l10n.departmentGroup
        : group.privacy == GroupPrivacy.private
        ? l10n.groupPrivate
        : l10n.groupPublic;
    return Card(
      child: ListTile(
        key: Key('group-${group.id}'),
        leading: CircleAvatar(
          backgroundColor: scheme.secondaryContainer,
          child: Icon(icon, color: scheme.onSecondaryContainer),
        ),
        title: Text(group.name),
        subtitle: Text('$kind · ${l10n.memberCount(group.memberCount)}'),
        trailing: group.isMember
            ? null
            : Text(l10n.joinGroup, style: TextStyle(color: scheme.primary)),
        onTap: () => context.push(GroupScreen.pathFor(group.id)),
      ),
    );
  }
}
