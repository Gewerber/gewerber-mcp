import 'package:gewerber_backend_client/gewerber_backend_client.dart';
import 'package:serverpod_auth_idp_client/serverpod_auth_idp_client.dart';

/// Thrown when the configured credentials cannot be used to sign in at all.
final class BackendAuthException implements Exception {
  BackendAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Owns the admin session against the Gewerber backend.
///
/// - [BackendAuth.signIn] performs the initial email+password login and
///   stores the resulting `access`/`refresh` tokens ([AuthSuccess]).
/// - A [JwtAuthKeyProvider] is attached to the client so every request carries
///   `Authorization: Bearer <jwt>` and access tokens are refreshed
///   proactively before they expire.
/// - [run] wraps endpoint calls: if a call fails with an authentication error,
///   it tries an explicit token refresh first, then a full re-login, and
///   retries the call **once**. If that still fails the original error is
///   rethrown for the caller to map into a tool result.
final class BackendAuth {
  /// Creates the auth layer and wires the JWT provider into [client].
  ///
  /// The [signInStub]/[refreshStub] hooks replace the real endpoint calls;
  /// they exist for unit tests so the recovery logic can be exercised without
  /// a live backend. Production code never passes them.
  BackendAuth(
    this._client,
    this._email,
    this._password, {
    Future<AuthSuccess> Function(String email, String password)? signInStub,
    Future<AuthSuccess> Function(String refreshToken)? refreshStub,
  }) : _doSignIn =
           signInStub ??
           ((String email, String password) =>
               _client.emailIdp.login(email: email, password: password)),
       _doRefresh =
           refreshStub ??
           ((String token) =>
               _client.jwtRefresh.refreshAccessToken(refreshToken: token)) {
    _client.authKeyProvider = JwtAuthKeyProvider(
      getAuthInfo: () async => _auth,
      onRefreshAuthInfo: (success) async => _auth = success,
      refreshEndpoint: _client.jwtRefresh,
    );
  }

  final Client _client;
  final String _email;
  final String _password;

  final Future<AuthSuccess> Function(String email, String password) _doSignIn;
  final Future<AuthSuccess> Function(String refreshToken) _doRefresh;

  AuthSuccess? _auth;
  bool _signedIn = false;

  /// The authenticated Serverpod client used by all tools.
  Client get client => _client;

  /// Whether we currently believe we hold a valid session.
  bool get isSignedIn => _signedIn;

  /// Signs in with the configured credentials.
  ///
  /// Throws [BackendAuthException] with an operator-friendly message when the
  /// credentials are rejected (wrong password, unknown account, blocked user).
  Future<void> signIn() async {
    try {
      _auth = await _doSignIn(_email, _password);
      _signedIn = true;
    } on EmailAccountLoginException catch (e) {
      _signedIn = false;
      throw BackendAuthException(switch (e.reason) {
        EmailAccountLoginExceptionReason.tooManyAttempts =>
          'Backend sign-in failed: too many login attempts for $_email. '
              'Wait and try again.',
        EmailAccountLoginExceptionReason.invalidCredentials =>
          'Backend sign-in failed: invalid credentials. '
              'Check GEWERBER_MCP_EMAIL / GEWERBER_MCP_PASSWORD.',
        _ =>
          'Backend sign-in failed (${e.reason.name}). '
              'Check GEWERBER_MCP_EMAIL / GEWERBER_MCP_PASSWORD.',
      });
    } on AuthUserBlockedException {
      _signedIn = false;
      throw BackendAuthException(
        'The account $_email is blocked on the backend. '
        'Unban it or use a different admin account.',
      );
    }
  }

  /// Runs [action], recovering once from expired/invalid tokens:
  /// refresh → re-login → retry. All other errors propagate unchanged.
  Future<T> run<T>(Future<T> Function() action) async {
    // Lazy (re-)sign-in, e.g. when the backend restarted between calls.
    if (!_signedIn) await signIn();
    try {
      return await action();
    } on ServerpodClientUnauthorized {
      await reauthenticate();
      return await action();
    }
  }

  /// Refreshes the token pair; falls back to a full re-login when no refresh
  /// token is available or the refresh is rejected.
  Future<void> reauthenticate() async {
    final refreshToken = _auth?.refreshToken;
    if (refreshToken != null) {
      try {
        _auth = await _doRefresh(refreshToken);
        _signedIn = true;
        return;
      } on RefreshTokenMalformedException {
        // fall through to re-login
      } on RefreshTokenNotFoundException {
        // fall through to re-login
      } on RefreshTokenExpiredException {
        // fall through to re-login
      } on RefreshTokenInvalidSecretException {
        // fall through to re-login
      }
    }
    await signIn();
  }
}
