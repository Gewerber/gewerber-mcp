import 'dart:io';

import 'cli_args.dart';

/// Package version reported to MCP clients during initialization.
///
/// Keep in sync with `version:` in pubspec.yaml.
const String gewerberMcpVersion = '0.1.0';

/// Thrown when the launch configuration (env vars or command line) does not
/// contain a usable value set.
final class ConfigurationException implements Exception {
  ConfigurationException(
    this.problems, {
    this.title = 'Invalid GEWERBER_MCP_* configuration',
  }) : message =
           '$title:\n'
           '${problems.map((p) => ' - $p').join('\n')}';

  /// Header of [message], naming the configuration source.
  final String title;

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
  /// Thin delegate to [McpConfig.load] without command-line arguments.
  factory McpConfig.fromEnvironment([Map<String, String>? env]) =>
      McpConfig.load(env: env);

  /// Loads the configuration from command-line [args] and [env]
  /// (`Platform.environment` by default).
  ///
  /// Per setting the precedence is *command line > environment > default*.
  /// `--host` and `--port` are applied to the URL taken from
  /// `GEWERBER_MCP_API_URL` (or its default) and keep its scheme and path;
  /// this code does no default-port stripping — the resulting `Uri` is
  /// whatever `Uri.replace` produces (an explicit `:80` stays the URL's
  /// port, even though `Uri.toString()` renders the default port without
  /// the suffix).
  ///
  /// Invalid command-line arguments throw first (from [CliArgs.parse]);
  /// otherwise *all* remaining problems are collected before a single
  /// [ConfigurationException] is thrown so operators can fix everything at
  /// once.
  factory McpConfig.load({List<String>? args, Map<String, String>? env}) {
    final cli = CliArgs.parse(args ?? const []);
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

    // Applies --host/--port to the URL without leaking raw Uri errors.
    Uri? applyToUrl(Uri? base, Uri Function(Uri base) change, String problem) {
      if (base == null) return null;
      try {
        return change(base);
      } on ArgumentError {
        problems.add(problem);
        return null;
      } on FormatException {
        problems.add(problem);
        return null;
      }
    }

    final email = cli.email ?? required('GEWERBER_MCP_EMAIL');
    final password = cli.password ?? required('GEWERBER_MCP_PASSWORD');
    var apiUrl = parseUrl(
      'GEWERBER_MCP_API_URL',
      environment['GEWERBER_MCP_API_URL']?.trim(),
      fallback: Uri.parse(defaultApiUrl),
    );
    final host = cli.host;
    if (host != null) {
      apiUrl = applyToUrl(
        apiUrl,
        (base) => base.replace(host: host),
        '--host="$host" is not a valid host for the API URL '
        '(use GEWERBER_MCP_API_URL for the full URL)',
      );
    }
    final port = cli.port;
    if (port != null) {
      apiUrl = applyToUrl(
        apiUrl,
        (base) => base.replace(port: port),
        '--port=$port cannot be applied to the API URL',
      );
    }
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
