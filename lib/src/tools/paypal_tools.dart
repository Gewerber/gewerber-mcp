import 'dart:convert';

import 'package:dart_mcp/server.dart';

import '../errors/tool_errors.dart';
import '../util/parsing.dart';
import 'tool_context.dart';

/// PayPal catalog provisioning for the subscription plans and discount codes.
///
/// Lives in its own file (next to `subscription_tools.dart`, sharing the same
/// commercial `adminSubscription` endpoint) because these tools operate on the
/// PayPal catalog rather than on promo-code campaigns: they provision products,
/// price plans and discounted plan variants. Reads require the moderator
/// role, both mutations the admin role; the mutations follow the repo-wide
/// `confirm: true` convention and are audited server-side
/// (`admin.paypal.plans_sync` / `admin.paypal.discount_variant_sync`).
List<AdminTool> paypalTools(ToolContext ctx) {
  final adminSubscription =
      ctx.auth.client.modules.commercial.adminSubscription;
  return [
    AdminTool(
      Tool(
        name: 'paypal_plan_sync',
        description:
            'MUTATION. Provisions/updates the PayPal catalog (product plus '
            'monthly/annual price plans) from the plan catalog: syncs every '
            'active plan row and every active discount promo still lacking a '
            'plan variant. Run it after price changes or before the first '
            'checkout; it is idempotent and safe to re-run (rows that already '
            'carry their PayPal ids are skipped, per-item provider failures '
            'are collected into the report and never abort the run). Returns '
            '{plansSynced, plansSkipped, variantsSynced, variantsSkipped, '
            'errors}. Audited. Requires admin role and confirm=true.',
        inputSchema: Schema.object(
          properties: {
            'confirm': Schema.bool(
              description:
                  'Must be true. The call talks to PayPal and creates or '
                  'updates live catalog products and plans.',
            ),
          },
          required: ['confirm'],
        ),
      ),
      ctx.guarded('paypal_plan_sync', (request) async {
        final args = request.arguments ?? const <String, Object?>{};
        requireConfirm(args);
        final report = await ctx.auth.run(adminSubscription.plansSync);
        return jsonResult(jsonDecode(report));
      }),
    ),
    AdminTool(
      Tool(
        name: 'paypal_plans_status',
        description:
            'Read-only PayPal provisioning status: one entry per plan row '
            '(code, currency, monthly/annual prices in minor units, '
            'paypalProductId, paypalPlanIdMonthly, paypalPlanIdAnnual, '
            'monthlySynced, annualSynced, ordered by sortOrder) and one per '
            'active discount promo (code, paypalPlanVariantId, '
            'variantSynced). Pure DB read — works without a configured '
            'gateway. Use it before/after paypal_plan_sync to see what is '
            'still missing. Requires moderator role or higher.',
        inputSchema: Schema.object(properties: {}),
      ),
      ctx.guarded('paypal_plans_status', (_) async {
        final status = await ctx.auth.run(adminSubscription.plansStatus);
        return jsonResult(jsonDecode(status));
      }),
    ),
    AdminTool(
      Tool(
        name: 'paypal_discount_variant_sync',
        description:
            'MUTATION. Provisions the discounted PayPal plan variant of one '
            'active discount promo (covers the monthly price point of the '
            'promo\'s plan); required before that code can be used at '
            'checkout. An already-provisioned promo is returned unchanged. '
            'The promo is addressed by its numeric id (see promo_codes_list '
            '/ promo_code_get); fails with reason "notFound" for an unknown '
            'id and with field "paypal", reason "invalid" when the promo is '
            'not provisionable or PayPal rejects the creation (provider '
            'message surfaced verbatim). Returns {code, '
            'paypalPlanVariantId}. Audited. Requires admin role and '
            'confirm=true.',
        inputSchema: Schema.object(
          properties: {
            'promoCodeId': Schema.int(
              description:
                  'Numeric promo code id of an active "discount" code (from '
                  'promo_codes_list / promo_code_get).',
            ),
            'confirm': Schema.bool(
              description:
                  'Must be true. Only confirm after verifying the id and its '
                  'code/kind via promo_code_get.',
            ),
          },
          required: ['promoCodeId', 'confirm'],
        ),
      ),
      ctx.guarded('paypal_discount_variant_sync', (request) async {
        final args = request.arguments ?? const <String, Object?>{};
        requireConfirm(args);
        final result = await ctx.auth.run(
          () => adminSubscription.discountVariantSync(
            requirePositiveInt(args, 'promoCodeId'),
          ),
        );
        return jsonResult(jsonDecode(result));
      }),
    ),
  ];
}
