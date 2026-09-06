import 'package:gewerber_backend_client/gewerber_backend_client.dart';
import 'package:gewerber_backend_commercial_client/gewerber_backend_commercial_client.dart'
    show
        AdminPromoCodeCreateRequest,
        PromoCodeKind,
        PromoCodeStatus,
        PromoDiscountType;

import '../errors/tool_errors.dart';

/// Canonical UUID string form accepted by the tools.
final RegExp _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Reads a required non-empty string argument; surrounding whitespace is
/// trimmed.
String requireString(Map<String, Object?> args, String name) {
  final value = args[name];
  if (value is! String || value.trim().isEmpty) {
    throw ToolInputError('`$name` must be a non-empty string.');
  }
  return value.trim();
}

/// Reads an optional string argument; surrounding whitespace is trimmed.
String? optionalString(Map<String, Object?> args, String name) {
  final value = args[name];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw ToolInputError('`$name` must be a non-empty string when provided.');
  }
  return value.trim();
}

/// Reads the mandatory `confirm: true` flag of destructive tools.
///
/// The backend enforces this too; checking here gives agents a precise,
/// immediate error instead of a round-trip.
bool requireConfirm(Map<String, Object?> args) {
  final confirm = args['confirm'];
  if (confirm is! bool) {
    throw ToolInputError(
      '`confirm` (boolean) is required for destructive actions — pass '
      'confirm=true only after you have stated what you are about to do.',
    );
  }
  if (!confirm) {
    throw ToolInputError(
      'Refusing to run a destructive action without explicit approval: '
      'pass `confirm: true` once you have double-checked the target.',
    );
  }
  return confirm;
}

/// Reads an optional positive integer argument.
int? optionalInt(
  Map<String, Object?> args,
  String name, {
  int min = 1,
  required int max,
}) {
  final value = args[name];
  if (value == null) return null;
  if (value is! int || value < min || value > max) {
    throw ToolInputError('`$name` must be an integer between $min and $max.');
  }
  return value;
}

/// Reads a mandatory positive integer argument (ids, counts).
int requirePositiveInt(Map<String, Object?> args, String name) {
  final value = args[name];
  if (value is! int || value < 1) {
    throw ToolInputError('`$name` must be a positive integer.');
  }
  return value;
}

/// Default page size used when the agent does not pass an explicit limit;
/// mirrors `defaultAdminListLimit` in the backend's `admin_list_limits.dart`.
const int defaultPageLimit = 50;

/// Maximum page size; mirrors the backend hard cap of 200 rows per page
/// (`admin_list_limits.dart` / `core/pagination/list_limits.dart`).
const int maxPageLimit = 200;

/// Parses a UUID argument into a [UuidValue].
UuidValue requireUuid(Map<String, Object?> args, String name) {
  final raw = requireString(args, name);
  if (!_uuidPattern.hasMatch(raw)) {
    throw ToolInputError(
      '`$name`="$raw" is not a valid UUID '
      '(expected canonical form 8-4-4-4-12 hex digits).',
    );
  }
  try {
    return UuidValue.fromString(raw);
  } on FormatException catch (e) {
    throw ToolInputError('`$name`="$raw" is not a valid UUID (${e.message}).');
  }
}

/// Parses an optional ISO-8601 date/datetime argument.
DateTime? optionalIsoDate(Map<String, Object?> args, String name) {
  final raw = args[name];
  if (raw == null) return null;
  if (raw is! String) {
    throw ToolInputError('`$name` must be an ISO-8601 string.');
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    throw ToolInputError(
      '`$name`="$raw" is not a valid ISO-8601 date '
      '(examples: 2026-01-31, 2026-01-31T23:59:59Z).',
    );
  }
  return parsed;
}

/// Values of [MembershipRole] as accepted by the backend.
const Map<String, MembershipRole> membershipRoleValues = {
  'owner': MembershipRole.owner,
  'admin': MembershipRole.admin,
  'member': MembershipRole.member,
};

/// Parses a [MembershipRole] argument from its serialized name.
MembershipRole requireMembershipRole(Map<String, Object?> args, String name) =>
    _enumArg(membershipRoleValues, args, name);

/// Values of [InvoiceStatus] as accepted by the backend.
const Map<String, InvoiceStatus> invoiceStatusValues = {
  'draft': InvoiceStatus.draft,
  'sent': InvoiceStatus.sent,
  'paid': InvoiceStatus.paid,
  'partiallyPaid': InvoiceStatus.partiallyPaid,
  'overdue': InvoiceStatus.overdue,
  'cancelled': InvoiceStatus.cancelled,
};

/// Parses an optional [InvoiceStatus] filter argument.
InvoiceStatus? optionalInvoiceStatus(Map<String, Object?> args, String name) {
  if (!args.containsKey(name) || args[name] == null) return null;
  return _enumArg(invoiceStatusValues, args, name);
}

