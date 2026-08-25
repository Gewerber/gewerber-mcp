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
}
