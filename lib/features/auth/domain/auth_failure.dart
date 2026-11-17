import 'package:supabase_flutter/supabase_flutter.dart';

/// Login problems the UI shows a friendly, translated message for.
enum AuthFailure {
  notRegistered,
  notActive,
  wrongCode,
  tooManyAttempts,
  network,
  unknown;

  static AuthFailure from(Object error) {
    if (error is AuthException) {
      final message = error.message.toLowerCase();
      if (message.contains('not registered') ||
          message.contains('only allowed with a registered')) {
        return AuthFailure.notRegistered;
      }
      if (message.contains('not active')) return AuthFailure.notActive;
      if (error.statusCode == '429' || message.contains('rate limit')) {
        return AuthFailure.tooManyAttempts;
      }
      if (message.contains('expired') ||
          message.contains('invalid') ||
          error.code == 'otp_expired' ||
          error.code == 'mfa_verification_failed') {
        return AuthFailure.wrongCode;
      }
      if (error is AuthRetryableFetchException) return AuthFailure.network;
      return AuthFailure.unknown;
    }
    final text = error.toString().toLowerCase();
    if (text.contains('socket') || text.contains('network')) {
      return AuthFailure.network;
    }
    return AuthFailure.unknown;
  }
}
