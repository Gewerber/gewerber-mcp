import 'package:dart_mcp/server.dart';

import '../errors/tool_errors.dart';

import '../util/parsing.dart';
import 'tool_context.dart';

/// Administration of guidance content shown to end users.
List<AdminTool> guidanceTools(ToolContext ctx) {
  final client = ctx.auth.client;
  return [
    AdminTool(
      Tool(
        name: 'guidance_tips_list',
        description:
            'The effective guidance tips as users see them (curated in-code '
            'content merged with admin overrides). Requires moderator role or '
            'higher.',
        inputSchema: Schema.object(properties: {}),
      ),
      ctx.guarded('guidance_tips_list', (_) async {
        final tips = await ctx.auth.run(client.adminGuidance.guidanceTipsList);
        return jsonResult([for (final tip in tips) tip.toJson()]);
      }),
    ),
    AdminTool(
      Tool(
        name: 'guidance_tip_upsert',
        description:
            'DESTRUCTIVE (overwrites content). Creates or replaces an '
            'admin-managed guidance tip by its unique topic. A topic matching '
            'a curated tip overrides it; other topics are appended as new '
            'tips. Requires admin role and confirm=true.',
        inputSchema: Schema.object(
          properties: {
            'topic': Schema.string(
              description:
                  'Unique topic key. Re-using an existing topic replaces that '
                  'tip entirely.',
            ),
            'title': Schema.string(description: 'Short title of the tip.'),
            'body': Schema.string(description: 'Body text of the tip.'),
            'confirm': Schema.bool(
              description:
                  'Must be true — upserting silently replaces existing '
                  'content for the topic.',
            ),
          },
          required: ['topic', 'title', 'body', 'confirm'],
        ),
      ),
      ctx.guarded('guidance_tip_upsert', (request) async {
        final args = request.arguments ?? const <String, Object?>{};
        requireConfirm(args);
        final tip = await ctx.auth.run(
          () => client.adminGuidance.guidanceTipUpsert(
            topic: requireString(args, 'topic'),
            title: requireString(args, 'title'),
            body: requireString(args, 'body'),
            confirm: true,
          ),
        );
        return jsonResult(tip.toJson());
      }),
    ),
  ];
}
