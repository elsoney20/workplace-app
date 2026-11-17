import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../data/feed_repository.dart';
import '../domain/person.dart';
import 'animated_emoji.dart';
import 'feed_format.dart';
import 'person_avatar.dart';

/// Who saw an announcement, newest first.
Future<void> showSeenByDialog(
  BuildContext context, {
  required String postId,
  int? total,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _PeopleDialog<(Person, DateTime)>(
      title: AppLocalizations.of(context).seenByTitle,
      load: (ref) => ref.read(feedRepositoryProvider).fetchViewers(postId),
      empty: AppLocalizations.of(context).nobodySeenYet,
      header: (items) => total == null
          ? null
          : AppLocalizations.of(context).seenByOf(items.length, total),
      tile: (context, item) => ListTile(
        leading: PersonAvatar(item.$1),
        title: Text(item.$1.fullName),
        subtitle: item.$1.jobTitle == null ? null : Text(item.$1.jobTitle!),
        trailing: Text(
          fullTime(context, item.$2),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ),
  );
}

/// Who reacted, with a filter per emoji.
Future<void> showReactorsDialog(
  BuildContext context, {
  String? postId,
  String? commentId,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _ReactorsDialog(postId: postId, commentId: commentId),
  );
}

class _ReactorsDialog extends ConsumerStatefulWidget {
  const _ReactorsDialog({this.postId, this.commentId});

  final String? postId;
  final String? commentId;

  @override
  ConsumerState<_ReactorsDialog> createState() => _ReactorsDialogState();
}

class _ReactorsDialogState extends ConsumerState<_ReactorsDialog> {
  late final Future<List<(Person, String)>> _future = ref
      .read(feedRepositoryProvider)
      .fetchReactors(postId: widget.postId, commentId: widget.commentId);
  String? _filter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.reactionsTitle),
      content: SizedBox(
        width: 420,
        height: 420,
        child: FutureBuilder(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text(l10n.errorNetwork));
            }
            final items = snapshot.data;
            if (items == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final counts = <String, int>{};
            for (final (_, e) in items) {
              counts[e] = (counts[e] ?? 0) + 1;
            }
            final shown = _filter == null
                ? items
                : items.where((i) => i.$2 == _filter).toList();
            return Column(
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: Text('${l10n.allReactions} ${items.length}'),
                        selected: _filter == null,
                        onSelected: (_) => setState(() => _filter = null),
                      ),
                      for (final e in counts.entries) ...[
                        const SizedBox(width: 6),
                        ChoiceChip(
                          avatar: AnimatedEmoji(e.key, size: 20),
                          label: Text('${e.value}'),
                          selected: _filter == e.key,
                          onSelected: (_) => setState(() => _filter = e.key),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    children: [
                      for (final (person, emoji) in shown)
                        ListTile(
                          leading: PersonAvatar(person),
                          title: Text(person.fullName),
                          subtitle: person.jobTitle == null
                              ? null
                              : Text(person.jobTitle!),
                          trailing: AnimatedEmoji(emoji, size: 28),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
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

class _PeopleDialog<T> extends ConsumerStatefulWidget {
  const _PeopleDialog({
    required this.title,
    required this.load,
    required this.empty,
    required this.tile,
    this.header,
  });

  final String title;
  final Future<List<T>> Function(WidgetRef ref) load;
  final String empty;
  final Widget Function(BuildContext context, T item) tile;
  final String? Function(List<T> items)? header;

  @override
  ConsumerState<_PeopleDialog<T>> createState() => _PeopleDialogState<T>();
}

class _PeopleDialogState<T> extends ConsumerState<_PeopleDialog<T>> {
  late final Future<List<T>> _future = widget.load(ref);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        height: 420,
        child: FutureBuilder(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text(l10n.errorNetwork));
            }
            final items = snapshot.data;
            if (items == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (items.isEmpty) return Center(child: Text(widget.empty));
            final header = widget.header?.call(items);
            return ListView(
              children: [
                if (header != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      header,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                for (final item in items) widget.tile(context, item),
              ],
            );
          },
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
