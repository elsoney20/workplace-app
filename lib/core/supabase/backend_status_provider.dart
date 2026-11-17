import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../config/app_env.dart';

enum BackendStatus { online, offline }

/// Pings the Supabase Auth health endpoint to confirm the URL and key work.
final backendStatusProvider = FutureProvider.autoDispose<BackendStatus>((
  ref,
) async {
  final uri = Uri.parse('${AppEnv.supabaseUrl}/auth/v1/health');
  try {
    final response = await http
        .get(uri, headers: {'apikey': AppEnv.supabasePublishableKey})
        .timeout(const Duration(seconds: 10));
    return response.statusCode == 200
        ? BackendStatus.online
        : BackendStatus.offline;
  } on Exception {
    return BackendStatus.offline;
  }
});
