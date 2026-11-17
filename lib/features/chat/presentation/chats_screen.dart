import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../auth/application/auth_providers.dart';
import '../../feed/data/feed_repository.dart';
import '../../feed/domain/person.dart';
import '../../feed/domain/rich_text.dart';
import '../../feed/presentation/feed_format.dart';
import '../../feed/presentation/person_avatar.dart';
import '../application/chat_providers.dart';
import '../data/chat_repository.dart';
import '../domain/conversation.dart';
import 'chat_screen.dart';

/// List of my chats.
class ChatsScreen extends ConsumerWidget {
  const ChatsScreen({super.key});

  static const String routePath = '/chats';
  static const String routeName = 'chats';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final chats = ref.watch(conversationsProvider);
    ref.watch(onlinePeopleProvider); // join the online channel while here

    return Scaffold(
      appBar: AppBar(title: Text(l10n.chatsTitle)),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('newChatButton'),
        onPressed: () => _newChat(context, ref),
        icon: const Icon(Icons.add_comment),
        label: Text(l10n.newChat),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: switch (chats) {
            AsyncData(:final value) when value.isEmpty => Center(
              child: Text(l10n.chatsEmpty),
            ),
            AsyncData(:final value) => RefreshIndicator(
              onRefresh: () => ref.refresh(conversationsProvider.future),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 88),
                children: [
                  for (final c in value) ConversationTile(conversation: c),
                ],
              ),
            ),
            AsyncError() => Center(
              child: TextButton.icon(
                onPressed: () => ref.invalidate(conversationsProvider),
                icon: const Icon(Icons.refresh),
                label: Text('${l10n.errorNetwork}\n${l10n.retry}'),
              ),
            ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ),
    );
  }

  Future<void> _newChat(BuildContext context, WidgetRef ref) async {
    final id = await showDialog<String>(
      context: context,
      builder: (_) => const NewChatDialog(),
    );
    if (id != null && context.mounted) {
      ref.invalidate(conversationsProvider);
      context.push(ChatScreen.pathFor(id));
    }
  }
}

class ConversationTile extends ConsumerWidget {
  const ConversationTile({
    super.key,
    required this.conversation,
    this.onOpen,
    this.selected = false,
  });

  final Conversation conversation;

  /// Opens the chat somewhere else (the home side panel). Default: new page.
  final VoidCallback? onOpen;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final me = ref.watch(myProfileProvider).value;
    final online = ref.watch(onlinePeopleProvider);
    final c = conversation;
    final last = c.lastMessage;
    String preview = '';
    if (last != null) {
      final who = last.senderId == me?.id
          ? l10n.you
          : last.senderName.split(' ').first;
      final text = last.deleted
          ? l10n.messageDeleted
          : last.body.isNotEmpty
          ? plainText(last.body)
          : (last.hasAttachment ? '📎 ${l10n.attachment}' : '');
      preview = c.isGroup || last.senderId == me?.id ? '$who: $text' : text;
    }
    final isOnline =
        !c.isGroup &&
        c.otherPerson != null &&
        online.contains(c.otherPerson!.id);
    final unread = c.unreadCount > 0;

    return ListTile(
      key: Key('chat-${c.id}'),
      leading: Stack(
        children: [
          c.isGroup
              ? CircleAvatar(
                  radius: 22,
                  backgroundColor: theme.colorScheme.tertiaryContainer,
                  child: Icon(
                    Icons.group,
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                )
              : PersonAvatar(c.avatarPerson, radius: 22),
          if (isOnline)
            PositionedDirectional(
              end: 0,
              bottom: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: const Color(0xFF7BE8A8),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.surface,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              c.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: unread
                  ? const TextStyle(fontWeight: FontWeight.bold)
                  : null,
            ),
          ),
          if (c.muted) const Icon(Icons.notifications_off_outlined, size: 16),
        ],
      ),
      subtitle: Text(
        preview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: unread ? const TextStyle(fontWeight: FontWeight.w600) : null,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (c.lastMessageAt != null)
            Text(
              timeAgo(context, c.lastMessageAt!),
              style: theme.textTheme.bodySmall,
            ),
          if (unread)
            Badge(
              label: Text('${c.unreadCount}'),
              backgroundColor: c.muted
                  ? theme.colorScheme.outline
                  : theme.colorScheme.primary,
            ),
        ],
      ),
      selected: selected,
      selectedTileColor: theme.colorScheme.primary.withValues(alpha: .10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onTap: onOpen ?? () => context.push(ChatScreen.pathFor(c.id)),
    );
  }
}

