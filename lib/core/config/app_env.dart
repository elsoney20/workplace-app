/// Environment values injected at build time with
/// `--dart-define-from-file=env.json`.
///
/// Only the Supabase *publishable* (anon) key belongs here. It is safe to
/// ship inside the app because every table is protected by Row Level
/// Security. The secret / service_role key must never be added to the app.
abstract final class AppEnv {
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  static const String supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
