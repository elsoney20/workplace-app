import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../data/notifications_repository.dart';
import 'desktop_notifier.dart';

/// Bumped when a new notification arrives; lists and badges reload.
class NotificationsTick extends Notifier<int> {
  @override
  int build() {
    final me = ref.watch(myProfileProvider).value;
    if (me == null) return 0;
    final repo = ref.watch(notificationsRepositoryProvider);
    final channel = repo.watch((row) {
      state++;
      unawaited(ref.read(desktopNotifierProvider).showForNotificationRow(row));
    });
    ref.onDispose(
      () => unawaited(repo.stop(channel).catchError((_) => 'error')),
    );
    return 0;
  }
}

final notificationsTickProvider = NotifierProvider<NotificationsTick, int>(
  NotificationsTick.new,
);

final unreadNotificationsProvider = FutureProvider<int>((ref) async {
  ref.watch(notificationsTickProvider);
  if (ref.watch(myProfileProvider).value == null) return 0;
  return ref.watch(notificationsRepositoryProvider).unreadCount();
});

final notificationsListProvider =
    FutureProvider.autoDispose<List<AppNotification>>((ref) async {
      ref.watch(notificationsTickProvider);
      return ref.watch(notificationsRepositoryProvider).list();
    });
