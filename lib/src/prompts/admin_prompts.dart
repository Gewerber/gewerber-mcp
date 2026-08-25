import 'package:dart_mcp/server.dart';

/// The MCP prompts offered by the Gewerber admin server.
///
/// Prompts are short, structured playbooks the client can instantiate so an
/// agent always follows the same safe review/investigation routine.
abstract final class AdminPrompts {
  /// `admin_dashboard` — argument-free operational morning review.
  static final Prompt dashboard = Prompt(
    name: 'admin_dashboard',
    description:
        'Operational morning review of the whole platform: growth numbers, '
        'overdue invoices and recent (admin) activity, ending with a '
        'risk summary. Read-only.',
  );

  /// `investigate_user` — investigation plan for one account.
  static final Prompt investigateUser = Prompt(
    name: 'investigate_user',
    description:
        'Step-by-step investigation of a single user account: identify it '
        'via search, open the dossier, correlate audit entries and conclude '
        'with a recommendation. Mutations require explicit confirmation.',
    arguments: [
      PromptArgument(
        name: 'email',
        description:
            'Email address (or distinctive substring) of the user to '
            'investigate.',
        required: true,
      ),
    ],
  );

  /// All prompts in registration order.
  static List<Prompt> get all => [dashboard, investigateUser];

  /// Implementation for [dashboard].
  static GetPromptResult renderDashboard(
    GetPromptRequest request,
  ) => GetPromptResult(
    messages: [
      PromptMessage(
        role: Role.user,
        content: Content.text(
          text:
              'You are the Gewerber operations assistant running the daily '
              'admin review over the MCP tools. Work through these steps, '
              'then summarize.\n'
              '\n'
              '1. Platform pulse — call `stats_overview`:\n'
              '   - users total vs. new users in the last 7/30 days (trend);\n'
              '   - businesses total;\n'
              '   - active timers (who is working right now).\n'
              '2. Money at risk — call `invoices_list` with status="overdue":\n'
              '   - list invoice id, business id, issue date per row;\n'
              '   - mark invoices overdue for more than 30 days as urgent.\n'
              '3. Who changed what — call `audit_query` with since=<yesterday '
              'as ISO-8601>; optionally narrow with action="admin." prefix '
              'filters (e.g. admin.usersBan, admin.invoiceCancel) to see '
              'admin/moderator mutations first.\n'
              '4. Close with a compact operational summary:\n'
              '   - growth (users/businesses),\n'
              '   - risks (total overdue amount, suspicious bans or '
              'cancellations),\n'
              '   - suggested next actions for a human operator.\n'
              '\n'
              'Rules:\n'
              '- This review is read-only; do not run destructive tools.\n'
              '- Any later write (users_ban, users_unban, '
              'membership_set_role, invoice_cancel_admin, '
              'guidance_tip_upsert) needs the admin role AND an explicit '
              'confirm=true — state exactly what you are about to change '
              'before confirming.',
        ),
      ),
    ],
  );

  /// Implementation for [investigateUser].
  static GetPromptResult renderInvestigateUser(GetPromptRequest request) {
    final rawEmail = request.arguments?['email'];
    final email = rawEmail is String ? rawEmail.trim() : null;
    final subject = (email == null || email.isEmpty) ? '<email>' : email;
    return GetPromptResult(
      messages: [
        PromptMessage(
          role: Role.user,
          content: Content.text(
            text:
                'Investigate the Gewerber account "$subject" using the admin MCP '
                'tools and report findings.\n'
                '\n'
                '1. Identify — call `users_search` with query="$subject".\n'
                '   - If nothing matches, stop and say so; never guess ids.\n'
                '   - If several match, list them and ask which one is meant.\n'
                '2. Dossier — call `users_get` with the userId found:\n'
                '   - profile name, email confirmed state;\n'
                '   - auth status: blocked (= banned)? global admin role?\n'
                '   - memberships: which businesses and which roles '
                '(owner/admin/member)?\n'
                '3. Audit trail — call `audit_query` with actorUserId=<userId> '
                'to see what this user did recently; also look for admin actions '
                'that touched them (e.g. action=admin.usersBan).\n'
                '4. Conclusion:\n'
                '   - summarize who the user is and what they did;\n'
                '   - give a recommendation with concrete next steps.\n'
                '\n'
                'Guardrails:\n'
                '- `users_verify_email_check` is a read-only compliance check — '
                'safe to run any time.\n'
                '- Banning via `users_ban` requires a mandatory reason (stored '
                'in the audit trail) and explicit confirm=true after you '
                'verified the userId.\n'
                '- Lifting a ban (`users_unban`) likewise needs confirm=true.\n'
                '- Do not run other destructive tools unless the task '
                'explicitly asks for it.',
          ),
        ),
      ],
    );
  }
}
