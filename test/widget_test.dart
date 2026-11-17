import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workplace_app/app.dart';
import 'package:workplace_app/core/l10n/locale_controller.dart';
import 'package:workplace_app/features/auth/application/auth_providers.dart';
import 'package:workplace_app/features/auth/domain/auth_status.dart';
import 'package:workplace_app/features/auth/domain/my_profile.dart';
import 'package:workplace_app/features/auth/presentation/login_screen.dart';
import 'package:workplace_app/features/auth/presentation/second_factor_screen.dart';
import 'package:workplace_app/features/home/presentation/home_screen.dart';

class _FakeAuthStatus extends AuthStatusController {
  _FakeAuthStatus(this.initial);

  final AuthStatus initial;

  @override
  AuthStatus build() => initial;
}

const _admin = MyProfile(
  id: 'a1',
  fullName: 'Owner',
  phone: '+201001234567',
  role: 'admin',
  jobTitle: 'CEO',
);

Future<void> _pumpApp(
  WidgetTester tester, {
  required String locale,
  AuthStatus status = AuthStatus.signedOut,
  MyProfile? profile,
}) async {
  SharedPreferences.setMockInitialValues({'app_locale': locale});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authStatusProvider.overrideWith(() => _FakeAuthStatus(status)),
        myProfileProvider.overrideWith((ref) async => profile),
      ],
      child: const WorkplaceApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Signed-out users see the login screen (English, LTR)', (
    tester,
  ) async {
    await _pumpApp(tester, locale: 'en');

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Send code'), findsOneWidget);
    final context = tester.element(find.byType(LoginScreen));
    expect(Directionality.of(context), TextDirection.ltr);
  });

  testWidgets('Login screen in Arabic is right to left', (tester) async {
    await _pumpApp(tester, locale: 'ar');

    expect(find.text('إرسال الكود'), findsOneWidget);
    final context = tester.element(find.byType(LoginScreen));
    expect(Directionality.of(context), TextDirection.rtl);
  });

  testWidgets('An invalid phone number shows an error', (tester) async {
    await _pumpApp(tester, locale: 'en');

    await tester.enterText(find.byKey(const Key('phoneField')), '123');
    await tester.tap(find.byKey(const Key('sendCodeButton')));
    await tester.pumpAndSettle();

    expect(find.text('Please enter a valid mobile number.'), findsOneWidget);
  });

  testWidgets('Authenticator users are asked for the app code', (tester) async {
    await _pumpApp(tester, locale: 'en', status: AuthStatus.needsSecondFactor);

    expect(find.byType(SecondFactorScreen), findsOneWidget);
  });

  testWidgets('Admins see their name and the admin panel button', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      locale: 'en',
      status: AuthStatus.signedIn,
      profile: _admin,
    );

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Hello, Owner'), findsOneWidget);
    expect(find.byKey(const Key('openAdminPanel')), findsOneWidget);
  });

  testWidgets('Employees do not see the admin panel button', (tester) async {
    await _pumpApp(
      tester,
      locale: 'ar',
      status: AuthStatus.signedIn,
      profile: const MyProfile(
        id: 'e1',
        fullName: 'Sara',
        phone: '+201000000002',
        role: 'employee',
      ),
    );

    expect(find.text('أهلاً يا Sara'), findsOneWidget);
    expect(find.byKey(const Key('openAdminPanel')), findsNothing);
  });
}
