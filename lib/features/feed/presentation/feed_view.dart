import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../auth/domain/my_profile.dart';
import '../application/feed_controller.dart';
import 'person_avatar.dart';
import 'post_card.dart';
import 'post_composer_dialog.dart';
import '../domain/person.dart';

/// The company feed: "write a post" box, pinned announcements, then posts.
class FeedView extends ConsumerStatefulWidget {
  const FeedView({super.key, required this.me, this.header});

  final MyProfile me;

  /// Shown above the composer (e.g. greeting + shortcuts).
  final Widget? header;

  @override
  ConsumerState<FeedView> createState() => _FeedViewState();
}

class _FeedViewState extends ConsumerState<FeedView> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 600) {
        ref.read(feedControllerProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _filter(String? tag) {
    ref.read(hashtagFilterProvider.notifier).set(tag);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _compose() async {
    if (await showPostComposer(context, me: widget.me)) {
      await ref.read(feedControllerProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final feed = ref.watch(feedControllerProvider);
    final tag = ref.watch(hashtagFilterProvider);
    final me = Person(
      id: widget.me.id,
      fullName: widget.me.fullName,
      jobTitle: widget.me.jobTitle,
    );

    final children = <Widget>[
      ?widget.header,
      Card(
        child: InkWell(
          key: const Key('openComposer'),
          borderRadius: BorderRadius.circular(12),
          onTap: _compose,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                PersonAvatar(me),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Text(
                      l10n.composerPrompt(widget.me.fullName.split(' ').first),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.photo_library_outlined),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      if (tag != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.showingHashtag(tag),
                  style: theme.textTheme.titleMedium,
                ),
              ),
              TextButton.icon(
                key: const Key('clearHashtag'),
                onPressed: () => _filter(null),
                icon: const Icon(Icons.close),
                label: Text(l10n.clearFilter),
              ),
            ],
          ),
        )
      else
        _TrendingRow(onTap: _filter),
    ];

    switch (feed) {
      case AsyncData(:final value):
        for (final p in value.pinned) {
          children.add(
            PostCard(
              key: ValueKey('pinned-${p.id}'),
              post: p,
              me: widget.me,
              onHashtag: _filter,
            ),
          );
        }
        if (value.pinned.isEmpty && value.posts.isEmpty) {
          children.add(
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(
                  tag == null ? l10n.feedEmpty : l10n.feedEmptyHashtag(tag),
                ),
              ),
            ),
          );
        }
        for (final p in value.posts) {
          children.add(
            PostCard(
              key: ValueKey(p.id),
              post: p,
              me: widget.me,
              onHashtag: _filter,
            ),
          );
        }
        if (value.loadingMore) {
          children.add(
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        } else if (value.hasMore && value.posts.isNotEmpty) {
          children.add(
            Center(
              child: TextButton(
                onPressed: () =>
                    ref.read(feedControllerProvider.notifier).loadMore(),
                child: Text(l10n.loadMore),
              ),
            ),
          );
        }
      case AsyncError():
        children.add(
          Center(
            child: TextButton.icon(
              onPressed: () => ref.invalidate(feedControllerProvider),
              icon: const Icon(Icons.refresh),
              label: Text('${l10n.errorNetwork}\n${l10n.retry}'),
            ),
          ),
        );
      default:
        children.add(
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
        );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(feedControllerProvider.notifier).refresh(),
      child: ListView(
        key: const Key('feedList'),
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
        children: children,
      ),
    );
  }
}

class _TrendingRow extends ConsumerWidget {
  const _TrendingRow({required this.onTap});

  final void Function(String tag) onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tags = ref.watch(trendingHashtagsProvider).value ?? const [];
    if (tags.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Text(
              '${l10n.trending}: ',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            for (final (tag, _) in tags) ...[
              ActionChip(label: Text('#$tag'), onPressed: () => onTap(tag)),
              const SizedBox(width: 6),
            ],
          ],
        ),
      ),
    );
  }
}
