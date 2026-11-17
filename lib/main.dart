import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/config/app_env.dart';
import 'core/diagnostics/frame_diagnostics.dart';
import 'core/l10n/locale_controller.dart';
import 'core/supabase/supabase_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!AppEnv.isConfigured) {
    runApp(const _MissingConfigApp());
    return;
  }

  await SupabaseBootstrap.initialize();
  final prefs = await SharedPreferences.getInstance();

  FrameDiagnostics.startIfEnabled();
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const WorkplaceApp(),
    ),
  );
}

/// Shown to developers when the app was started without env.json.
class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Missing Supabase configuration.\n\n'
              'Copy env.example.json to env.json, fill in your values, '
              'then run:\n'
              'flutter run -d windows --dart-define-from-file=env.json',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
