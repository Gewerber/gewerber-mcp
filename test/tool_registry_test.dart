import 'dart:async';

import 'package:gewerber_backend_client/gewerber_backend_client.dart';
import 'package:gewerber_mcp/gewerber_mcp.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

/// The full set of tools this MCP server must expose.
const expectedToolNames = [
  'stats_overview',
  //
  'users_search',
  'users_get',
  'users_ban',
  'users_unban',
  'users_verify_email_check',
  //
  'businesses_search',
  'businesses_get',
  'membership_set_role',
  //
  'invoices_list',
  'invoices_get',
  'invoice_cancel_admin',
  //
  'audit_query',
  //
  'guidance_tips_list',
  'guidance_tip_upsert',
  //
  'promo_code_create',
  'promo_codes_list',
  'promo_code_get',
  'subscription_stats',
  'subscription_get',
  'promo_code_set_status',
];

/// Tools that mutate backend state; they must demand `confirm`.
const destructiveToolNames = {
  'users_ban',
  'users_unban',
  'membership_set_role',
  'invoice_cancel_admin',
  'guidance_tip_upsert',
  'promo_code_create',
  'promo_code_set_status',
};

void main() {
  late ToolContext ctx;
  late Map<String, AdminTool> toolsByName;

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
    ctx = ToolContext(config: config, auth: auth);
    toolsByName = {for (final tool in buildToolCatalog(ctx)) tool.name: tool};
  });

  group('tool catalog', () {
    test('exposes exactly the admin/moderator tool set', () {
      expect(toolsByName.keys, unorderedEquals(expectedToolNames));
    });

    test('every tool has a name, description and object input schema', () {
      for (final tool in toolsByName.values) {
        expect(tool.name, isNotEmpty);
        expect(
          tool.definition.description,
          isNotNull,
          reason: '${tool.name} should document itself',
        );
        expect(
          tool.definition.inputSchema.properties,
          isA<Map?>(),
          reason: '${tool.name} must declare its parameters',
        );
      }
    });

    test('destructive tools require a boolean confirm in their schema', () {
      for (final name in destructiveToolNames) {
        final tool = toolsByName[name]!;

        expect(
          requiredArgs(tool),
          contains('confirm'),
          reason: '$name must declare confirm as a required argument',
        );
        final confirmProperty = propertyOf(tool, 'confirm');
        expect(confirmProperty, isNotNull, reason: '$name.confirm documented');
        expect(
          confirmProperty['type'],
          'boolean',
          reason: '$name.confirm must be typed boolean',
        );
        expect(
          confirmProperty['description'],
          isNotNull,
          reason: '$name.confirm must explain when to set it',
        );
      }
    });

    test('read-only tools never take a confirm parameter', () {
      for (final entry in toolsByName.entries) {
        if (destructiveToolNames.contains(entry.key)) continue;
        expect(
          requiredArgs(entry.value),
          isNot(contains('confirm')),
          reason: '${entry.key} is read-only',
        );
        expect(
          propertiesOf(entry.value).keys,
          isNot(contains('confirm')),
          reason: '${entry.key} is read-only',
        );
      }
    });

    test('enum-typed parameters only offer valid backend values', () {
      final roleValues = enumValuesOf(
        toolsByName['membership_set_role']!,
        'role',
      );
      expect(roleValues, ['owner', 'admin', 'member']);

      final statusValues = enumValuesOf(
        toolsByName['invoices_list']!,
        'status',
      );
      expect(
        statusValues,
        unorderedEquals([
          'draft',
          'sent',
          'paid',
          'partiallyPaid',
          'overdue',
          'cancelled',
        ]),
      );

      final kindValues = enumValuesOf(
        toolsByName['promo_code_create']!,
        'kind',
      );
      expect(kindValues, unorderedEquals(['trial', 'discount', 'attribution']));

      final discountValues = enumValuesOf(
        toolsByName['promo_code_create']!,
        'discountType',
      );
      expect(discountValues, unorderedEquals(['percent', 'fixed']));

      final promoStatusValues = enumValuesOf(
        toolsByName['promo_code_set_status']!,
        'status',
      );
      expect(
        promoStatusValues,
        unorderedEquals(['active', 'disabled', 'archived']),
      );
      expect(
        enumValuesOf(toolsByName['promo_codes_list']!, 'status'),
        unorderedEquals(['active', 'disabled', 'archived']),
      );
    });

    test('key arguments exist where agents need them', () {
      expect(
        requiredArgs(toolsByName['users_ban']!),
        containsAll(['userId', 'reason']),
      );
      expect(
        requiredArgs(toolsByName['users_unban']!),
        containsAll(['userId']),
      );
      expect(
        requiredArgs(toolsByName['invoice_cancel_admin']!),
        containsAll(['invoiceId', 'reason']),
      );
      expect(
        requiredArgs(toolsByName['guidance_tip_upsert']!),
        containsAll(['topic', 'title', 'body']),
      );
      expect(
        propertiesOf(toolsByName['audit_query']!).keys,
        containsAll(['actorUserId', 'action', 'since', 'limit']),
      );
      expect(
        propertiesOf(toolsByName['invoices_list']!).keys,
        containsAll(['businessId', 'status', 'from', 'to', 'limit', 'cursor']),
      );
      expect(
        requiredArgs(toolsByName['promo_code_create']!),
        containsAll(['code', 'kind']),
      );
      expect(
        propertiesOf(toolsByName['promo_code_create']!).keys,
        containsAll([
          'planCode',
          'trialDays',
          'discountType',
          'discountPercent',
          'discountMinor',
          'maxRedemptions',
          'perUserLimit',
          'validFrom',
          'validUntil',
          'campaign',
          'ref',
          'note',
        ]),
      );
      expect(
        requiredArgs(toolsByName['promo_code_set_status']!),
        containsAll(['id', 'status']),
      );
      expect(requiredArgs(toolsByName['promo_code_get']!), containsAll(['id']));
      expect(
        requiredArgs(toolsByName['subscription_get']!),
        containsAll(['userId']),
      );
      expect(
        propertiesOf(toolsByName['promo_codes_list']!).keys,
        containsAll(['status', 'limit']),
      );
      expect(
        propertiesOf(toolsByName['subscription_stats']!),
        isEmpty,
        reason: 'subscription_stats takes no arguments',
      );
    });
  });

  group('GewerberMcpServer', () {
    test(
      'constructs over a channel with the full registered tool list',
      () async {
        // In-memory stand-in for stdio; the sink side needs a listener so its
        // close-future can complete once the peer shuts down.
        final fromClient = StreamController<String>();
        final toClient = StreamController<String>();
        final sub = toClient.stream.listen(null);

        final server = GewerberMcpServer(
          StreamChannel(fromClient.stream, toClient.sink),
          ctx: ctx,
        );

        // Server-side catalog is populated without any MCP handshake.
        expect(
          server.tools.map((t) => t.name),
          hasLength(expectedToolNames.length),
        );

        await fromClient.close(); // peer sees end-of-stream -> shuts down
        await server.done;
        await sub.cancel();
        await toClient.close();
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}

/// dart_mcp models are extension types over plain JSON maps; the runtime
/// representation is the underlying map, so reading schema internals via
/// casts is safe here.
Map<String, Object?> _raw(Object? node) =>
    node == null ? const {} : (node as Map).cast<String, Object?>();

Map<String, Object?> propertyOf(AdminTool tool, String name) =>
    _raw(propertiesOf(tool)[name]);

Map<String, Object?> propertiesOf(AdminTool tool) =>
    _raw(tool.definition.inputSchema.properties);

/// Names of arguments marked required in the tool input schema.
List<String> requiredArgs(AdminTool tool) =>
    tool.definition.inputSchema.required ?? const [];

/// The allowed values of an untitled single-select enum argument.
List<String> enumValuesOf(AdminTool tool, String property) {
  final prop = propertyOf(tool, property);
  if (prop.isEmpty) return const [];
  // dart_mcp stores enum values as an iterable, not a list.
  return ((prop['enum'] as Iterable?) ?? const []).cast<String>().toList();
}
