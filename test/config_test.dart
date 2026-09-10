import 'package:gewerber_mcp/gewerber_mcp.dart';
import 'package:test/test.dart';

void main() {
  group('McpConfig.fromEnvironment', () {
    const validEnv = {
      'GEWERBER_MCP_EMAIL': 'admin@example.com',
      'GEWERBER_MCP_PASSWORD': 'secret',
    };

    test('accepts a minimal configuration with defaults', () {
      final config = McpConfig.fromEnvironment(validEnv);
      expect(config.email, 'admin@example.com');
      expect(config.password, 'secret');
      expect(config.apiUrl, Uri.parse('http://localhost:8080'));
      expect(config.serverName, 'gewerber-admin');
      expect(config.logTools, isFalse);
    });

    test('parses all optional values', () {
      final config = McpConfig.fromEnvironment({
        ...validEnv,
        'GEWERBER_MCP_API_URL': 'https://api.gewerber.de',
        'GEWERBER_MCP_SERVER_NAME': 'gwb-prod-admin',
        'GEWERBER_MCP_LOG_TOOLS': 'true',
      });
      expect(config.apiUrl, Uri.parse('https://api.gewerber.de'));
      expect(config.serverName, 'gwb-prod-admin');
      expect(config.logTools, isTrue);
    });

    test('trims whitespace around values', () {
      final config = McpConfig.fromEnvironment({
        'GEWERBER_MCP_EMAIL': '  admin@example.com ',
        'GEWERBER_MCP_PASSWORD': ' secret ',
      });
      expect(config.email, 'admin@example.com');
      expect(config.password, 'secret');
    });

    test('rejects missing email and reports all problems at once', () {
      expect(
        () => McpConfig.fromEnvironment({
          'GEWERBER_MCP_PASSWORD': 'secret',
          'GEWERBER_MCP_API_URL': 'http://localhost:8080',
        }),
        throwsA(
          isA<ConfigurationException>().having(
            (e) => e.problems,
            'problems',
            hasLength(1),
          ),
        ),
      );
    });

    test('rejects empty password', () {
      expect(
        () => McpConfig.fromEnvironment({
          ...validEnv,
          'GEWERBER_MCP_PASSWORD': '   ',
        }),
        throwsA(isA<ConfigurationException>()),
      );
    });

    test('rejects an invalid API URL', () {
      try {
        McpConfig.fromEnvironment({
          ...validEnv,
          'GEWERBER_MCP_API_URL': 'not a url',
        });
        fail('expected ConfigurationException');
      } on ConfigurationException catch (e) {
        expect(e.problems.single, contains('GEWERBER_MCP_API_URL'));
      }
    });

    test('rejects an API URL without http(s) scheme', () {
      expect(
        () => McpConfig.fromEnvironment({
          ...validEnv,
          'GEWERBER_MCP_API_URL': 'ftp://files.example.com',
        }),
        throwsA(isA<ConfigurationException>()),
      );
    });

    test('rejects an invalid LOG_TOOLS value', () {
      expect(
        () => McpConfig.fromEnvironment({
          ...validEnv,
          'GEWERBER_MCP_LOG_TOOLS': 'sometimes',
        }),
        throwsA(isA<ConfigurationException>()),
      );
    });

    test('message lists every problem for the operator', () {
      try {
        McpConfig.fromEnvironment(const {});
        fail('expected ConfigurationException');
      } on ConfigurationException catch (e) {
        expect(e.problems, hasLength(2));
        expect(e.message, contains('GEWERBER_MCP_EMAIL'));
        expect(e.message, contains('GEWERBER_MCP_PASSWORD'));
      }
    });
  });

  group('CliArgs.parse', () {
    test('accepts the long --flag value form for all four flags', () {
      final cli = CliArgs.parse([
        '--host',
        'api.gewerber.de',
        '--port',
        '443',
        '--email',
        'admin@example.com',
        '--password',
        's3cret',
      ]);
      expect(cli.host, 'api.gewerber.de');
      expect(cli.port, 443);
      expect(cli.email, 'admin@example.com');
      expect(cli.password, 's3cret');
      expect(cli.help, isFalse);
    });

    test('accepts the --flag=value form for all four flags', () {
      final cli = CliArgs.parse([
        '--host=api.gewerber.de',
        '--port=8443',
        '--email=admin@example.com',
        '--password=s3cret',
      ]);
      expect(cli.host, 'api.gewerber.de');
      expect(cli.port, 8443);
      expect(cli.email, 'admin@example.com');
      expect(cli.password, 's3cret');
    });

    test('--login is an alias for --email', () {
      final cli = CliArgs.parse(['--login', 'admin@example.com']);
      expect(cli.email, 'admin@example.com');
    });

    test('--help short-circuits validation', () {
      final cli = CliArgs.parse(['--nonsense', '--port', 'abc', '--help']);
      expect(cli.help, isTrue);
    });

    test('-h short-circuits validation', () {
      final cli = CliArgs.parse(['-h', '--port', '0']);
      expect(cli.help, isTrue);
    });

    test('unknown option reports a problem naming it', () {
      try {
        CliArgs.parse(['--nope']);
        fail('expected ConfigurationException');
      } on ConfigurationException catch (e) {
        expect(e.problems.single, contains('unknown option "--nope"'));
        expect(e.title, 'Invalid command-line arguments');
      }
    });

    test('missing value at the end of argv', () {
      expect(
        () => CliArgs.parse(['--host']),
        throwsA(
          isA<ConfigurationException>().having((e) => e.problems, 'problems', [
            'missing value for --host',
          ]),
        ),
      );
    });

    test('a value that looks like a flag is not consumed', () {
      expect(
        () => CliArgs.parse(['--host', '--port', '443']),
        throwsA(
          isA<ConfigurationException>().having((e) => e.problems, 'problems', [
            'missing value for --host',
          ]),
        ),
      );
    });

    test('empty --port= value is a problem', () {
      expect(
        () => CliArgs.parse(['--port=']),
        throwsA(
          isA<ConfigurationException>().having((e) => e.problems, 'problems', [
            'missing value for --port',
          ]),
        ),
      );
    });

    test('duplicated flags keep the last value', () {
      final cli = CliArgs.parse([
        '--host',
        'first.example',
        '--host',
        'second.example',
        '--port',
        '1',
        '--port',
        '2',
        '--email',
        'a@example.com',
        '--login',
        'b@example.com',
        '--password',
        'p1',
        '--password',
        'p2',
      ]);
      expect(cli.host, 'second.example');
      expect(cli.port, 2);
      expect(cli.email, 'b@example.com');
      expect(cli.password, 'p2');
    });

    test('stray positional argument is a problem', () {
      expect(
        () => CliArgs.parse(['serve']),
        throwsA(
          isA<ConfigurationException>().having(
            (e) => e.problems.single,
            'problem',
            contains('serve'),
          ),
        ),
      );
    });

    test('rejects invalid ports', () {
      for (final bad in ['0', '70000', '-1', 'abc', '8080.0']) {
        expect(
          () => CliArgs.parse(['--port', bad]),
          throwsA(
            isA<ConfigurationException>().having(
              (e) => e.problems.single,
              'problem',
              contains('--port'),
            ),
          ),
          reason: '--port $bad must be rejected',
        );
      }
    });

    test('trims whitespace around values', () {
      final cli = CliArgs.parse([
        '--host',
        '  api.example.com  ',
        '--port',
        ' 9091 ',
        '--email',
        ' admin@example.com ',
        '--password',
        '  s3cret ',
      ]);
      expect(cli.host, 'api.example.com');
      expect(cli.port, 9091);
      expect(cli.email, 'admin@example.com');
      expect(cli.password, 's3cret');
    });
  });

  group('CliArgs.wantsHelp', () {
    test('detects --help and -h among other arguments', () {
      expect(CliArgs.wantsHelp(['--host', 'x', '--help']), isTrue);
      expect(CliArgs.wantsHelp(['-h']), isTrue);
    });

    test('is false without a help flag', () {
      expect(CliArgs.wantsHelp(['--host', 'x', '--port', '443']), isFalse);
    });
  });

  group('McpConfig.load', () {
    const validEnv = {
      'GEWERBER_MCP_EMAIL': 'admin@example.com',
      'GEWERBER_MCP_PASSWORD': 'secret',
    };
    const creds = ['--email', 'admin@example.com', '--password', 'secret'];

    test('accepts an args-only minimal configuration', () {
      final config = McpConfig.load(args: creds, env: const {});
      expect(config.email, 'admin@example.com');
      expect(config.password, 'secret');
      expect(config.apiUrl, Uri.parse('http://localhost:8080'));
    });

    test('precedence: args over env over default', () {
      final config = McpConfig.load(
        args: [
          '--email',
          'cli@example.com',
          '--password',
          'clipw',
          '--port',
          '7000',
        ],
        env: {...validEnv, 'GEWERBER_MCP_API_URL': 'http://localhost:9999'},
      );
      expect(config.email, 'cli@example.com');
      expect(config.password, 'clipw');
      expect(config.apiUrl, Uri.parse('http://localhost:7000'));
    });

    test('env API URL is used when no host/port args are given', () {
      final config = McpConfig.load(
        args: creds,
        env: {...validEnv, 'GEWERBER_MCP_API_URL': 'https://api.gewerber.de'},
      );
      expect(config.apiUrl, Uri.parse('https://api.gewerber.de'));
    });

    test('--host keeps the scheme and port of the env URL', () {
      final config = McpConfig.load(
        args: [...creds, '--host', 'example.com'],
        env: {
          ...validEnv,
          'GEWERBER_MCP_API_URL': 'https://api.gewerber.de:8443',
        },
      );
      expect(config.apiUrl, Uri.parse('https://example.com:8443'));
    });

    test('--port keeps the host and scheme of the env URL', () {
      final config = McpConfig.load(
        args: [...creds, '--port', '9091'],
        env: {...validEnv, 'GEWERBER_MCP_API_URL': 'https://api.gewerber.de'},
      );
      expect(config.apiUrl, Uri.parse('https://api.gewerber.de:9091'));
    });

    test('--host and --port together apply to the default URL', () {
      final config = McpConfig.load(
        args: [...creds, '--host', 'h.example', '--port', '1234'],
        env: const {},
      );
      expect(config.apiUrl, Uri.parse('http://h.example:1234'));
    });

    test('no env URL: --host example.com yields http://example.com:8080', () {
      final config = McpConfig.load(
        args: [...creds, '--host', 'example.com'],
        env: const {},
      );
      expect(config.apiUrl, Uri.parse('http://example.com:8080'));
    });

    test('no env URL: --port 9091 yields http://localhost:9091', () {
      final config = McpConfig.load(
        args: [...creds, '--port', '9091'],
        env: const {},
      );
      expect(config.apiUrl, Uri.parse('http://localhost:9091'));
    });

    test('required settings missing everywhere aggregate into one throw', () {
      expect(
        () => McpConfig.load(args: const [], env: const {}),
        throwsA(
          isA<ConfigurationException>().having(
            (e) => e.problems,
            'problems',
            hasLength(2),
          ),
        ),
      );
    });

    test('invalid env API URL is still rejected under load', () {
      expect(
        () => McpConfig.load(
          args: creds,
          env: {...validEnv, 'GEWERBER_MCP_API_URL': 'not a url'},
        ),
        throwsA(
          isA<ConfigurationException>().having(
            (e) => e.problems.single,
            'problem',
            contains('GEWERBER_MCP_API_URL'),
          ),
        ),
      );
    });

    test('host that cannot be applied yields a problem, not a crash', () {
      expect(
        () => McpConfig.load(
          args: [...creds, '--host', 'example.com:8080'],
          env: const {},
        ),
        throwsA(
          isA<ConfigurationException>().having(
            (e) => e.problems.single,
            'problem',
            contains('--host'),
          ),
        ),
      );
    });

    test('explicit default port is kept on the Uri (pinned behavior)', () {
      // No smart stripping in our code: Uri keeps port 80 on the http base
      // URL; only Dart's own rendering omits the redundant ":80" suffix.
      final config = McpConfig.load(
        args: [...creds, '--port', '80'],
        env: const {},
      );
      expect(config.apiUrl.port, 80);
      expect(config.apiUrl.toString(), 'http://localhost');
    });
  });
}
