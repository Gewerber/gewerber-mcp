import 'dart:io';

import 'package:dart_mcp/stdio.dart';
import 'package:gewerber_backend_client/gewerber_backend_client.dart';
import 'package:gewerber_mcp/src/auth/backend_auth.dart';
import 'package:gewerber_mcp/src/config/config.dart';
import 'package:gewerber_mcp/src/tools/gewerber_mcp_server.dart';
import 'package:gewerber_mcp/src/tools/tool_context.dart';

/// Entry point of the Gewerber admin MCP server.
///
/// Reads configuration from `GEWERBER_MCP_*` environment variables, signs in
/// against the backend and then serves MCP over stdio until the client
/// disconnects.
Future<void> main() async {
  final McpConfig config;
  try {
    config = McpConfig.fromEnvironment();
  } on ConfigurationException catch (e) {
    stderr.writeln('gewerber-mcp: ${e.message}');
    exitCode = 64; // EX_USAGE
    return;
  }

  final client = Client(config.apiUrl.toString());
  final auth = BackendAuth(client, config.email, config.password);

  try {
    await auth.signIn();
    stderr.writeln(
      '[gewerber-mcp] signed in as ${config.email} '
      '(backend ${config.apiUrl}, role enforced server-side)',
    );
  } on BackendAuthException catch (e) {
    stderr.writeln('gewerber-mcp: $e');
    exitCode = 65; // EX_DATAERR
    await _disposeQuietly(client);
    return;
  } catch (e) {
    stderr.writeln(
      'gewerber-mcp: cannot reach the backend at ${config.apiUrl}: $e',
    );
    exitCode = 69; // EX_UNAVAILABLE
    await _disposeQuietly(client);
    return;
  }

  final server = GewerberMcpServer(
    stdioChannel(input: stdin, output: stdout),
    ctx: ToolContext(config: config, auth: auth),
  );

  // Keep serving tool calls until the MCP client disconnects.
  await server.done;
  await _disposeQuietly(client);
}

Future<void> _disposeQuietly(Client client) async {
  try {
    client.close();
  } catch (_) {
    // Best effort during startup/shutdown failures.
  }
}
