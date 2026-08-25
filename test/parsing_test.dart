import 'package:gewerber_backend_client/gewerber_backend_client.dart';
import 'package:gewerber_mcp/gewerber_mcp.dart';
import 'package:test/test.dart';

void main() {
  group('requireString / optionalString', () {
    test('returns trimmed-required strings', () {
      expect(requireString({'q': ' acme '}, 'q'), 'acme');
    });

    test('rejects missing / non-string / empty required values', () {
      expect(() => requireString({}, 'q'), throwsToolInputError);
      expect(() => requireString({'q': 5}, 'q'), throwsToolInputError);
      expect(() => requireString({'q': '  '}, 'q'), throwsToolInputError);
    });

    test('optionalString passes through null', () {
      expect(optionalString({}, 'cursor'), isNull);
      expect(optionalString({'cursor': null}, 'cursor'), isNull);
      expect(optionalString({'cursor': 'abc'}, 'cursor'), 'abc');
      expect(
        () => optionalString({'cursor': ''}, 'cursor'),
        throwsToolInputError,
      );
    });
  });

  group('requireConfirm', () {
    test('accepts true', () {
      expect(requireConfirm({'confirm': true}), isTrue);
    });

    test('rejects missing, false and non-bool confirm', () {
      expect(() => requireConfirm({}), throwsToolInputError);
      expect(() => requireConfirm({'confirm': false}), throwsToolInputError);
      expect(() => requireConfirm({'confirm': 'true'}), throwsToolInputError);
    });
  });

  group('requireUuid', () {
    const uuid = '550e8400-e29b-41d4-a716-446655440000';

    test('parses a canonical UUID into UuidValue', () {
      final value = requireUuid({'userId': uuid}, 'userId');
      expect(value.uuid.toLowerCase(), uuid);
    });

    test('rejects malformed UUIDs with a precise message', () {
      expect(
        () => requireUuid({'userId': 'not-a-uuid'}, 'userId'),
        throwsA(
          isA<ToolInputError>().having(
            (e) => e.message,
            'message',
            contains('valid UUID'),
          ),
        ),
      );
      // No braces, no urn prefix.
      expect(
        () => requireUuid({
          'userId': '{550e8400-e29b-41d4-a716-446655440000}',
        }, 'userId'),
        throwsToolInputError,
      );
    });
  });

  group('optionalIsoDate', () {
    test('parses date-only and full ISO-8601 timestamps', () {
      final from = optionalIsoDate({'from': '2026-01-31'}, 'from');
      expect(
        from!.isAtSameMomentAs(DateTime(2026, 1, 31)),
        isTrue,
        reason: 'date-only input parses as local midnight',
      );
      final parsed = optionalIsoDate({'to': '2026-01-31T23:59:59Z'}, 'to');
      expect(
        parsed!.isAtSameMomentAs(DateTime.utc(2026, 1, 31, 23, 59, 59)),
        isTrue,
      );
    });

    test('passes null through', () {
      expect(optionalIsoDate({}, 'since'), isNull);
    });

    test('rejects garbage dates', () {
      expect(
        () => optionalIsoDate({'from': '31.01.2026'}, 'from'),
        throwsA(isA<ToolInputError>()),
      );
    });
  });

  group('enum arguments', () {
    test('membership roles match the backend enum names', () {
      expect(
        membershipRoleValues.keys,
        unorderedEquals(['owner', 'admin', 'member']),
      );
      expect(
        requireMembershipRole({'role': 'owner'}, 'role'),
        MembershipRole.owner,
      );
      expect(
        requireMembershipRole({'role': 'admin'}, 'role'),
        MembershipRole.admin,
      );
      expect(
        requireMembershipRole({'role': 'member'}, 'role'),
        MembershipRole.member,
      );
    });

    test('unknown role lists allowed values', () {
      try {
        requireMembershipRole({'role': 'superuser'}, 'role');
        fail('expected ToolInputError');
      } on ToolInputError catch (e) {
        expect(e.message, contains('"owner"'));
        expect(e.message, contains('"admin"'));
        expect(e.message, contains('"member"'));
      }
    });

    test('invoice status matches the backend enum names', () {
      expect(
        invoiceStatusValues.keys,
        unorderedEquals([
          'draft',
          'sent',
          'paid',
          'partiallyPaid',
          'overdue',
          'cancelled',
        ]),
      );
      expect(
        optionalInvoiceStatus({'status': 'partiallyPaid'}, 'status'),
        InvoiceStatus.partiallyPaid,
      );
      expect(optionalInvoiceStatus({}, 'status'), isNull);
    });
  });

  group('limit bounds', () {
    test('page-size constants mirror the backend admin API', () {
      // Backend source of truth: modules/admin/domain/admin_list_limits.dart
      // (defaultAdminListLimit = 50, hard cap 200 via core/pagination).
      expect(defaultPageLimit, 50);
      expect(maxPageLimit, 200);
    });

    test('optionalInt enforces min/max', () {
      expect(optionalInt({'limit': 50}, 'limit', max: maxPageLimit), 50);
      expect(optionalInt({}, 'limit', max: maxPageLimit), isNull);
      expect(
        () => optionalInt({'limit': 0}, 'limit', max: maxPageLimit),
        throwsToolInputError,
      );
      expect(
        () => optionalInt({'limit': 1000}, 'limit', max: maxPageLimit),
        throwsToolInputError,
      );
    });
  });
}

final Matcher throwsToolInputError = throwsA(isA<ToolInputError>());
