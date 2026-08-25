import 'package:dart_mcp/server.dart';

import '../errors/tool_errors.dart';

import '../util/parsing.dart';
import 'tool_context.dart';

/// Read access to the audit trail (moderator and up).
List<AdminTool> auditTools(ToolContext ctx) {
  final client = ctx.auth.client;
  return [
    AdminTool(
      Tool(
        name: 'audit_query',
        description:
            'Newest-first audit entries, optionally filtered by acting user '
            '(UUID), exact action name (e.g. admin.usersBan) and a lower time '
            'bound (ISO-8601). No cursor: to page further, pass `since` set to '
            'the createdAt of the oldest returned entry. Requires moderator '
            'role or higher.',
        inputSchema: Schema.object(
          properties: {
            'actorUserId': Schema.string(
              description: 'Only entries acted by this AuthUser UUID.',
            ),
            'action': Schema.string(
              description: 'Exact action name filter (e.g. admin.usersBan).',
            ),
            'since': Schema.string(
              description:
                  'Only entries at or after this ISO-8601 instant; reuse the '
                  'oldest entry\'s createdAt for paging.',
            ),
            'limit': Schema.int(
              description:
                  'Page size (default $defaultPageLimit, max $maxPageLimit).',
            ),
          },
        ),
      ),
      ctx.guarded('audit_query', (request) async {
        final args = request.arguments ?? const <String, Object?>{};
        final page = await ctx.auth.run(
          () => client.adminAudit.auditQuery(
            actorUserId:
                args.containsKey('actorUserId') && args['actorUserId'] != null
                ? requireUuid(args, 'actorUserId')
                : null,
            action: optionalString(args, 'action'),
            since: optionalIsoDate(args, 'since'),
            limit: optionalInt(args, 'limit', max: maxPageLimit),
          ),
        );
        return jsonResult(page.toJson());
      }),
    ),
  ];
}
