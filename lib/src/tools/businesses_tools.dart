import 'package:dart_mcp/server.dart';

import '../errors/tool_errors.dart';

import '../util/parsing.dart';
import 'tool_context.dart';

/// Cross-tenant business and membership administration.
List<AdminTool> businessesTools(ToolContext ctx) {
  final client = ctx.auth.client;
  return [
    AdminTool(
      Tool(
        name: 'businesses_search',
        description:
            'Keyset-paginated business search by name substring. Returns '
            'Business items and `nextCursor` for paging. Requires moderator '
            'role or higher.',
        inputSchema: Schema.object(
          properties: {
            'query': Schema.string(
              description: 'Name substring to search for; omit to list all.',
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
      ctx.guarded('businesses_search', (request) async {
        final args = request.arguments ?? const <String, Object?>{};
        final page = await ctx.auth.run(
          () => client.adminBusinesses.businessesSearch(
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
        name: 'businesses_get',
        description:
            'One business with all of its memberships. Requires moderator '
            'role or higher.',
        inputSchema: Schema.object(
          properties: {
            'businessId': Schema.int(description: 'Numeric business id.'),
          },
          required: ['businessId'],
        ),
      ),
      ctx.guarded('businesses_get', (request) async {
        final args = request.arguments ?? const <String, Object?>{};
        final businessId = optionalInt(args, 'businessId', max: 1 << 62);
        if (businessId == null) {
          throw ToolInputError('`businessId` must be a positive integer.');
        }
        final detail = await ctx.auth.run(
          () => client.adminBusinesses.businessesGet(businessId),
        );
        return jsonResult(detail.toJson());
      }),
    ),
    AdminTool(
      Tool(
        name: 'membership_set_role',
        description:
            'DESTRUCTIVE. Changes the tenant role of one membership. Allowed '
            'roles: owner, admin, member. The backend refuses to demote the '
            'last owner of a business (Conflict). Requires admin role and '
            'confirm=true.',
        inputSchema: Schema.object(
          properties: {
            'membershipId': Schema.int(description: 'Numeric membership id.'),
            'role': UntitledSingleSelectEnumSchema(
              values: membershipRoleValues.keys,
              description: 'New tenant role for the membership.',
            ),
            'confirm': Schema.bool(
              description:
                  'Must be true. Only confirm after verifying membershipId '
                  'and role.',
            ),
          },
          required: ['membershipId', 'role', 'confirm'],
        ),
      ),
      ctx.guarded('membership_set_role', (request) async {
        final args = request.arguments ?? const <String, Object?>{};
        requireConfirm(args);
        final membershipId = optionalInt(args, 'membershipId', max: 1 << 62);
        if (membershipId == null) {
          throw ToolInputError('`membershipId` must be a positive integer.');
        }
        final membership = await ctx.auth.run(
          () => client.adminBusinesses.membershipsSetRole(
            membershipId: membershipId,
            role: requireMembershipRole(args, 'role'),
            confirm: true,
          ),
        );
        return jsonResult(membership.toJson());
      }),
    ),
  ];
}
