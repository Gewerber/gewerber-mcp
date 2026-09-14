import 'dart:async';

import 'package:dart_mcp/server.dart';

import '../config/config.dart';
import '../prompts/admin_prompts.dart';
import 'audit_tools.dart';
import 'businesses_tools.dart';
import 'guidance_tools.dart';
import 'invoices_tools.dart';
import 'stats_tools.dart';
import 'tool_context.dart';
import 'users_tools.dart';

/// Builds the full tool catalog for [ctx].
///
/// Exposed as a plain function so tests can inspect names/schemas without a
/// live MCP connection.
List<AdminTool> buildToolCatalog(ToolContext ctx) => [
  ...statsTools(ctx),
  ...usersTools(ctx),
  ...businessesTools(ctx),
  ...invoicesTools(ctx),
  ...auditTools(ctx),
  ...guidanceTools(ctx),
];

/// The Gewerber admin MCP server.
///
/// Connects to stdio and exposes read tools (moderator+) and guarded write
/// tools (admin+ with `confirm: true`) over the backend's admin endpoints,
/// plus playbook prompts for recurring admin routines.
final class GewerberMcpServer extends MCPServer
    with ToolsSupport, PromptsSupport {
  /// Creates the server on top of an already connected channel.
  GewerberMcpServer(super.channel, {required ToolContext ctx})
    : _ctx = ctx,
      super.fromStreamChannel(
        implementation: Implementation(
          name: ctx.config.serverName,
          version: gewerberMcpVersion,
        ),
        instructions:
            'Gewerber admin console. Read tools require the moderator role; '
            'destructive tools additionally pass confirm=true to the backend '
            'and require the admin role. All mutations are audited. The '
            '`admin_dashboard` and `investigate_user` prompts encode the '
            'recommended review/investigation playbooks.',
      );

  final ToolContext _ctx;

  /// The complete tool catalog (also visible before initialization).
  List<AdminTool> get tools => buildToolCatalog(_ctx);

  /// The prompt catalog offered to clients.
  List<Prompt> get prompts => AdminPrompts.all;

  @override
  FutureOr<InitializeResult> initialize(InitializeRequest request) {
    // Registering here follows the dart_mcp guidance: by the time the client
    // asks for `tools/list` or `prompts/list`, everything is registered.
    for (final tool in buildToolCatalog(_ctx)) {
      registerTool(tool.definition, tool.handler);
    }
    addPrompt(AdminPrompts.dashboard, AdminPrompts.renderDashboard);
    addPrompt(AdminPrompts.investigateUser, AdminPrompts.renderInvestigateUser);
    return super.initialize(request);
  }
}
