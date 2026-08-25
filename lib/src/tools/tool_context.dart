import 'dart:async';
import 'dart:io';

import 'package:dart_mcp/server.dart';

import '../auth/backend_auth.dart';
import '../config/config.dart';
import '../errors/tool_errors.dart';

/// Signature of a raw tool handler.
typedef AdminToolHandler =
    FutureOr<CallToolResult> Function(CallToolRequest request);

/// A tool definition plus its raw handler, before logging/error guarding.
final class AdminTool {
  const AdminTool(this.definition, this.handler);

  /// The MCP tool definition exposed to clients.
  final Tool definition;

  /// The unguarded implementation; use [ToolContext.guarded] when wiring.
  final FutureOr<CallToolResult> Function(CallToolRequest request) handler;

  /// Tool name shortcut.
  String get name => definition.name;
}

/// Shared dependencies and helpers for all tool handlers.
final class ToolContext {
  const ToolContext({required this.config, required this.auth});

  final McpConfig config;
  final BackendAuth auth;

  /// Wraps [handler] so every invocation is logged (optional, stderr) and
  /// any thrown error becomes an `isError` tool result instead of crashing
  /// the MCP session. Protocol-level [RpcException]s are rethrown untouched.
  AdminToolHandler guarded(String toolName, AdminToolHandler handler) =>
      (CallToolRequest request) async {
        final stopwatch = Stopwatch()..start();
        log('$toolName args=${prettyJson(request.arguments ?? const {})}');
        try {
          final result = await handler(request);
          log('$toolName ok in ${stopwatch.elapsedMilliseconds}ms');
          return result;
        } catch (error, stackTrace) {
          log(
            '$toolName FAILED after ${stopwatch.elapsedMilliseconds}ms: '
            '$error\n$stackTrace',
          );
          return errorResult(describeToolError(error));
        }
      };

  /// Logs to stderr only when `GEWERBER_MCP_LOG_TOOLS=true`.
  ///
  /// stdout carries the MCP protocol and must never receive log output.
  void log(String message) {
    if (config.logTools) stderr.writeln('[gewerber-mcp] $message');
  }
}
