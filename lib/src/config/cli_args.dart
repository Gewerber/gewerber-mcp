import 'config.dart';

/// Parsed command-line launch options for the MCP server.
///
/// Every flag is optional; values merge with the `GEWERBER_MCP_*` environment
/// variables in [McpConfig.load] using the precedence
/// *command line > environment > default*. Parsing performs no I/O and never
/// reads the process environment, so it stays pure and testable.
final class CliArgs {
  const CliArgs({
    this.host,
    this.port,
    this.email,
    this.password,
    this.help = false,
  });

  /// Backend host override, applied to the API URL (keeps its scheme).
  final String? host;

  /// Backend port override, applied to the API URL (range 1..65535).
  final int? port;

  /// Admin/moderator account email (`--login` is an accepted alias).
  final String? email;

  /// Admin/moderator account password.
  final String? password;

  /// Whether `--help` / `-h` was requested.
  final bool help;

  static final RegExp _portPattern = RegExp(r'^\d+$');

  /// Parses raw [argv] (without the program name).
  ///
  /// Supported syntax: `--flag value` and `--flag=value`; a repeated flag
  /// keeps its last value. `--help` / `-h` short-circuits: it returns
  /// `help: true` immediately without validating anything else. All other
  /// problems are collected and thrown as one [ConfigurationException] so
  /// operators can fix everything at once.
  static CliArgs parse(List<String> argv) {
    String? host;
    int? port;
    String? email;
    String? password;
    final problems = <String>[];

    var i = 0;
    while (i < argv.length) {
      final token = argv[i++];
      if (token == '-h') return const CliArgs(help: true);
      if (!token.startsWith('--')) {
        problems.add('unexpected argument "$token" (expected a --flag)');
        continue;
      }

      final eq = token.indexOf('=');
      final name = eq == -1 ? token : token.substring(0, eq);
      final inline = eq == -1 ? null : token.substring(eq + 1);
      if (name == '--help') return const CliArgs(help: true);

      // Consumes this flag's value: the inline `=value` part, or the next
      // argv token unless it is absent or looks like another flag.
      String? takeValue() {
        final String? raw;
        if (inline != null) {
          raw = inline;
        } else if (i < argv.length && !argv[i].startsWith('--')) {
          raw = argv[i++];
        } else {
          raw = null;
        }
        final value = raw?.trim();
        if (value == null || value.isEmpty) {
          problems.add('missing value for $name');
          return null;
        }
        return value;
      }

      switch (name) {
        case '--host':
          host = takeValue() ?? host;
        case '--port':
          final raw = takeValue();
          if (raw == null) break;
          final parsed = _portPattern.hasMatch(raw) ? int.tryParse(raw) : null;
          if (parsed == null) {
            problems.add('$name value "$raw" is not a valid port number');
          } else if (parsed < 1 || parsed > 65535) {
            problems.add(
              '$name value "$raw" is out of range (must be 1..65535)',
            );
          } else {
            port = parsed;
          }
        case '--email' || '--login':
          email = takeValue() ?? email;
        case '--password':
          password = takeValue() ?? password;
        default:
          problems.add('unknown option "$name"');
      }
    }

    if (problems.isNotEmpty) {
      throw ConfigurationException(
        problems,
        title: 'Invalid command-line arguments',
      );
    }
    return CliArgs(host: host, port: port, email: email, password: password);
  }

  /// Whether [argv] asks for the help text — a trivial scan that never
  /// throws, so the server can print usage before any other startup work.
  static bool wantsHelp(List<String> argv) =>
      argv.any((a) => a == '-h' || a == '--help' || a.startsWith('--help='));

  /// Usage text printed on `--help` / `-h`.
  static const String usage = '''
Usage: gewerber-mcp [options]

Options (each overrides its environment variable):
  --host <host>            Backend host, replaces the host of the API URL.
                           Env: GEWERBER_MCP_API_URL
                           (default base: http://localhost:8080)
  --port <port>            Backend port, replaces the port of the API URL.
                           Env: GEWERBER_MCP_API_URL (default: 8080)
  --email, --login <email> Admin/moderator account email. Required.
                           Env: GEWERBER_MCP_EMAIL
  --password <password>    Account password. Required.
                           Env: GEWERBER_MCP_PASSWORD
  --help, -h               Show this help and exit.

Precedence: command-line argument > environment variable > default.
GEWERBER_MCP_SERVER_NAME and GEWERBER_MCP_LOG_TOOLS are environment-only;
there are no command-line equivalents.

Notes:
  - Both `--flag value` and `--flag=value` are accepted; a repeated flag
    keeps its last value.
  - A value that starts with `--` must use the `--flag=value` form
    (e.g. --password=--secret), otherwise it is read as the next flag.
  - For IPv6 backend hosts prefer the full URL in GEWERBER_MCP_API_URL
    (e.g. http://[::1]:8080) over --host.
  - SECURITY: command-line arguments are visible to other users via `ps`
    and are often stored in shell history. On shared machines pass the
    password via GEWERBER_MCP_PASSWORD instead.

Example:
  gewerber-mcp --host api.gewerber.de --port 443 --email admin@example.com
''';
}
