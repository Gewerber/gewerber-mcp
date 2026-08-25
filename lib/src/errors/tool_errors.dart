import 'dart:convert';

import 'package:dart_mcp/server.dart';
import 'package:gewerber_backend_client/gewerber_backend_client.dart';
import 'package:serverpod_auth_idp_client/serverpod_auth_idp_client.dart';

/// Invalid tool input supplied by the agent (bad UUID, unknown enum value,
/// non-ISO date, missing `confirm`, …).
final class ToolInputError implements Exception {
  ToolInputError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Encodes [payload] as pretty-printed JSON for a tool result.
String prettyJson(Object? payload) =>
    const JsonEncoder.withIndent('  ').convert(payload);

/// Successful tool result carrying [payload] as pretty JSON text.
CallToolResult jsonResult(Object? payload) =>
    CallToolResult(content: [TextContent(text: prettyJson(payload))]);

/// Failed tool result with a human/agent readable [message].
CallToolResult errorResult(String message) =>
    CallToolResult(content: [TextContent(text: message)], isError: true);

/// Maps any error thrown inside a tool handler into an agent-readable text.
///
/// Generated backend exceptions are rendered with their actual fields
/// (e.g. `NotFound: AuthUser <id>`); anything unexpected gets a generic
/// message plus a hint to check the server logs. This function never throws.
String describeToolError(Object error) {
  switch (error) {
    case final ToolInputError e:
      return 'Invalid arguments: ${e.message}';
    case ValidationException(:final field, :final message):
      return 'Validation failed'
          '${field == null ? '' : ' on `$field`'}: $message '
          '(the backend refused the request; nothing was changed).';
    case NotFoundException(:final entityType, :final entityId):
      return ['NotFound:', entityType, ?entityId].join(' ');
    case ConflictException(:final message):
      return 'Conflict: $message';
    case ForbiddenException(:final message):
      return 'Forbidden: ${message ?? 'the signed-in account has no global '
              'admin/moderator role for this operation. Grant the role out of band '
              '(admin_user allowlist / grant_admin.sql).'}';
    case EmailAccountLoginException():
      return 'Backend rejected the credentials (${error.reason.name}). Check '
          'GEWERBER_MCP_EMAIL / GEWERBER_MCP_PASSWORD.';
    case AuthUserBlockedException():
      return 'The configured admin account is blocked on the backend. '
          'Unban it or configure a different GEWERBER_MCP_EMAIL.';
    case ServerpodClientUnauthorized():
      return 'Not authenticated (HTTP 401): token refresh and re-login both '
          'failed. Check GEWERBER_MCP_EMAIL / GEWERBER_MCP_PASSWORD and that '
          'the account is not blocked.';
    case ServerpodClientForbidden():
      return 'Forbidden (HTTP 403): the account is signed in but lacks the '
          'global role required for this operation (moderator = read, admin = '
          'write). Grant it via the admin_user allowlist (grant_admin.sql).';
    case ServerpodClientBadRequest():
      return 'Bad request (HTTP 400): ${error.message}';
    case ServerpodClientNotFound():
      return 'Endpoint not found (HTTP 404): is the backend running the '
          'admin API? URL/config mismatch?';
    case ServerpodClientInternalServerError():
      return 'Backend internal error (HTTP 500). Check the backend logs.';
    case ServerpodClientException(:final statusCode, :final message):
      return 'Backend request failed (HTTP $statusCode): $message';
    default:
      return 'Unexpected MCP server error: $error — check the gewerber-mcp '
          'logs (stderr) and the backend logs.';
  }
}
