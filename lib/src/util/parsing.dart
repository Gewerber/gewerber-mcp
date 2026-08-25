import 'package:gewerber_backend_client/gewerber_backend_client.dart';

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

/// Default page size used when the agent does not pass an explicit limit.
const int defaultPageLimit = 20;

/// Maximum page size the tools allow (mirrors sane backend limits).
const int maxPageLimit = 100;

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
