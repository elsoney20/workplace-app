import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workplace_app/app.dart';
import 'package:workplace_app/core/l10n/locale_controller.dart';
import 'package:workplace_app/features/auth/application/auth_providers.dart';
import 'package:workplace_app/features/auth/data/auth_repository.dart';
import 'package:workplace_app/features/auth/domain/auth_status.dart';

class _SignedOut extends AuthStatusController {
  @override
  AuthStatus build() => AuthStatus.signedOut;
}

class _FakeAuth implements AuthRepository {
  final List<String> tried = [];

  @override
  Future<void> sendCode(String phoneE164) async {}

  @override
  Future<void> verifyCode(String phoneE164, String code) async {
    tried.add(code);
    if (code != '123456') throw Exception('wrong');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_FakeAuth> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'app_locale': 'en'});
  final prefs = await SharedPreferences.getInstance();
  final auth = _FakeAuth();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authStatusProvider.overrideWith(_SignedOut.new),
        authRepositoryProvider.overrideWithValue(auth),
      ],
      child: const WorkplaceApp(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('phoneField')), '01065111122');
  await tester.tap(find.byKey(const Key('sendCodeButton')));
  await tester.pumpAndSettle();
  return auth;
}

void main() {
  testWidgets('six digits check the code by themselves and show the result', (
    tester,
  ) async {
    final auth = await _pump(tester);
    expect(find.byKey(const Key('codeField')), findsOneWidget);
    expect(find.byKey(const Key('resendCode')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('codeField')), '111111');
    await tester.pumpAndSettle();
    expect(auth.tried, ['111111']);
    expect(find.textContaining('Something went wrong'), findsWidgets);

    // Typing again clears the error; the right code shows the check.
    await tester.enterText(find.byKey(const Key('codeField')), '12345');
    await tester.pump();
    await tester.enterText(find.byKey(const Key('codeField')), '123456');
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('Code is correct'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(auth.tried, ['111111', '123456']);
  });
}
