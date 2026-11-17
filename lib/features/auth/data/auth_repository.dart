import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_bootstrap.dart';
import '../domain/auth_status.dart';
import '../domain/my_profile.dart';

/// Everything the app needs from Supabase Auth, in one place.
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  Stream<AuthState> get changes => _auth.onAuthStateChange;

  AuthStatus get status {
    if (_auth.currentSession == null) return AuthStatus.signedOut;
    final aal = _auth.mfa.getAuthenticatorAssuranceLevel();
    final needsAppCode =
        aal.nextLevel == AuthenticatorAssuranceLevels.aal2 &&
        aal.currentLevel != AuthenticatorAssuranceLevels.aal2;
    return needsAppCode ? AuthStatus.needsSecondFactor : AuthStatus.signedIn;
  }

  /// Step 1: ask Supabase to send a login code to [phoneE164].
  /// Unregistered numbers are rejected by the database hook.
  Future<void> sendCode(String phoneE164) =>
      _auth.signInWithOtp(phone: phoneE164, shouldCreateUser: true);

  /// Step 2: check the code the employee typed.
  Future<void> verifyCode(String phoneE164, String code) async {
    await _auth.verifyOTP(phone: phoneE164, token: code, type: OtpType.sms);
  }

  Future<void> signOut() => _auth.signOut();

  /// The employee's own profile, or `null` if they are not an active,
  /// registered employee (e.g. they were just deactivated).
  Future<MyProfile?> fetchMyProfile() async {
    final rows = await _client.rpc<List<dynamic>>('get_my_profile');
    if (rows.isEmpty) return null;
    return MyProfile.fromJson(Map<String, dynamic>.from(rows.first as Map));
  }

  // ---------------------------------------------------------------------------
  // Authenticator app (TOTP)
  // ---------------------------------------------------------------------------

  /// The verified authenticator app, if the user has turned one on.
  Future<Factor?> verifiedAuthenticator() async {
    final factors = await _auth.mfa.listFactors();
    for (final factor in factors.totp) {
      if (factor.status == FactorStatus.verified) return factor;
    }
    return null;
  }

  /// Starts adding an authenticator app. Returns the QR code link and the
  /// secret the user can type manually.
  Future<AuthMFAEnrollResponse> startAuthenticatorSetup() async {
    // Remove unfinished earlier attempts so names don't clash.
    final factors = await _auth.mfa.listFactors();
    for (final factor in factors.all) {
      if (factor.factorType == FactorType.totp &&
          factor.status != FactorStatus.verified) {
        await _auth.mfa.unenroll(factor.id);
      }
    }
    return _auth.mfa.enroll(
      factorType: FactorType.totp,
      issuer: 'Workplace',
      friendlyName: 'Authenticator ${DateTime.now().millisecondsSinceEpoch}',
    );
  }

  /// Checks a 6-digit code from the authenticator app. Used both to finish
  /// setup and to sign in.
  Future<void> verifyAuthenticatorCode(String factorId, String code) async {
    await _auth.mfa.challengeAndVerify(factorId: factorId, code: code);
  }

  Future<void> removeAuthenticator(String factorId) async {
    await _auth.mfa.unenroll(factorId);
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseClientProvider)),
);
