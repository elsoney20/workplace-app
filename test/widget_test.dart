import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workplace_app/app.dart';
import 'package:workplace_app/core/config/brand_config.dart';
import 'package:workplace_app/core/l10n/locale_controller.dart';
import 'package:workplace_app/core/supabase/backend_status_provider.dart';
import 'package:workplace_app/features/home/presentation/home_screen.dart';

Future<void> _pumpApp(WidgetTester tester, {required String locale}) async {
  SharedPreferences.setMockInitialValues({'app_locale': locale});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        backendStatusProvider.overrideWith((ref) async => BackendStatus.online),
      ],
      child: const WorkplaceApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('English renders left to right', (tester) async {
    await _pumpApp(tester, locale: 'en');

    expect(find.text('Welcome to ${BrandConfig.appName}'), findsOneWidget);
    final context = tester.element(find.byType(HomeScreen));
    expect(Directionality.of(context), TextDirection.ltr);
  });

  testWidgets('Arabic renders right to left', (tester) async {
    await _pumpApp(tester, locale: 'ar');

    expect(find.text('أهلاً بك في ${BrandConfig.appNameAr}'), findsOneWidget);
    final context = tester.element(find.byType(HomeScreen));
    expect(Directionality.of(context), TextDirection.rtl);
  });

  testWidgets('Switching language updates direction', (tester) async {
    await _pumpApp(tester, locale: 'en');

    await tester.tap(find.text('العربية'));
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(HomeScreen));
    expect(Directionality.of(context), TextDirection.rtl);
  });
}
