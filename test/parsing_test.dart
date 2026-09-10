import 'package:gewerber_backend_client/gewerber_backend_client.dart';
import 'package:gewerber_backend_commercial_client/gewerber_backend_commercial_client.dart'
    show PromoCodeKind, PromoCodeStatus, PromoDiscountType;
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

    test('requirePositiveInt rejects missing/zero/negative/non-int', () {
      expect(requirePositiveInt({'id': 7}, 'id'), 7);
      expect(() => requirePositiveInt({}, 'id'), throwsToolInputError);
      expect(() => requirePositiveInt({'id': 0}, 'id'), throwsToolInputError);
      expect(() => requirePositiveInt({'id': -3}, 'id'), throwsToolInputError);
      expect(() => requirePositiveInt({'id': '7'}, 'id'), throwsToolInputError);
    });
  });

  group('promo code enums', () {
    test('maps match the backend enum names', () {
      expect(promoCodeKindValues.keys, ['trial', 'discount', 'attribution']);
      expect(promoCodeStatusValues.keys, ['active', 'disabled', 'archived']);
      expect(promoDiscountTypeValues.keys, ['percent', 'fixed']);
    });

    test('requirePromoCodeKind rejects unknown values and lists allowed', () {
      expect(
        requirePromoCodeKind({'kind': 'trial'}, 'kind'),
        PromoCodeKind.trial,
      );
      try {
        requirePromoCodeKind({'kind': 'freebie'}, 'kind');
        fail('expected ToolInputError');
      } on ToolInputError catch (e) {
        expect(e.message, contains('"trial"'));
        expect(e.message, contains('"discount"'));
        expect(e.message, contains('"attribution"'));
      }
    });

    test('status accessors parse / pass through null', () {
      expect(
        requirePromoCodeStatus({'status': 'archived'}, 'status'),
        PromoCodeStatus.archived,
      );
      expect(optionalPromoCodeStatus({}, 'status'), isNull);
      expect(
        optionalPromoCodeStatus({'status': 'disabled'}, 'status'),
        PromoCodeStatus.disabled,
      );
      expect(
        () => optionalPromoCodeStatus({'status': 'gone'}, 'status'),
        throwsToolInputError,
      );
      expect(
        optionalPromoDiscountType({'discountType': 'percent'}, 'discountType'),
        PromoDiscountType.percent,
      );
      expect(optionalPromoDiscountType({}, 'discountType'), isNull);
    });
  });

  group('buildPromoCodeCreateRequest', () {
    test('maps a full trial request incl. ISO dates and optional fields', () {
      final request = buildPromoCodeCreateRequest({
        'code': ' SPRING26 ',
        'kind': 'trial',
        'trialDays': 30,
        'planCode': 'pro-monthly',
        'maxRedemptions': 500,
        'perUserLimit': 2,
        'validFrom': '2026-03-01',
        'validUntil': '2026-03-31T23:59:59Z',
        'campaign': 'spring-26',
        'ref': 'press',
        'note': 'internal',
      });
      expect(request.code, 'SPRING26');
      expect(request.kind, PromoCodeKind.trial);
      expect(request.trialDays, 30);
      expect(request.planCode, 'pro-monthly');
      expect(request.maxRedemptions, 500);
      expect(request.perUserLimit, 2);
      expect(request.validFrom!.isAtSameMomentAs(DateTime(2026, 3, 1)), isTrue);
      expect(
        request.validUntil!.isAtSameMomentAs(
          DateTime.utc(2026, 3, 31, 23, 59, 59),
        ),
        isTrue,
      );
      expect(request.campaign, 'spring-26');
      expect(request.ref, 'press');
      expect(request.note, 'internal');
    });

    test('perUserLimit defaults to 1 when omitted', () {
      final request = buildPromoCodeCreateRequest({
        'code': 'X',
        'kind': 'attribution',
      });
      expect(request.perUserLimit, 1);
      expect(request.trialDays, isNull);
      expect(request.discountType, isNull);
    });

    test('discount/percent and discount/fixed map their values', () {
      final percent = buildPromoCodeCreateRequest({
        'code': 'P',
        'kind': 'discount',
        'discountType': 'percent',
        'discountPercent': 25,
      });
      expect(percent.discountType, PromoDiscountType.percent);
      expect(percent.discountPercent, 25);

      final fixed = buildPromoCodeCreateRequest({
        'code': 'F',
        'kind': 'discount',
        'discountType': 'fixed',
        'discountMinor': 500,
      });
      expect(fixed.discountType, PromoDiscountType.fixed);
      expect(fixed.discountMinor, 500);
    });

    test('trial without trialDays is rejected with a precise error', () {
      expect(
        () => buildPromoCodeCreateRequest({'code': 'X', 'kind': 'trial'}),
        throwsA(
          isA<ToolInputError>().having(
            (e) => e.message,
            'message',
            contains('trialDays'),
          ),
        ),
      );
    });

    test('discount without type / matching value is rejected', () {
      expect(
        () => buildPromoCodeCreateRequest({'code': 'X', 'kind': 'discount'}),
        throwsA(
          isA<ToolInputError>().having(
            (e) => e.message,
            'message',
            contains('discountType'),
          ),
        ),
      );
      expect(
        () => buildPromoCodeCreateRequest({
          'code': 'X',
          'kind': 'discount',
          'discountType': 'percent',
        }),
        throwsA(
          isA<ToolInputError>().having(
            (e) => e.message,
            'message',
            contains('discountPercent'),
          ),
        ),
      );
      expect(
        () => buildPromoCodeCreateRequest({
          'code': 'X',
          'kind': 'discount',
          'discountType': 'fixed',
        }),
        throwsA(
          isA<ToolInputError>().having(
            (e) => e.message,
            'message',
            contains('discountMinor'),
          ),
        ),
      );
    });

    test('missing code / kind produce required-argument errors', () {
      expect(
        () => buildPromoCodeCreateRequest({'kind': 'attribution'}),
        throwsA(
          isA<ToolInputError>().having(
            (e) => e.message,
            'message',
            contains('`code`'),
          ),
        ),
      );
      expect(
        () => buildPromoCodeCreateRequest({'code': 'X'}),
        throwsA(
          isA<ToolInputError>().having(
            (e) => e.message,
            'message',
            contains('`kind`'),
          ),
        ),
      );
    });

    test('bad enum value / bad date / inverted window are rejected', () {
      expect(
        () => buildPromoCodeCreateRequest({'code': 'X', 'kind': 'bogus'}),
        throwsToolInputError,
      );
      expect(
        () => buildPromoCodeCreateRequest({
          'code': 'X',
          'kind': 'attribution',
          'validUntil': '31.03.2026',
        }),
        throwsToolInputError,
      );
      expect(
        () => buildPromoCodeCreateRequest({
          'code': 'X',
          'kind': 'attribution',
          'validFrom': '2026-04-01',
          'validUntil': '2026-03-01',
        }),
        throwsA(
          isA<ToolInputError>().having(
            (e) => e.message,
            'message',
            contains('after'),
          ),
        ),
      );
    });

    test('out-of-range discountPercent is rejected', () {
      expect(
        () => buildPromoCodeCreateRequest({
          'code': 'X',
          'kind': 'discount',
          'discountType': 'percent',
          'discountPercent': 101,
        }),
        throwsToolInputError,
      );
    });

    test('result serializes with the protocol class name', () {
      final request = buildPromoCodeCreateRequest({
        'code': 'X',
        'kind': 'attribution',
      });
      expect(
        request.toJsonForProtocol()['__className__'],
        'gewerber_backend_commercial.AdminPromoCodeCreateRequest',
      );
    });
  });
}

final Matcher throwsToolInputError = throwsA(isA<ToolInputError>());
