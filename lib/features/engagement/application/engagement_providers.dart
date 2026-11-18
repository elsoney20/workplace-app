import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../chat/application/chat_providers.dart';
import '../../feed/domain/person.dart';
import '../data/engagement_repository.dart';
import '../domain/home_sidebar.dart';

/// The home side columns. Refreshed after my own changes (going, kudos...).
final homeSidebarProvider = FutureProvider<HomeSidebar>(
  (ref) => ref.watch(engagementRepositoryProvider).fetchSidebar(),
);

/// Cards of the people online right now (me left out).
final onlineCardsProvider = FutureProvider<List<Person>>((ref) async {
  final ids = ref.watch(onlinePeopleProvider);
  return ref.watch(engagementRepositoryProvider).fetchPeople(ids);
});
