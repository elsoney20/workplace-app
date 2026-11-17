import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_env.dart';

/// Initializes the Supabase client once at startup.
abstract final class SupabaseBootstrap {
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: AppEnv.supabaseUrl,
      publishableKey: AppEnv.supabasePublishableKey,
    );
  }
}

/// Access the Supabase client through Riverpod so it can be mocked in tests.
final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);
