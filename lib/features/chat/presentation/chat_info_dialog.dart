import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../auth/domain/my_profile.dart';
import '../../feed/data/feed_repository.dart';
import '../../feed/domain/person.dart';
import '../../feed/presentation/person_avatar.dart';
import '../application/chat_providers.dart';
import '../data/chat_repository.dart';
import '../domain/conversation.dart';

final _membersProvider = FutureProvider.autoDispose
    .family<List<(Person, bool)>, String>(
      (ref, id) => ref.watch(chatRepositoryProvider).fetchMembers(id),
    );

/// Members, rename, add people, mute, leave. Returns true if I left.
Future<bool> showChatInfoDialog(
  BuildContext context, {
  required Conversation conversation,
  required MyProfile me,
}) async {
  final left = await showDialog<bool>(
    context: context,
    builder: (_) => _ChatInfoDialog(conversation: conversation, me: me),
  );
  return left ?? false;
}

class _ChatInfoDialog extends ConsumerStatefulWidget {
  const _ChatInfoDialog({required this.conversation, required this.me});

  final Conversation conversation;
  final MyProfile me;

  @override
  ConsumerState<_ChatInfoDialog> createState() => _ChatInfoDialogState();
}

class _ChatInfoDialogState extends ConsumerState<_ChatInfoDialog> {
  late bool _muted = widget.conversation.muted;

  Conversation get c => widget.conversation;

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      ref.invalidate(_membersProvider(c.id));
      ref.invalidate(conversationsProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).errorUnknown)),
        );
      }
    }
  }

  Future<void> _rename() async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: c.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.renameChat),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 120,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title != null && title.isNotEmpty) {
      await _run(() => ref.read(chatRepositoryProvider).rename(c.id, title));
    }
  }

  Future<void> _addPeople(Set<String> existing) async {
    await showDialog<void>(
      context: context,
      builder: (_) =>
          _AddPeopleDialog(conversationId: c.id, existing: existing),
    );
    ref.invalidate(_membersProvider(c.id));
    ref.invalidate(conversationsProvider);
  }

  Future<void> _leave() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l10n.leaveChatConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.leaveChat),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(chatRepositoryProvider).leave(c.id);
      ref.invalidate(conversationsProvider);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.errorUnknown)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final members = ref.watch(_membersProvider(c.id));
    final online = ref.watch(onlinePeopleProvider);
    return AlertDialog(
      title: Text(c.displayName),
      content: SizedBox(
        width: 440,
        height: 460,
        child: ListView(
          children: [
            Row(
              children: [
                const Icon(Icons.lock_outline, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.chatPrivacyNote,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.notifications_off_outlined),
              title: Text(l10n.muteChat),
              value: _muted,
              onChanged: (v) {
                setState(() => _muted = v);
                _run(
                  () => ref
                      .read(chatRepositoryProvider)
                      .setMuted(c.id, widget.me.id, muted: v),
                );
              },
            ),
            if (c.isGroup && c.isOwner)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.edit),
                title: Text(l10n.renameChat),
                onTap: _rename,
              ),
            const Divider(),
            switch (members) {
              AsyncData(:final value) => Column(
                children: [
                  if (c.isGroup && c.isOwner)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.person_add),
                      title: Text(l10n.addMembers),
                      onTap: () =>
                          _addPeople({for (final (p, _) in value) p.id}),
                    ),
                  for (final (person, owner) in value)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: PersonAvatar(person),
                      title: Text(
                        person.id == widget.me.id
                            ? '${person.fullName} (${l10n.you})'
                            : person.fullName,
                      ),
                      subtitle: Text(
                        [
                          if (owner && c.isGroup) l10n.roleOwner,
                          online.contains(person.id)
                              ? l10n.online
                              : l10n.offline,
                        ].join(' · '),
                      ),
                      trailing:
                          c.isGroup && c.isOwner && person.id != widget.me.id
                          ? IconButton(
                              tooltip: l10n.removeFromGroup,
                              icon: const Icon(Icons.person_remove_outlined),
                              onPressed: () => _run(
                                () => ref
                                    .read(chatRepositoryProvider)
                                    .removeMember(c.id, person.id),
                              ),
                            )
                          : null,
                    ),
                ],
              ),
              AsyncError() => Text(l10n.errorNetwork),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ],
        ),
      ),
      actions: [
        if (c.isGroup)
          TextButton(
            onPressed: _leave,
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(l10n.leaveChat),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.ok),
        ),
      ],
    );
  }
}

class _AddPeopleDialog extends ConsumerStatefulWidget {
  const _AddPeopleDialog({
    required this.conversationId,
    required this.existing,
  });

  final String conversationId;
  final Set<String> existing;

  @override
  ConsumerState<_AddPeopleDialog> createState() => _AddPeopleDialogState();
}

class _AddPeopleDialogState extends ConsumerState<_AddPeopleDialog> {
  List<Person> _results = const [];
  late final Set<String> _added = {...widget.existing};

  @override
  void initState() {
    super.initState();
    _search('');
  }

  Future<void> _search(String q) async {
    try {
      final people = await ref.read(feedRepositoryProvider).searchPeople(q);
      if (mounted) setState(() => _results = people);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.addMembers),
      content: SizedBox(
        width: 400,
        height: 400,
        child: Column(
          children: [
            TextField(
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
                      trailing: _added.contains(p.id)
                          ? const Icon(Icons.check)
                          : IconButton(
                              icon: const Icon(Icons.person_add_alt),
                              onPressed: () async {
                                try {
                                  await ref
                                      .read(chatRepositoryProvider)
                                      .addMember(widget.conversationId, p.id);
                                  setState(() => _added.add(p.id));
                                } catch (_) {}
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
