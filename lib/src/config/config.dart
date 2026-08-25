import 'dart:io';

/// Package version reported to MCP clients during initialization.
///
/// Keep in sync with `version:` in pubspec.yaml.
const String gewerberMcpVersion = '0.1.0';

/// Thrown when the environment does not contain a usable configuration.
final class ConfigurationException implements Exception {
  ConfigurationException(this.problems)
    : message =
          'Invalid GEWERBER_MCP_* configuration:\n'
          '${problems.map((p) => ' - $p').join('\n')}';

  /// Human readable list of all detected problems.
  final List<String> problems;

  /// Ready-to-print error message for the operator.
  final String message;

  @override
  String toString() => message;
}

/// Immutable runtime configuration, loaded from `GEWERBER_MCP_*` env vars.
///
/// Required:
/// - `GEWERBER_MCP_EMAIL` — admin/moderator account email.
/// - `GEWERBER_MCP_PASSWORD` — its password.
///
/// Optional:
/// - `GEWERBER_MCP_API_URL` (default `http://localhost:8080`).
/// - `GEWERBER_MCP_SERVER_NAME` (default `gewerber-admin`).
/// - `GEWERBER_MCP_LOG_TOOLS` (default off) — log tool calls to stderr.
final class McpConfig {
  const McpConfig({
    required this.apiUrl,
    required this.email,
    required this.password,
    this.serverName = defaultServerName,
    this.logTools = false,
  });

  static const defaultApiUrl = 'http://localhost:8080';
  static const defaultServerName = 'gewerber-admin';

  /// Base URL of the Serverpod backend API.
  final Uri apiUrl;

  /// Admin/moderator account email.
  final String email;

  /// Admin/moderator account password.
  final String password;

  /// Name reported to the MCP client.
  final String serverName;

  /// Whether to log every tool invocation to stderr.
  final bool logTools;

  /// Parses [env] (`Platform.environment` by default).
  ///
  /// Collects *all* problems before throwing a single
  /// [ConfigurationException] so operators can fix everything at once.
  factory McpConfig.fromEnvironment([Map<String, String>? env]) {
    final environment = env ?? Platform.environment;
    final problems = <String>[];

    String? required(String key) {
      final value = environment[key]?.trim();
      if (value == null || value.isEmpty) {
        problems.add('$key is required but missing or empty');
        return null;
      }
      return value;
    }

    Uri? parseUrl(String key, String? raw, {required Uri fallback}) {
      if (raw == null || raw.isEmpty) return fallback;
      final uri = Uri.tryParse(raw);
      if (uri == null ||
          !uri.hasScheme ||
          (uri.scheme != 'http' && uri.scheme != 'https')) {
        problems.add(
          '$key="$raw" is not a valid http(s) URL '
          '(example: $defaultApiUrl)',
        );
        return null;
      }
      return uri;
    }

    final email = required('GEWERBER_MCP_EMAIL');
    final password = required('GEWERBER_MCP_PASSWORD');
    final apiUrl = parseUrl(
      'GEWERBER_MCP_API_URL',
      environment['GEWERBER_MCP_API_URL']?.trim(),
      fallback: Uri.parse(defaultApiUrl),
    );
    final serverName =
        environment['GEWERBER_MCP_SERVER_NAME']?.trim().isNotEmpty ?? false
        ? environment['GEWERBER_MCP_SERVER_NAME']!.trim()
        : defaultServerName;
    final logTools = parseBool('GEWERBER_MCP_LOG_TOOLS', environment, problems);

    if (problems.isNotEmpty) throw ConfigurationException(problems);

    return McpConfig(
      apiUrl: apiUrl!,
      email: email!,
      password: password!,
      serverName: serverName,
      logTools: logTools,
    );
  }

  static bool parseBool(
    String key,
    Map<String, String> env,
    List<String> problems,
  ) {
    final raw = env[key]?.trim();
    if (raw == null || raw.isEmpty) return false;
    switch (raw.toLowerCase()) {
      case 'true':
      case '1':
      case 'yes':
        return true;
      case 'false':
      case '0':
      case 'no':
        return false;
      default:
        problems.add('$key="$raw" must be "true" or "false"');
        return false;
    }
  }
}
