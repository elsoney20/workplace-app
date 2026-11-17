import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provided in `main()` after [SharedPreferences.getInstance] completes.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main().',
  ),
);

/// The language the user picked, or `null` to follow the OS language.
///
/// Stored on the device. Saving it to the profile (so it follows the user
/// across devices) is planned for a later phase.
class LocaleController extends Notifier<Locale?> {
  static const String _storageKey = 'app_locale';

  @override
  Locale? build() {
    final code = ref.watch(sharedPreferencesProvider).getString(_storageKey);
    return code == null ? null : Locale(code);
  }

  Future<void> setLocale(Locale? locale) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (locale == null) {
      await prefs.remove(_storageKey);
    } else {
      await prefs.setString(_storageKey, locale.languageCode);
    }
    state = locale;
  }
}

final localeControllerProvider = NotifierProvider<LocaleController, Locale?>(
  LocaleController.new,
);
