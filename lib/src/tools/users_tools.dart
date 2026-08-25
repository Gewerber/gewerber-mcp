import 'package:dart_mcp/server.dart';

import '../errors/tool_errors.dart';

import '../util/parsing.dart';
import 'tool_context.dart';

/// User directory reads plus auth-level mutations (ban/unban) and the
/// read-only email-verification compliance check.
List<AdminTool> usersTools(ToolContext ctx) {
  final client = ctx.auth.client;
  return [
    AdminTool(
      Tool(
        name: 'users_search',
        description:
            'Keyset-paginated search over all users by email substring. '
            'Returns AdminUserSummary items and `nextCursor` for paging. '
            'Requires moderator role or higher.',
        inputSchema: Schema.object(
          properties: {
            'query': Schema.string(
              description: 'Email substring to search for; omit to list all.',
            ),
            'limit': Schema.int(
              description:
                  'Page size (default $defaultPageLimit, max $maxPageLimit).',
            ),
            'cursor': Schema.string(
              description: '`nextCursor` from the previous page.',
            ),
          },
        ),
      ),
      ctx.guarded('users_search', (request) async {
        final args = request.arguments ?? const <String, Object?>{};
        final page = await ctx.auth.run(
          () => client.adminUsers.usersSearch(
            query: optionalString(args, 'query'),
            limit: optionalInt(args, 'limit', max: maxPageLimit),
            cursor: optionalString(args, 'cursor'),
          ),
        );
        return jsonResult(page.toJson());
      }),
    ),
    AdminTool(
      Tool(
        name: 'users_get',
        description:
            'Full dossier of one user: profile, email, auth status (blocked / '
            'email confirmed), memberships with business names and the global '
            'admin role. Requires moderator role or higher.',
        inputSchema: Schema.object(
          properties: {'userId': Schema.string(description: 'AuthUser UUID.')},
          required: ['userId'],
        ),
      ),
      ctx.guarded('users_get', (request) async {
        final args = request.arguments ?? const <String, Object?>{};
        final dossier = await ctx.auth.run(
          () => client.adminUsers.usersGet(requireUuid(args, 'userId')),
        );
        return jsonResult(dossier.toJson());
      }),
    ),
    AdminTool(
      Tool(
        name: 'users_ban',
        description:
            'DESTRUCTIVE. Blocks a user on the authentication level: refresh '
            'tokens are invalidated immediately, sign-in is refused. No data '
            'is deleted. The reason is stored in the audit trail. Requires '
            'admin role and confirm=true.',
        inputSchema: Schema.object(
          properties: {
            'userId': Schema.string(description: 'AuthUser UUID to ban.'),
            'reason': Schema.string(
              description:
                  'Why this user is banned (mandatory, goes into the audit '
                  'trail).',
            ),
            'confirm': Schema.bool(
              description:
                  'Must be true. Only confirm after verifying userId and '
                  'stating the consequence.',
            ),
          },
          required: ['userId', 'reason', 'confirm'],
        ),
      ),
      ctx.guarded('users_ban', (request) async {
        final args = request.arguments ?? const <String, Object?>{};
        requireConfirm(args);
        final dossier = await ctx.auth.run(
          () => client.adminUsers.usersBan(
            userId: requireUuid(args, 'userId'),
            reason: requireString(args, 'reason'),
            confirm: true,
          ),
        );
        return jsonResult(dossier.toJson());
      }),
    ),
    AdminTool(
      Tool(
        name: 'users_unban',
        description:
            'DESTRUCTIVE. Lifts a ban: the user can sign in again (previously '
            'purged refresh tokens are not restored). Requires admin role and '
            'confirm=true.',
        inputSchema: Schema.object(
          properties: {
            'userId': Schema.string(description: 'AuthUser UUID to unban.'),
            'confirm': Schema.bool(
              description: 'Must be true after verifying userId.',
            ),
          },
          required: ['userId', 'confirm'],
        ),
      ),
      ctx.guarded('users_unban', (request) async {
        final args = request.arguments ?? const <String, Object?>{};
        requireConfirm(args);
        final dossier = await ctx.auth.run(
          () => client.adminUsers.usersUnban(
            userId: requireUuid(args, 'userId'),
            confirm: true,
          ),
        );
        return jsonResult(dossier.toJson());
      }),
    ),
    AdminTool(
      Tool(
        name: 'users_verify_email_check',
        description:
            'READ-ONLY compliance check of a user\'s email verification state '
            '(audited as admin.verifyEmailCheck). Throws NotFound if the user '
            'has no email account. Requires admin role.',
        inputSchema: Schema.object(
          properties: {'userId': Schema.string(description: 'AuthUser UUID.')},
          required: ['userId'],
        ),
      ),
      ctx.guarded('users_verify_email_check', (request) async {
        final args = request.arguments ?? const <String, Object?>{};
        final status = await ctx.auth.run(
          () => client.adminUsers.usersVerifyEmail(
            userId: requireUuid(args, 'userId'),
          ),
        );
        return jsonResult(status.toJson());
      }),
    ),
  ];
}
