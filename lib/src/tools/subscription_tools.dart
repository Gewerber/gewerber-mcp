import 'package:dart_mcp/server.dart';
import 'package:gewerber_backend_commercial_client/gewerber_backend_commercial_client.dart'
    show AdminPromoCodeView;

import '../errors/tool_errors.dart';

import '../util/parsing.dart';
import 'tool_context.dart';

/// Subscription promo-code campaign management and portfolio reads.
///
/// Talks to the commercial module's `adminSubscription` endpoint: reads
/// require the moderator role, mutations the admin role. Both mutations
/// follow the repo-wide `confirm: true` convention and are audited
/// server-side (`admin.promo_code.create` / `admin.promo_code.status_set`).
List<AdminTool> subscriptionTools(ToolContext ctx) {
  final adminSubscription =
      ctx.auth.client.modules.commercial.adminSubscription;
  return [
    AdminTool(
      Tool(
        name: 'promo_code_create',
        description:
            'MUTATION. Creates a subscription promo code. kind="trial" '
            'grants free days (requires trialDays >= 1); kind="discount" '
            'requires discountType plus discountPercent (1-100) or, for '
            '"fixed", discountMinor in EUR cents (>= 1); kind="attribution" '
            'only tracks campaign/ref labels. planCode must exist in the '
            'plan catalog. The code string is normalized (trim, lowercase) '
            'server-side; duplicates are rejected. New codes start "active". '
            'Requires admin role and confirm=true.',
        inputSchema: Schema.object(
          properties: {
            'code': Schema.string(
              description: 'Raw code string as printed by the campaign.',
            ),
            'kind': UntitledSingleSelectEnumSchema(
              values: promoCodeKindValues.keys,
              description: 'What the code grants.',
            ),
            'planCode': Schema.string(
              description:
                  'Plan the benefit is tied to; must exist in the catalog.',
            ),
            'trialDays': Schema.int(
              description: 'Free days; required (>= 1) for kind="trial".',
            ),
            'discountType': UntitledSingleSelectEnumSchema(
              values: promoDiscountTypeValues.keys,
              description: 'Required for kind="discount".',
            ),
            'discountPercent': Schema.int(
              description:
                  'Percent 1-100; required with discountType="percent".',
            ),
            'discountMinor': Schema.int(
              description:
                  'Fixed amount in EUR minor units (cents), >= 1; required '
                  'with discountType="fixed".',
            ),
            'maxRedemptions': Schema.int(
              description: 'Global redemption cap (>= 1); omit for uncapped.',
            ),
            'perUserLimit': Schema.int(
              description: 'Redemptions per user (>= 1, default 1).',
            ),
            'validFrom': Schema.string(
              description:
                  'ISO-8601 start of the validity window; omit for '
                  '"immediately".',
            ),
            'validUntil': Schema.string(
              description:
                  'ISO-8601 end of the validity window; omit for "never"; '
                  'must be after validFrom.',
            ),
            'campaign': Schema.string(
              description: 'Free-form campaign label (shows up in stats).',
            ),
            'ref': Schema.string(
              description: 'Free-form referral / press source label.',
            ),
            'note': Schema.string(description: 'Internal note for operators.'),
            'confirm': Schema.bool(
              description:
                  'Must be true. Only confirm after double-checking code, '
                  'kind and discount parameters.',
            ),
          },
          required: ['code', 'kind', 'confirm'],
        ),
      ),
      ctx.guarded('promo_code_create', (request) async {
        final args = request.arguments ?? const <String, Object?>{};
        requireConfirm(args);
        final created = await ctx.auth.run(
          () =>
              adminSubscription.codesCreate(buildPromoCodeCreateRequest(args)),
        );
        return jsonResult(created.toJson());
      }),
    ),
    AdminTool(
      Tool(
        name: 'promo_codes_list',
        description:
            'Lists promo codes, newest first, each with its total redemption '
            'count. Optional status filter (active|disabled|archived) and '
            'limit (default $defaultPageLimit, max $maxPageLimit). Returns a '
            'compact summary per code — use promo_code_get for full detail '
            'including recent redemptions. Requires moderator role or '
            'higher.',
        inputSchema: Schema.object(
          properties: {
            'status': UntitledSingleSelectEnumSchema(
              values: promoCodeStatusValues.keys,
              description: 'Only return codes in this lifecycle status.',
            ),
            'limit': Schema.int(
              description:
                  'Page size (default $defaultPageLimit, max $maxPageLimit).',
            ),
          },
        ),
      ),
      ctx.guarded('promo_codes_list', (request) async {
        final args = request.arguments ?? const <String, Object?>{};
        final codes = await ctx.auth.run(
          () => adminSubscription.codesList(
            status: optionalPromoCodeStatus(args, 'status')?.name,
            limit: optionalInt(args, 'limit', max: maxPageLimit),
          ),
        );
        return jsonResult([for (final code in codes) _promoCodeSummary(code)]);
      }),
    ),
    AdminTool(
      Tool(
        name: 'promo_code_get',
        description:
            'Full detail of one promo code, including its most recent '
            'redemptions (userId, businessId, UTM labels, redeemedAt). Fails '
            'with reason "notFound" for an unknown id. Requires moderator '
            'role or higher.',
        inputSchema: Schema.object(
          properties: {'id': Schema.int(description: 'Numeric promo code id.')},
          required: ['id'],
        ),
      ),
      ctx.guarded('promo_code_get', (request) async {
        final args = request.arguments ?? const <String, Object?>{};
        final detail = await ctx.auth.run(
          () => adminSubscription.codeGet(requirePositiveInt(args, 'id')),
        );
        return jsonResult(detail.toJson());
      }),
    ),
    AdminTool(
      Tool(
        name: 'subscription_stats',
        description:
            'Portfolio-wide subscription numbers: counts per status '
            '(trialing/active/pastDue/canceled/expired), live subscriptions, '
            'MRR estimate in EUR minor units, total promo redemptions, '
            'subscriptions per plan and redemptions per campaign label. '
            'Requires moderator role or higher.',
        inputSchema: Schema.object(properties: {}),
      ),
      ctx.guarded('subscription_stats', (_) async {
        final stats = await ctx.auth.run(adminSubscription.subscriptionsStats);
        return jsonResult(stats.toJson());
      }),
    ),
    AdminTool(
      Tool(
        name: 'subscription_get',
        description:
            'All subscription rows of one user (any scope, any status), '
            'newest first, each with plan code/name, billing period, trial '
            'end, cancel flag and the applied promo code id. An unknown user '
            'yields an empty list. Requires moderator role or higher.',
        inputSchema: Schema.object(
          properties: {'userId': Schema.string(description: 'AuthUser UUID.')},
          required: ['userId'],
        ),
      ),
      ctx.guarded('subscription_get', (request) async {
        final args = request.arguments ?? const <String, Object?>{};
        final subscriptions = await ctx.auth.run(
          () => adminSubscription.subscriptionGetAdmin(
            requireUuid(args, 'userId').uuid,
          ),
        );
        return jsonResult([
          for (final subscription in subscriptions) subscription.toJson(),
        ]);
      }),
    ),
    AdminTool(
      Tool(
        name: 'promo_code_set_status',
        description:
            'MUTATION. Sets the lifecycle status of a promo code: "active" '
            '(redeemable), "disabled" (temporarily off) or "archived" '
            '(permanent end). Fails with reason "notFound" for an unknown '
            'id. Audited. Requires admin role and confirm=true.',
        inputSchema: Schema.object(
          properties: {
            'id': Schema.int(description: 'Numeric promo code id.'),
            'status': UntitledSingleSelectEnumSchema(
              values: promoCodeStatusValues.keys,
              description: 'New lifecycle status for the code.',
            ),
            'confirm': Schema.bool(
              description:
                  'Must be true. Only confirm after verifying the id and its '
                  'code via promo_code_get.',
            ),
          },
          required: ['id', 'status', 'confirm'],
        ),
      ),
      ctx.guarded('promo_code_set_status', (request) async {
        final args = request.arguments ?? const <String, Object?>{};
        requireConfirm(args);
        final updated = await ctx.auth.run(
          () => adminSubscription.codesSetStatus(
            requirePositiveInt(args, 'id'),
            requirePromoCodeStatus(args, 'status').name,
          ),
        );
        return jsonResult(updated.toJson());
      }),
    ),
  ];
}

/// Compact, agent-friendly projection of one list row (full detail lives in
/// `promo_code_get`).
Map<String, Object?> _promoCodeSummary(AdminPromoCodeView code) => {
  'id': code.id,
  'code': code.code,
  'kind': code.kind.name,
  'status': code.status.name,
  if (code.planCode != null) 'planCode': code.planCode,
  if (code.trialDays != null) 'trialDays': code.trialDays,
  if (code.discountType != null) 'discountType': code.discountType!.name,
  if (code.discountPercent != null) 'discountPercent': code.discountPercent,
  if (code.discountMinor != null) 'discountMinor': code.discountMinor,
  'redemptionCount': code.redemptionCount,
  if (code.validUntil != null) 'validUntil': code.validUntil!.toIso8601String(),
  if (code.campaign != null) 'campaign': code.campaign,
};