/// Values of [PromoCodeKind] as accepted by the backend.
const Map<String, PromoCodeKind> promoCodeKindValues = {
  'trial': PromoCodeKind.trial,
  'discount': PromoCodeKind.discount,
  'attribution': PromoCodeKind.attribution,
};

/// Values of [PromoCodeStatus] as accepted by the backend.
const Map<String, PromoCodeStatus> promoCodeStatusValues = {
  'active': PromoCodeStatus.active,
  'disabled': PromoCodeStatus.disabled,
  'archived': PromoCodeStatus.archived,
};

/// Values of [PromoDiscountType] as accepted by the backend.
const Map<String, PromoDiscountType> promoDiscountTypeValues = {
  'percent': PromoDiscountType.percent,
  'fixed': PromoDiscountType.fixed,
};

/// Parses a required [PromoCodeKind] argument from its serialized name.
PromoCodeKind requirePromoCodeKind(Map<String, Object?> args, String name) =>
    _enumArg(promoCodeKindValues, args, name);

/// Parses a required [PromoCodeStatus] argument from its serialized name.
PromoCodeStatus requirePromoCodeStatus(
  Map<String, Object?> args,
  String name,
) => _enumArg(promoCodeStatusValues, args, name);

/// Parses an optional [PromoCodeStatus] filter argument.
PromoCodeStatus? optionalPromoCodeStatus(
  Map<String, Object?> args,
  String name,
) {
  if (!args.containsKey(name) || args[name] == null) return null;
  return _enumArg(promoCodeStatusValues, args, name);
}

/// Parses an optional [PromoDiscountType] argument.
PromoDiscountType? optionalPromoDiscountType(
  Map<String, Object?> args,
  String name,
) {
  if (!args.containsKey(name) || args[name] == null) return null;
  return _enumArg(promoDiscountTypeValues, args, name);
}

/// Maps `promo_code_create` arguments into an [AdminPromoCodeCreateRequest].
///
/// Applies the same kind-sanity rules as the backend (`trial` requires
/// `trialDays >= 1`; `discount` requires `discountType` plus the matching
/// value; caps must be >= 1; `validUntil` must be after `validFrom`) so the
/// agent gets an immediate, precise error instead of a round-trip. The
/// backend re-validates everything (and normalizes `code`).
AdminPromoCodeCreateRequest buildPromoCodeCreateRequest(
  Map<String, Object?> args,
) {
  final kind = requirePromoCodeKind(args, 'kind');
  final trialDays = optionalInt(args, 'trialDays', max: 1 << 62);
  final discountType = optionalPromoDiscountType(args, 'discountType');
  final discountPercent = optionalInt(args, 'discountPercent', max: 100);
  final discountMinor = optionalInt(args, 'discountMinor', max: 1 << 62);
  final maxRedemptions = optionalInt(args, 'maxRedemptions', max: 1 << 62);
  final perUserLimit = optionalInt(args, 'perUserLimit', max: 1 << 62);
  final validFrom = optionalIsoDate(args, 'validFrom');
  final validUntil = optionalIsoDate(args, 'validUntil');

  switch (kind) {
    case PromoCodeKind.trial:
      if (trialDays == null) {
        throw ToolInputError(
          '`trialDays` (integer >= 1) is required for kind="trial".',
        );
      }
    case PromoCodeKind.discount:
      if (discountType == null) {
        throw ToolInputError(
          '`discountType` ("percent" or "fixed") is required for '
          'kind="discount".',
        );
      }
      if (discountType == PromoDiscountType.percent &&
          discountPercent == null) {
        throw ToolInputError(
          '`discountPercent` (integer 1-100) is required with '
          'discountType="percent".',
        );
      }
      if (discountType == PromoDiscountType.fixed && discountMinor == null) {
        throw ToolInputError(
          '`discountMinor` (EUR minor units, integer >= 1) is required with '
          'discountType="fixed".',
        );
      }
    case PromoCodeKind.attribution:
      break;
  }

  if (validFrom != null &&
      validUntil != null &&
      !validUntil.isAfter(validFrom)) {
    throw ToolInputError('`validUntil` must be after `validFrom`.');
  }

  return AdminPromoCodeCreateRequest(
    code: requireString(args, 'code'),
    kind: kind,
    discountType: discountType,
    discountPercent: discountPercent,
    discountMinor: discountMinor,
    trialDays: trialDays,
    planCode: optionalString(args, 'planCode'),
    maxRedemptions: maxRedemptions,
    perUserLimit: perUserLimit,
    validFrom: validFrom,
    validUntil: validUntil,
    campaign: optionalString(args, 'campaign'),
    ref: optionalString(args, 'ref'),
    note: optionalString(args, 'note'),
  );
}

T _enumArg<T>(Map<String, T> values, Map<String, Object?> args, String name) {
  final raw = requireString(args, name);
  final value = values[raw];
  if (value == null) {
    throw ToolInputError(
      '`$name`="$raw" is not a valid value. Allowed: '
      '${values.keys.map((v) => '"$v"').join(', ')}.',
    );
  }
  return value;
}
