import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../auth/application/auth_providers.dart';
import '../../groups/data/groups_repository.dart';
import '../data/feed_repository.dart';
import '../domain/feed_post.dart';
import '../domain/feed_scope.dart';
import 'post_card.dart';

final singlePostProvider = FutureProvider.autoDispose.family<FeedPost?, String>(
  (ref, id) => ref.watch(feedRepositoryProvider).fetchPost(id),
);

/// One post on its own page (opened from a notification, search or report).
class PostScreen extends ConsumerWidget {
  const PostScreen({super.key, required this.postId});

  final String postId;

  static const String routePath = '/posts/:id';
  static const String routeName = 'post';
  static String pathFor(String id) => '/posts/$id';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final me = ref.watch(myProfileProvider).value;
    final post = ref.watch(singlePostProvider(postId));

    Widget body;
    switch (post) {
      case AsyncData(value: final p?) when me != null:
        final group = p.groupId == null
            ? null
            : ref.watch(groupProvider(p.groupId!)).value;
        final scope = FeedScope(
          groupId: p.groupId,
          canModerate: p.groupId == null
              ? me.isAdmin
              : (group?.canModerate ?? false),
        );
        body = ListView(
          padding: const EdgeInsets.all(12),
          children: [PostCard(post: p, me: me, scope: scope)],
        );
      case AsyncData(value: null):
        body = Center(child: Text(l10n.postNotFound));
      case AsyncError():
        body = Center(
          child: TextButton.icon(
            onPressed: () => ref.invalidate(singlePostProvider(postId)),
            icon: const Icon(Icons.refresh),
            label: Text('${l10n.errorNetwork}\n${l10n.retry}'),
          ),
        );
      default:
        body = const Center(child: CircularProgressIndicator());
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.postTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: body,
        ),
      ),
    );
  }
}
