import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../chat/presentation/chat_drawer.dart';
import '../../directory/data/directory_repository.dart';
import '../../directory/presentation/directory_screen.dart';
import '../../feed/domain/rich_text.dart';
import '../../feed/presentation/feed_format.dart';
import '../../feed/presentation/person_avatar.dart';
import '../../feed/presentation/post_screen.dart';
import '../data/search_repository.dart';

final _searchQueryProvider = NotifierProvider<_Query, String>(_Query.new);

class _Query extends Notifier<String> {
  @override
  String build() => '';
  void set(String value) => state = value.trim();
}

final _peopleResults = FutureProvider.autoDispose<List<DirectoryEntry>>((ref) {
  final q = ref.watch(_searchQueryProvider);
  if (q.length < SearchRepository.minLength) return const [];
  return ref.watch(directoryRepositoryProvider).list(query: q);
});

final _postResults = FutureProvider.autoDispose<List<SearchHit>>((ref) {
  final q = ref.watch(_searchQueryProvider);
  if (q.length < SearchRepository.minLength) return const [];
  return ref.watch(searchRepositoryProvider).posts(q);
});

final _messageResults = FutureProvider.autoDispose<List<SearchHit>>((ref) {
  final q = ref.watch(_searchQueryProvider);
  if (q.length < SearchRepository.minLength) return const [];
  return ref.watch(searchRepositoryProvider).messages(q);
});

/// One search box, three tabs: people, posts, my messages.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  static const String routePath = '/search';
  static const String routeName = 'search';

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) ref.read(_searchQueryProvider.notifier).set(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final query = ref.watch(_searchQueryProvider);
    final tooShort = query.length < SearchRepository.minLength;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: TextField(
            key: const Key('searchField'),
            controller: _controller,
            autofocus: true,
            onChanged: _onChanged,
            onSubmitted: (v) => ref.read(_searchQueryProvider.notifier).set(v),
            decoration: InputDecoration(
              hintText: l10n.searchHint,
              border: InputBorder.none,
              prefixIcon: const Icon(Icons.search),
            ),
          ),
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.searchPeople),
              Tab(text: l10n.searchPosts),
              Tab(text: l10n.searchMessages),
            ],
          ),
        ),
        body: tooShort
            ? Center(child: Text(l10n.searchTypeMore))
            : TabBarView(
                children: [
                  _Results<DirectoryEntry>(
                    provider: _peopleResults,
                    itemBuilder: (context, e) => ListTile(
                      leading: PersonAvatar(e.person),
                      title: Text(e.person.fullName),
                      subtitle: Text(
                        [
                          if (e.person.jobTitle != null) e.person.jobTitle!,
                          if (e.department(
                                Localizations.localeOf(context).languageCode,
                              ) !=
                              null)
                            e.department(
                              Localizations.localeOf(context).languageCode,
                            )!,
                        ].join(' · '),
                      ),
                      onTap: () => showPersonCard(context, e),
                    ),
                  ),
                  _Results<SearchHit>(
                    provider: _postResults,
                    itemBuilder: (context, h) => _HitTile(
                      hit: h,
                      onTap: () => context.push(PostScreen.pathFor(h.id)),
                    ),
                  ),
                  _Results<SearchHit>(
                    provider: _messageResults,
                    itemBuilder: (context, h) => _HitTile(
                      hit: h,
                      onTap: h.contextId == null
                          ? null
                          : () => ref
                                .read(chatDrawerProvider.notifier)
                                .openChat(h.contextId!),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _Results<T> extends ConsumerWidget {
  const _Results({required this.provider, required this.itemBuilder});

  final FutureProvider<List<T>> provider;
  final Widget Function(BuildContext, T) itemBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ref
        .watch(provider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: TextButton(
              onPressed: () => ref.invalidate(provider),
              child: Text(l10n.retry),
            ),
          ),
          data: (items) => items.isEmpty
              ? Center(child: Text(l10n.noResults))
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, i) =>
                          itemBuilder(context, items[i]),
                    ),
                  ),
                ),
        );
  }
}

class _HitTile extends StatelessWidget {
  const _HitTile({required this.hit, this.onTap});

  final SearchHit hit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: PersonAvatar(hit.person),
      title: Text(
        [
          hit.person.fullName,
          if (hit.contextTitle != null) hit.contextTitle!,
        ].join(' · '),
      ),
      subtitle: Text(
        '${plainText(hit.body)}\n${timeAgo(context, hit.createdAt)}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      onTap: onTap,
    );
  }
}
