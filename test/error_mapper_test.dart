import 'package:dart_mcp/server.dart';
import 'package:gewerber_backend_client/gewerber_backend_client.dart';
import 'package:gewerber_backend_commercial_client/gewerber_backend_commercial_client.dart'
    show PromoException, SubscriptionAdminException;
import 'package:gewerber_mcp/gewerber_mcp.dart';
import 'package:serverpod_auth_idp_client/serverpod_auth_idp_client.dart';
import 'package:test/test.dart';

void main() {
  group('describeToolError', () {
    test('ToolInputError → Invalid arguments prefix', () {
      final text = describeToolError(ToolInputError('`userId` must be a UUID'));
      expect(text, startsWith('Invalid arguments:'));
      expect(text, contains('userId'));
    });

    test('ValidationException renders message and field', () {
      final text = describeToolError(
        ValidationException(message: 'confirm must be true', field: 'confirm'),
      );
      expect(text, contains('Validation failed on `confirm`'));
      expect(text, contains('confirm must be true'));
    });

    test('NotFoundException renders "NotFound: <entityType> <entityId>"', () {
      final text = describeToolError(
        NotFoundException(entityType: 'AuthUser', entityId: 'abc-123'),
      );
      expect(text, 'NotFound: AuthUser abc-123');
    });

    test('NotFoundException without id omits the id part', () {
      final text = describeToolError(NotFoundException(entityType: 'Business'));
      expect(text, 'NotFound: Business');
    });

    test('ConflictException renders the backend message', () {
      final text = describeToolError(
        ConflictException(
          message: 'Cannot demote the last owner of this business',
        ),
      );
      expect(text, 'Conflict: Cannot demote the last owner of this business');
    });

    test('ForbiddenException hints at missing global role', () {
      final text = describeToolError(ForbiddenException());
      expect(text, startsWith('Forbidden:'));
      expect(text, contains('admin_user'));
    });

    test('SubscriptionAdminException renders message, field and reason', () {
      final text = describeToolError(
        SubscriptionAdminException(
          message: 'Unknown promo code id 4711',
          field: 'promoCodeId',
          reason: 'notFound',
        ),
      );
      expect(text, contains('Unknown promo code id 4711'));
      expect(text, contains('(field `promoCodeId`)'));
      expect(text, contains('(reason: notFound)'));
      // notFound is an input problem, not a role problem: no allowlist hint.
      expect(text, isNot(contains('grant_admin.sql')));
    });

    test('SubscriptionAdminException role reasons add the allowlist hint', () {
      for (final reason in ['noRole', 'insufficientRole', 'notAuthenticated']) {
        final text = describeToolError(
          SubscriptionAdminException(
            message: 'Missing admin role',
            field: 'role',
            reason: reason,
          ),
        );
        expect(text, contains('(reason: $reason)'));
        expect(text, contains('admin_user'), reason: reason);
        expect(text, contains('grant_admin.sql'), reason: reason);
      }
    });

    test(
      'SubscriptionAdminException without optional fields still renders',
      () {
        final text = describeToolError(
          SubscriptionAdminException(message: 'Endpoint unavailable'),
        );
        expect(text, contains('Subscription admin refused the request'));
        expect(text, contains('Endpoint unavailable'));
        expect(text, isNot(contains('field')));
        expect(text, isNot(contains('reason')));
      },
    );

    test('PromoException renders message, field and reason', () {
      final text = describeToolError(
        PromoException(
          message: 'Code contains illegal characters',
          field: 'code',
          reason: 'badFormat',
        ),
      );
      expect(text, startsWith('Promo code error:'));
      expect(text, contains('Code contains illegal characters'));
      expect(text, contains('(field `code`)'));
      expect(text, contains('(reason: badFormat)'));
    });

    test('ServerpodClientHttpException reports the status code', () {
      final text = describeToolError(
        ServerpodClientUnknownHttpException('teapot', 418),
      );
      expect(text, contains('418'));
    });

    test('EmailAccountLoginException points at env credentials', () {
      final text = describeToolError(
        EmailAccountLoginException(
          reason: EmailAccountLoginExceptionReason.invalidCredentials,
        ),
      );
      expect(text, contains('GEWERBER_MCP_EMAIL'));
      expect(text, contains('invalidCredentials'));
    });

    test('ServerpodClientUnauthorized mentions refresh/re-login failure', () {
      final text = describeToolError(ServerpodClientUnauthorized());
      expect(text, contains('401'));
      expect(text, contains('GEWERBER_MCP_EMAIL'));
    });

    test('ServerpodClientForbidden explains role requirements', () {
      final text = describeToolError(ServerpodClientForbidden());
      expect(text, contains('403'));
      expect(text, contains('moderator'));
    });

    test('BackendAuthException passes the operator message through', () {
      final text = describeToolError(
        BackendAuthException(
          'Backend sign-in failed: invalid credentials. '
          'Check GEWERBER_MCP_EMAIL / GEWERBER_MCP_PASSWORD.',
        ),
      );
      expect(text, contains('GEWERBER_MCP_EMAIL'));
      // No generic prefix: session-level auth failures are actionable.
      expect(text, isNot(startsWith('Unexpected')));
    });

    test('unexpected errors stay opaque; details live on stderr only', () {
      final text = describeToolError(StateError('boom'));
      expect(text, startsWith('Unexpected MCP server error'));
      // Internal error details must never leak into the conversation; the
      // full error + stack trace are logged to stderr by ToolContext.guarded.
      expect(text, isNot(contains('boom')));
      expect(text, contains('logs'));
    });
  });

  group('errorResult / jsonResult / prettyJson', () {
    test('errorResult is flagged as an error', () {
      final result = errorResult('nope');
      expect(result.isError, isTrue);
      expect((result.content.single as TextContent).text, 'nope');
    });

    test('jsonResult pretty-prints its payload', () {
      final result = jsonResult({
        'a': 1,
        'nested': {
          'b': [2, 3],
        },
      });
      expect(result.isError ?? false, isFalse);
      final text = (result.content.single as TextContent).text;
      expect(text, contains('\n')); // multi-line = indented
      expect(text, contains('"a": 1'));
    });
  });
}
