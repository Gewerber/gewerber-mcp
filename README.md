# gewerber-mcp

An MCP (Model Context Protocol) server that lets an AI agent act as a
**Gewerber product admin/moderator**. It replaces a hand-rolled admin panel:
the agent manages the backend **through the official Serverpod endpoints** of
`gewerber_backend_client` — direct database access is neither used nor
possible.

Read tools are available to accounts with the global `moderator` role;
destructive tools additionally require the `admin` role and forward an
explicit `confirm: true` to the backend, which enforces it server-side and
writes an audit trail entry for every mutation.

## Security notes

- The credentials in `GEWERBER_MCP_EMAIL` / `GEWERBER_MCP_PASSWORD` belong to
  a real account. Treat the MCP configuration like production secrets; anyone
  who can talk to this MCP server can do everything the account's role allows.
- Roles live in the backend `admin_user` allowlist and are resolved from the
  database on every request. There is deliberately no MCP tool to grant them:
  grant the first admin out of band with
  [`gewerber_backend_server/tool/grant_admin.sql`](https://github.com/Gewerber/gewerber-backend/blob/main/gewerber_backend_server/tool/grant_admin.sql).
- All mutations (`users_ban`, `users_unban`, `membership_set_role`,
  `invoice_cancel_admin`, `guidance_tip_upsert`) require an explicit
  `confirm: true` parameter and are audited on the backend.
- This package is private infrastructure. Do not publish it or wire it into
  any OSS artifact.

## Configuration (environment variables)

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `GEWERBER_MCP_API_URL` | no | `http://localhost:8080` | Base URL of the Serverpod backend |
| `GEWERBER_MCP_EMAIL` | **yes** | — | Admin/moderator account email |
| `GEWERBER_MCP_PASSWORD` | **yes** | — | Account password |
| `GEWERBER_MCP_SERVER_NAME` | no | `gewerber-admin` | Name reported to the MCP client |
| `GEWERBER_MCP_LOG_TOOLS` | no | off | `true` logs every tool call to **stderr** |

See `.env.example`. Never commit a real `.env`.

## Connecting an agent

### opencode / Claude Desktop compatible

```json
{
  "mcpServers": {
    "gewerber-admin": {
      "command": "dart",
      "args": [
        "run", "-C", "/absolute/path/to/gewerber-mcp", "bin/gewerber_mcp.dart"
      ],
      "env": {
        "GEWERBER_MCP_API_URL": "http://localhost:8080",
        "GEWERBER_MCP_EMAIL": "admin@example.com",
        "GEWERBER_MCP_PASSWORD": "change-me"
      }
    }
  }
}
```

### Compiled binary (faster startup)

```bash
dart compile exe bin/gewerber_mcp.dart -o build/gewerber-mcp
```

```json
{
  "mcpServers": {
    "gewerber-admin": {
      "command": "/absolute/path/to/gewerber-mcp/build/gewerber-mcp",
      "env": {
        "GEWERBER_MCP_EMAIL": "admin@example.com",
        "GEWERBER_MCP_PASSWORD": "change-me"
      }
    }
  }
}
```

## Tools

| Tool | Arguments | Role | Description |
|---|---|---|---|
| `stats_overview` | – | moderator | Platform counters: users total/7d/30d, businesses, invoices per status, running timers |
| `users_search` | `query?`, `limit?`, `cursor?` | moderator | Keyset-paginated user search by email substring |
| `users_get` | `userId` (UUID) | moderator | Full dossier: profile, auth status, memberships, global role |
| `users_ban` | `userId`, `reason`, `confirm` | **admin** | Block sign-in immediately, purge refresh tokens, audit reason |
| `users_unban` | `userId`, `confirm` | **admin** | Lift a ban |
| `users_verify_email_check` | `userId` | moderator | Read-only email-verification compliance check (audited) |
| `businesses_search` | `query?`, `limit?`, `cursor?` | moderator | Keyset-paginated business search by name |
| `businesses_get` | `businessId` | moderator | Business with all memberships |
| `membership_set_role` | `membershipId`, `role` (`owner`\|`admin`\|`member`), `confirm` | **admin** | Change tenant role; refuses demoting the last owner |
| `invoices_list` | `businessId?`, `status?`, `from?`, `to?`, `limit?`, `cursor?` | moderator | Cross-tenant invoices by issue date desc |
| `invoices_get` | `invoiceId` | moderator | Single invoice across tenants |
| `invoice_cancel_admin` | `invoiceId`, `reason`, `confirm` | **admin** | Cancel sent/partiallyPaid/overdue invoice (GoBD-safe) |
| `audit_query` | `actorUserId?`, `action?`, `since?`, `limit?` | moderator | Newest-first audit trail |
| `guidance_tips_list` | – | moderator | Effective guidance tips as users see them |
| `guidance_tip_upsert` | `topic`, `title`, `body`, `confirm` | **admin** | Create/replace an admin tip by unique topic |

Dates are ISO-8601 strings (`2026-01-31`, `2026-01-31T23:59:59Z`). UUIDs must
be in canonical form. Results are returned as pretty-printed JSON.

## Authentication flow

On startup the server signs in via the backend's email IdP
(`emailIdp.login`) and stores the JWT access/refresh pair. A
`JwtAuthKeyProvider` attaches `Authorization: Bearer <jwt>` to every call and
refreshes tokens proactively before expiry. If a call still fails with HTTP
401 (e.g. stale refresh token after a backend restart), the server refreshes,
then re-logs-in once, and retries the call once.

## Development

```bash
dart pub get     # uses pubspec_overrides.yaml (gitignored) for local dev
dart analyze     # required: 0 issues
dart format .    # required before commit
dart test        # unit tests, no live backend needed
```

Dependency resolution: `pubspec.yaml` points at the public GitHub repos
(`feat/admin-api` until merged; the branch must be pushed first). For local
development a gitignored `pubspec_overrides.yaml` maps both packages to
sibling checkouts:

```yaml
dependency_overrides:
  gewerber_backend_client:
    path: ../gewerber-backend/gewerber_backend_client
  gewerber_commercial_client:
    path: ../gewerber-backend--stubs/gewerber_commercial_client
```

## Troubleshooting

| Symptom | Cause & fix |
|---|---|
| Startup error listing missing env vars | Set `GEWERBER_MCP_EMAIL` / `GEWERBER_MCP_PASSWORD` (see `.env.example`) |
| `invalid credentials` at startup | Wrong email/password — check the env values; also confirm the account is not blocked |
| Tool result `NotFound: …` | Entity id does not exist; re-check ids with the search/get tools first |
| Tool result `Forbidden: …` | Account has no (or too low) global role in the `admin_user` allowlist — grant `moderator` for reads, `admin` for writes via `grant_admin.sql`; then retry |
| `401` after backend restart | Should self-heal via refresh/re-login; if persistent, restart the MCP process and verify credentials |
| `Validation failed … confirm` | Destructive tool called without `confirm: true`; state what you will change, then confirm |
| Cannot reach backend | Check `GEWERBER_MCP_API_URL`; the user runs the backend with `serverpod start` locally on port 8080 |

## Scope & limitations

- Only the open-core admin surface is exposed. Payment/banking/tax modules
  are intentionally out of scope (open-core boundaries).
- No DB access: everything goes through generated endpoint clients.
- Unit tests run offline; end-to-end behaviour against a live backend should
  be smoke-tested manually after `serverpod start`.
