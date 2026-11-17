/// Where the user is in the login flow. The router sends them to the
/// matching screen.
enum AuthStatus {
  /// No session: show the phone number screen.
  signedOut,

  /// SMS code accepted, but the user has an authenticator app turned on and
  /// must also enter its 6-digit code.
  needsSecondFactor,

  /// Fully signed in.
  signedIn,
}
