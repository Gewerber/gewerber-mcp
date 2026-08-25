import 'package:dart_mcp/server.dart';
import 'package:gewerber_backend_client/gewerber_backend_client.dart';
import 'package:gewerber_mcp/gewerber_mcp.dart';
import 'package:serverpod_auth_idp_client/serverpod_auth_idp_client.dart';
import 'package:test/test.dart';

const _userId = '550e8400-e29b-41d4-a716-446655440000';

AuthSuccess _success(String token, {String? refreshToken}) => AuthSuccess(
  authStrategy: 'jwt',
  token: token,
  refreshToken: refreshToken,
  authUserId: UuidValue.fromString(_userId),
  scopeNames: const <String>{},
);

/// A [BackendAuth] wired against an offline dummy client; all remote
/// behaviour comes from the stub hooks.
BackendAuth _auth({
  Future<AuthSuccess> Function(String email, String password)? signInStub,
  Future<AuthSuccess> Function(String refreshToken)? refreshStub,
}) => BackendAuth(
  Client('http://localhost:8080'),
  'admin@example.com',
  'secret',
  signInStub: signInStub,
  refreshStub: refreshStub,
);

void main() {
  group('BackendAuth.signIn reason mapping', () {
    test('invalidCredentials → actionable credentials message', () async {
      final auth = _auth(
        signInStub: (_, _) async => throw EmailAccountLoginException(
          reason: EmailAccountLoginExceptionReason.invalidCredentials,
        ),
      );
      await expectLater(
        auth.signIn(),
        throwsA(
          isA<BackendAuthException>()
              .having(
                (e) => e.message,
                'message',
                contains('invalid credentials'),
              )
              .having(
                (e) => e.message,
                'message',
                contains('GEWERBER_MCP_EMAIL'),
              ),
        ),
      );
      expect(auth.isSignedIn, isFalse);
    });

    test('tooManyAttempts → wait message', () async {
      final auth = _auth(
        signInStub: (_, _) async => throw EmailAccountLoginException(
          reason: EmailAccountLoginExceptionReason.tooManyAttempts,
        ),
      );
      await expectLater(
        auth.signIn(),
        throwsA(
          isA<BackendAuthException>().having(
            (e) => e.message,
            'message',
            contains('too many login attempts'),
          ),
        ),
      );
    });

    test('unknown → falls into generic backend-rejection message', () async {
      final auth = _auth(
        signInStub: (_, _) async => throw EmailAccountLoginException(
          reason: EmailAccountLoginExceptionReason.unknown,
        ),
      );
      await expectLater(
        auth.signIn(),
        throwsA(
          isA<BackendAuthException>().having(
            (e) => e.message,
            'message',
            allOf(contains('(unknown)'), contains('GEWERBER_MCP_PASSWORD')),
          ),
        ),
      );
    });

    test('blocked account → dedicated unban message', () async {
      final auth = _auth(
        signInStub: (_, _) async => throw AuthUserBlockedException(),
      );
      await expectLater(
        auth.signIn(),
        throwsA(
          isA<BackendAuthException>().having(
            (e) => e.message,
            'message',
            contains('blocked'),
          ),
        ),
      );
      expect(auth.isSignedIn, isFalse);
    });

    test('success stores the session', () async {
      final auth = _auth(signInStub: (_, _) async => _success('access-1'));
      await auth.signIn();
      expect(auth.isSignedIn, isTrue);
    });
  });

  group('BackendAuth.run recovery', () {
    test('401 → refresh ok → retry succeeds exactly once more', () async {
      var refreshes = 0;
      final auth = _auth(
        signInStub: (_, _) async =>
            _success('access-1', refreshToken: 'refresh-1'),
        refreshStub: (_) async {
          refreshes++;
          return _success('access-2', refreshToken: 'refresh-2');
        },
      );
      await auth.signIn();

      var calls = 0;
      final result = await auth.run(() async {
        calls++;
        if (calls == 1) throw ServerpodClientUnauthorized();
        return 'payload';
      });

      expect(result, 'payload');
      expect(calls, 2, reason: 'original call + single retry');
      expect(refreshes, 1, reason: 'no re-login needed after a good refresh');
      expect(auth.isSignedIn, isTrue);
    });

    test('refresh fails → re-login → retry succeeds', () async {
      var logins = 0;
      var refreshes = 0;
      final auth = _auth(
        signInStub: (_, _) async {
          logins++;
          return _success('access-$logins', refreshToken: 'refresh-$logins');
        },
        refreshStub: (_) async {
          refreshes++;
          throw RefreshTokenExpiredException();
        },
      );
      await auth.signIn(); // initial sign-in
      expect(logins, 1);

      var calls = 0;
      final result = await auth.run(() async {
        calls++;
        if (calls == 1) throw ServerpodClientUnauthorized();
        return 'recovered';
      });

      expect(result, 'recovered');
      expect(calls, 2);
      expect(refreshes, 1);
      expect(logins, 2, reason: 'full re-login after rejected refresh');
      expect(auth.isSignedIn, isTrue);
    });

    test(
      'both refresh and re-login fail → error escapes exactly once',
      () async {
        var logins = 0;
        var refreshes = 0;
        final auth = _auth(
          signInStub: (_, _) async {
            logins++;
            if (logins == 1) return _success('access-1', refreshToken: 'r1');
            // Account banned / password rotated mid-session.
            throw EmailAccountLoginException(
              reason: EmailAccountLoginExceptionReason.invalidCredentials,
            );
          },
          refreshStub: (_) async {
            refreshes++;
            throw RefreshTokenInvalidSecretException();
          },
        );
        await auth.signIn();

        var actionCalls = 0;
        Object? caught;
        try {
          await auth.run(() async {
            actionCalls++;
            throw ServerpodClientUnauthorized();
          });
        } catch (e) {
          caught = e;
        }

        expect(caught, isA<BackendAuthException>());
        expect(actionCalls, 1, reason: 'no retry when recovery failed');
        expect(refreshes, 1);
        expect(logins, 2);
      },
    );

    test(
      'session without refresh token skips refresh, re-logins directly',
      () async {
        var logins = 0;
        var refreshes = 0;
        final auth = _auth(
          signInStub: (_, _) async {
            logins++;
            // No refresh token issued (e.g. SAS-style session).
            return _success('access-$logins');
          },
          refreshStub: (_) async {
            refreshes++;
            return _success('unused');
          },
        );
        await auth.signIn();

        var calls = 0;
        final result = await auth.run(() async {
          calls++;
          if (calls == 1) throw ServerpodClientUnauthorized();
          return 'ok';
        });

        expect(result, 'ok');
        expect(refreshes, 0, reason: 'nothing to refresh without a token');
        expect(logins, 2);
        expect(calls, 2);
      },
    );

    test(
      'non-auth errors propagate untouched without recovery attempts',
      () async {
        var refreshes = 0;
        var logins = 0;
        final auth = _auth(
          signInStub: (_, _) async {
            logins++;
            return _success('access-1', refreshToken: 'refresh-1');
          },
          refreshStub: (_) async {
            refreshes++;
            return _success('unused');
          },
        );
        await auth.signIn();

        await expectLater(
          auth.run(() async => throw NotFoundException(entityType: 'AuthUser')),
          throwsA(isA<NotFoundException>()),
        );
        expect(refreshes, 0);
        expect(logins, 1, reason: 'no re-login for domain errors');
      },
    );
  });

  group('ToolContext.guarded', () {
    late ToolContext ctx;

    setUp(() {
      final config = McpConfig.fromEnvironment({
        'GEWERBER_MCP_EMAIL': 'admin@example.com',
        'GEWERBER_MCP_PASSWORD': 'secret',
      });
      ctx = ToolContext(config: config, auth: _auth());
    });

    CallToolRequest request([Map<String, Object?> args = const {}]) =>
        CallToolRequest(name: 'probe_tool', arguments: args);

    test('throwing handler becomes an isError result, not a crash', () async {
      final guarded = ctx.guarded(
        'boom_tool',
        (_) => throw NotFoundException(entityType: 'AuthUser', entityId: 'u1'),
      );
      final result = await guarded(request());

      expect(result.isError, isTrue);
      final text = (result.content.single as TextContent).text;
      expect(text, 'NotFound: AuthUser u1');
    });

    test('unexpected handler errors are opaque to the agent', () async {
      final guarded = ctx.guarded(
        'crashy_tool',
        (_) => throw StateError('boom'),
      );
      final result = await guarded(request());

      expect(result.isError, isTrue);
      final text = (result.content.single as TextContent).text;
      expect(text, startsWith('Unexpected MCP server error'));
      expect(text, isNot(contains('boom')));
    });

    test('successful handlers pass through unchanged', () async {
      final guarded = ctx.guarded('fine_tool', (_) => jsonResult({'ok': 1}));
      final result = await guarded(request());

      expect(result.isError ?? false, isFalse);
      expect((result.content.single as TextContent).text, contains('"ok": 1'));
    });
  });

  group('describeToolError(BackendAuthException)', () {
    test('passes the operator message through verbatim', () {
      const message =
          'The account admin@example.com is blocked on the '
          'backend. Unban it or use a different admin account.';
      expect(describeToolError(BackendAuthException(message)), message);
    });
  });
}