/// Pick one person (1:1 chat) or several + a name (group chat).
/// Returns the conversation id.
class NewChatDialog extends ConsumerStatefulWidget {
  const NewChatDialog({super.key});

  @override
  ConsumerState<NewChatDialog> createState() => _NewChatDialogState();
}

class _NewChatDialogState extends ConsumerState<NewChatDialog> {
  List<Person> _results = const [];
  final Map<String, Person> _picked = {};
  bool _group = false;
  bool _busy = false;
  final _title = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    try {
      final me = ref.read(myProfileProvider).value;
      final people = await ref.read(feedRepositoryProvider).searchPeople(q);
      if (mounted) {
        setState(() => _results = people.where((p) => p.id != me?.id).toList());
      }
    } catch (_) {}
  }

  Future<void> _open(Future<String> Function() action) async {
    setState(() => _busy = true);
    try {
      final id = await action();
      if (mounted) Navigator.pop(context, id);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).errorUnknown)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(chatRepositoryProvider);
    return AlertDialog(
      title: Text(_group ? l10n.newGroupChat : l10n.newChat),
      content: SizedBox(
        width: 440,
        height: 480,
        child: Column(
          children: [
            SwitchListTile(
              key: const Key('groupChatSwitch'),
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.newGroupChat),
              value: _group,
              onChanged: (v) => setState(() => _group = v),
            ),
            if (_group)
              TextField(
                key: const Key('groupChatTitleField'),
                controller: _title,
                decoration: InputDecoration(labelText: l10n.groupChatTitle),
                onChanged: (_) => setState(() {}),
              ),
            TextField(
              key: const Key('chatPeopleSearch'),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: l10n.searchEmployees,
              ),
              onChanged: _search,
            ),
            if (_group && _picked.isNotEmpty)
              Wrap(
                spacing: 4,
                children: [
                  for (final p in _picked.values)
                    InputChip(
                      label: Text(p.fullName),
                      onDeleted: () => setState(() => _picked.remove(p.id)),
                    ),
                ],
              ),
            Expanded(
              child: ListView(
                children: [
                  for (final p in _results)
                    ListTile(
                      key: Key('person-${p.id}'),
                      leading: PersonAvatar(p),
                      title: Text(p.fullName),
                      subtitle: p.jobTitle == null ? null : Text(p.jobTitle!),
                      trailing: _group
                          ? Checkbox(
                              value: _picked.containsKey(p.id),
                              onChanged: (_) => _toggle(p),
                            )
                          : null,
                      onTap: _busy
                          ? null
                          : () => _group
                                ? _toggle(p)
                                : _open(() => repo.openDirect(p.id)),
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
          child: Text(l10n.cancel),
        ),
        if (_group)
          FilledButton(
            key: const Key('createGroupChatButton'),
            onPressed: _busy || _picked.isEmpty || _title.text.trim().isEmpty
                ? null
                : () => _open(
                    () => repo.createGroup(
                      _title.text.trim(),
                      _picked.keys.toList(),
                    ),
                  ),
            child: Text(l10n.create),
          ),
      ],
    );
  }

  void _toggle(Person p) => setState(() {
    if (_picked.remove(p.id) == null) _picked[p.id] = p;
  });
}
