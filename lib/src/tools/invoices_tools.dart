import 'package:dart_mcp/server.dart';

import '../errors/tool_errors.dart';

import '../util/parsing.dart';
import 'tool_context.dart';

/// Cross-tenant invoice reads plus admin-side cancellation.
List<AdminTool> invoicesTools(ToolContext ctx) {
  final client = ctx.auth.client;
  return [
    AdminTool(
      Tool(
        name: 'invoices_list',
        description:
            'Keyset-paginated invoice list across tenants, ordered by issue '
            'date descending. Optional filters: business, status, issue-date '
            'range (from inclusive, to inclusive). Returns `nextCursor` for '
            'paging. Requires moderator role or higher.',
        inputSchema: Schema.object(
          properties: {
            'businessId': Schema.int(
              description: 'Restrict to one tenant (numeric business id).',
            ),
            'status': UntitledSingleSelectEnumSchema(
              values: invoiceStatusValues.keys,
              description: 'Filter by invoice status.',
            ),
            'from': Schema.string(
              description: 'Earliest issue date, ISO-8601 (inclusive).',
            ),
            'to': Schema.string(
              description: 'Latest issue date, ISO-8601 (inclusive).',
            ),
            'limit': Schema.int(
              description:
                  'Page size (default $defaultPageLimit, max $maxPageLimit).',
            ),
            'cursor': Schema.string(
              description: '`nextCursor` from the previous page.',
            ),
          },
        ),
      ),
      ctx.guarded('invoices_list', (request) async {
        final args = request.arguments ?? const <String, Object?>{};
        final page = await ctx.auth.run(
          () => client.adminInvoices.invoicesList(
            businessId: optionalInt(args, 'businessId', max: 1 << 62),
            status: optionalInvoiceStatus(args, 'status'),
            from: optionalIsoDate(args, 'from'),
            to: optionalIsoDate(args, 'to'),
            limit: optionalInt(args, 'limit', max: maxPageLimit),
            cursor: optionalString(args, 'cursor'),
          ),
        );
        return jsonResult(page.toJson());
      }),
    ),
    AdminTool(
      Tool(
        name: 'invoices_get',
        description:
            'A single invoice across tenants by numeric id. Requires '
            'moderator role or higher.',
        inputSchema: Schema.object(
          properties: {
            'invoiceId': Schema.int(description: 'Numeric invoice id.'),
          },
          required: ['invoiceId'],
        ),
      ),
      ctx.guarded('invoices_get', (request) async {
        final args = request.arguments ?? const <String, Object?>{};
        final invoiceId = optionalInt(args, 'invoiceId', max: 1 << 62);
        if (invoiceId == null) {
          throw ToolInputError('`invoiceId` must be a positive integer.');
        }
        final invoice = await ctx.auth.run(
          () => client.adminInvoices.invoicesGet(invoiceId),
        );
        return jsonResult(invoice.toJson());
      }),
    ),
    AdminTool(
      Tool(
        name: 'invoice_cancel_admin',
        description:
            'DESTRUCTIVE. Cancels an invoice cross-tenant. Only invoices in '
            'states sent / partiallyPaid / overdue can be cancelled; drafts '
            'belong to their owners and paid invoices are immutable (GoBD) — '
            'both are rejected with Conflict. The reason is stored in the '
            'audit trail. Requires admin role and confirm=true.',
        inputSchema: Schema.object(
          properties: {
            'invoiceId': Schema.int(description: 'Numeric invoice id.'),
            'reason': Schema.string(
              description:
                  'Why this invoice is cancelled (mandatory, goes into the '
                  'audit trail).',
            ),
            'confirm': Schema.bool(
              description:
                  'Must be true. Only confirm after verifying invoiceId and '
                  'stating the consequence.',
            ),
          },
          required: ['invoiceId', 'reason', 'confirm'],
        ),
      ),
      ctx.guarded('invoice_cancel_admin', (request) async {
        final args = request.arguments ?? const <String, Object?>{};
        requireConfirm(args);
        final invoiceId = optionalInt(args, 'invoiceId', max: 1 << 62);
        if (invoiceId == null) {
          throw ToolInputError('`invoiceId` must be a positive integer.');
        }
        final invoice = await ctx.auth.run(
          () => client.adminInvoices.invoiceCancelAdmin(
            invoiceId: invoiceId,
            reason: requireString(args, 'reason'),
            confirm: true,
          ),
        );
        return jsonResult(invoice.toJson());
      }),
    ),
  ];
}
