import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../feed/domain/rich_text.dart';
import '../../feed/presentation/feed_format.dart';
import '../../feed/presentation/person_avatar.dart';
import '../../feed/presentation/post_screen.dart';
import '../../groups/presentation/group_screen.dart';
import '../application/notifications_providers.dart';
import '../data/notifications_repository.dart';

String notificationTitle(AppLocalizations l10n, AppNotification n) {
  final name = n.actor?.fullName ?? l10n.someone;
  return switch (n.type) {
    'mention' => l10n.notifMention(name),
    'comment' => l10n.notifComment(name),
    'reply' => l10n.notifReply(name),
    'reaction' => l10n.notifReaction(name),
    'announcement' => l10n.notifAnnouncement(name),
    'group_invite' => l10n.notifGroupInvite(name),
    'report_update' => l10n.notifReportUpdate,
    _ => l10n.notificationsTitle,
  };
}

IconData _iconFor(String type) => switch (type) {
  'mention' => Icons.alternate_email,
  'comment' || 'reply' => Icons.mode_comment_outlined,
  'reaction' => Icons.emoji_emotions_outlined,
  'announcement' => Icons.campaign_outlined,
  'group_invite' => Icons.group_add_outlined,
  'report_update' => Icons.flag_outlined,
  _ => Icons.notifications_outlined,
};

/// Where a notification (or a clicked Windows toast) leads.
void openNotificationTarget(BuildContext context, Map<String, dynamic> target) {
  final postId = target['post_id'] as String?;
  final groupId = target['group_id'] as String?;
  if (postId != null) {
    context.push(PostScreen.pathFor(postId));
  } else if (groupId != null) {
    context.push(GroupScreen.pathFor(groupId));
  }
}

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  static const String routePath = '/notifications';
  static const String routeName = 'notifications';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final list = ref.watch(notificationsListProvider);
    final repo = ref.read(notificationsRepositoryProvider);

    Future<void> markAll() async {
      await repo.markRead();
      ref.invalidate(notificationsListProvider);
      ref.invalidate(unreadNotificationsProvider);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.notificationsTitle),
        actions: [
          TextButton.icon(
            key: const Key('markAllRead'),
            onPressed: markAll,
            icon: const Icon(Icons.done_all),
            label: Text(l10n.markAllRead),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: switch (list) {
            AsyncData(:final value) when value.isEmpty => Center(
              child: Text(l10n.notificationsEmpty),
            ),
            AsyncData(:final value) => ListView(
              children: [
                for (final n in value)
                  ListTile(
                    key: Key('notification-${n.id}'),
                    tileColor: n.isRead
                        ? null
                        : theme.colorScheme.primaryContainer.withValues(
                            alpha: 0.35,
                          ),
                    leading: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        n.actor == null
                            ? const CircleAvatar(
                                child: Icon(Icons.flag_outlined),
                              )
                            : PersonAvatar(n.actor!),
                        PositionedDirectional(
                          end: -4,
                          bottom: -4,
                          child: CircleAvatar(
                            radius: 10,
                            backgroundColor: theme.colorScheme.primary,
                            child: Icon(
                              _iconFor(n.type),
                              size: 12,
                              color: theme.colorScheme.onPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    title: Text(
                      notificationTitle(l10n, n),
                      style: n.isRead
                          ? null
                          : const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      [
                        if (n.preview != null) plainText(n.preview!),
                        timeAgo(context, n.createdAt),
                      ].join('\n'),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () async {
                      if (!n.isRead) {
                        await repo.markRead([n.id]);
                        ref.invalidate(unreadNotificationsProvider);
                        ref.invalidate(notificationsListProvider);
                      }
                      if (context.mounted) {
                        openNotificationTarget(context, n.target);
                      }
                    },
                  ),
              ],
            ),
            AsyncError() => Center(
              child: TextButton.icon(
                onPressed: () => ref.invalidate(notificationsListProvider),
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
}
