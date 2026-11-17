import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import '../domain/auth_status.dart';
import '../domain/my_profile.dart';

/// Current login state. Updates whenever Supabase signs the user in or out,
/// refreshes the session, or accepts an authenticator code.
class AuthStatusController extends Notifier<AuthStatus> {
  @override
  AuthStatus build() {
    final repository = ref.watch(authRepositoryProvider);
    final subscription = repository.changes.listen(
      (_) => state = repository.status,
      onError: (_) => state = repository.status,
    );
    ref.onDispose(subscription.cancel);
    return repository.status;
  }
}

final authStatusProvider = NotifierProvider<AuthStatusController, AuthStatus>(
  AuthStatusController.new,
);

/// The signed-in employee's profile. `null` = not an active employee.
final myProfileProvider = FutureProvider<MyProfile?>((ref) async {
  final status = ref.watch(authStatusProvider);
  if (status != AuthStatus.signedIn) return null;
  return ref.watch(authRepositoryProvider).fetchMyProfile();
});
