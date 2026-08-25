import 'package:dart_mcp/server.dart';

import '../errors/tool_errors.dart';

import 'tool_context.dart';

/// Platform-wide counters (moderator and up).
List<AdminTool> statsTools(ToolContext ctx) {
  final client = ctx.auth.client;
  return [
    AdminTool(
      Tool(
        name: 'stats_overview',
        description:
            'Platform-wide counters across all tenants: total users, users '
            'registered in the last 7/30 days, businesses, invoices per '
            'status and currently running timers. Requires moderator role or '
            'higher.',
        inputSchema: Schema.object(properties: {}),
      ),
      ctx.guarded('stats_overview', (_) async {
        final overview = await ctx.auth.run(client.adminStats.statsOverview);
        return jsonResult(overview.toJson());
      }),
    ),
  ];
}
