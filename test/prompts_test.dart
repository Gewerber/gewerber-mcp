import 'dart:async';

import 'package:dart_mcp/server.dart';
import 'package:gewerber_backend_client/gewerber_backend_client.dart';
import 'package:gewerber_mcp/gewerber_mcp.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

void main() {
  late GewerberMcpServer server;

  setUp(() {
    final config = McpConfig.fromEnvironment({
      'GEWERBER_MCP_EMAIL': 'admin@example.com',
      'GEWERBER_MCP_PASSWORD': 'secret',
    });
    final auth = BackendAuth(
      Client(config.apiUrl.toString()),
      config.email,
      config.password,
    );
    // In-memory stand-in for stdio; the sink side needs a listener so its
    // close-future can complete once the peer shuts down.
    final fromClient = StreamController<String>();
    final toClient = StreamController<String>()..stream.listen(null);
    server = GewerberMcpServer(
      StreamChannel(fromClient.stream, toClient.sink),
      ctx: ToolContext(config: config, auth: auth),
    );
    addTearDown(() async {
      await fromClient.close();
      await server.done;
      await toClient.close();
    });
  });

  group('prompt catalog', () {
    test('registers exactly the admin playbooks', () {
      expect(server.prompts.map((p) => p.name), [
        'admin_dashboard',
        'investigate_user',
      ]);
    });

    test('both prompts document themselves', () {
      for (final prompt in server.prompts) {
        expect(prompt.description, isNotNull);
        expect(prompt.description, isNotEmpty);
      }
    });

    test('investigate_user requires an email argument', () {
      final prompt = server.prompts.singleWhere(
        (p) => p.name == 'investigate_user',
      );
      final arguments = prompt.arguments ?? const <PromptArgument>[];
      expect(arguments, hasLength(1));
      expect(arguments.single.name, 'email');
      expect(
        arguments.single.required,
        isTrue,
        reason: 'agents must pass the email to investigate',
      );
      expect(arguments.single.description, isNotNull);
    });

    test('admin_dashboard takes no arguments', () {
      final dashboard = server.prompts.singleWhere(
        (p) => p.name == 'admin_dashboard',
      );
      expect(dashboard.arguments ?? const [], isEmpty);
    });
  });

  group('prompt rendering', () {
    GetPromptRequest request([Map<String, String>? arguments]) =>
        GetPromptRequest(name: 'unused', arguments: arguments);

    // dart_mcp models are extension types over plain maps; at runtime the
    // content node is its underlying JSON map.
    String textOf(GetPromptResult result) => [
      for (final message in result.messages)
        ((message.content as Map)['text'] ?? '') as String,
    ].join('\n');

    test('admin_dashboard renders the review playbook', () {
      final result = AdminPrompts.renderDashboard(request());
      expect(result.messages, isNotEmpty);
      final text = textOf(result);
      expect(text, isNotEmpty);
      // The playbook references the tools it wants the agent to use.
      expect(text, contains('stats_overview'));
      expect(text, contains('invoices_list'));
      expect(text, contains('overdue'));
      expect(text, contains('audit_query'));
      expect(text, contains('confirm=true'));
    });

    test('investigate_user interpolates the email argument', () {
      final result = AdminPrompts.renderInvestigateUser(
        request({'email': ' kunde@example.de '}),
      );
      final text = textOf(result);
      expect(
        text,
        contains('kunde@example.de'),
        reason: 'whitespace-trimmed email lands in the message',
      );
      expect(text, contains('users_search'));
      expect(text, contains('users_get'));
      expect(text, contains('audit_query'));
      expect(text, contains('users_verify_email_check'));
      expect(text, contains('confirm=true'));
    });

    test('investigate_user falls back to a placeholder without email', () {
      final result = AdminPrompts.renderInvestigateUser(request());
      final text = textOf(result);
      expect(text, isNotEmpty);
      expect(text, contains('<email>'));
    });

    test('rendered messages are user-role text content', () {
      for (final result in [
        AdminPrompts.renderDashboard(request()),
        AdminPrompts.renderInvestigateUser(request({'email': 'a@b.c'})),
      ]) {
        for (final message in result.messages) {
          expect(message.role, Role.user);
          expect((message.content as Map)['type'], 'text');
        }
      }
    });
  });

  group('server wiring', () {
    test('registered tool list stays at 24 alongside prompts', () {
      expect(server.tools, hasLength(24));
      expect(server.prompts, hasLength(2));
    });
  });
}
