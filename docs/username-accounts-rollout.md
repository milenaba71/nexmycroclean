# Username and password accounts

Status: implementation tested locally; database migration not applied because the approval review declined it. Do not merge the frontend before applying and verifying `sql/username_accounts.sql`.

- New accounts use a unique username and an optional contact email. Their internal Auth email uses a reserved `.invalid` domain and cannot receive mail.
- Existing email accounts continue working. An administrator can add a username without changing the account identity or production assignments.
- Administrators create/reset operator and viewer passwords; only the Super Admin manages administrator accounts.
- Passwords use Supabase Auth, are never returned in lists, and are not included in application database or audit payloads.
- Mandatory first change is enforced server-side. Reset timestamps invalidate older application sessions, including Storage access checks.
- The `mycroclean-accounts` Edge Function verifies passwords for login and validates caller JWT, active membership, session and role for account management. Its gateway JWT check is disabled because login has no session yet; authenticated operations check the JWT inside the handler.
- Account login attempts are limited to 10 per identifier per 15 minutes, with an overall cap of 300 per 15 minutes. Supabase Auth rate limits also apply.
- New-user Auth creation is rolled back if the atomic member/username save fails. Existing profile/password partial failures have an explicit error message.

## Rollout order
1. Apply `sql/username_accounts.sql` through the approved Supabase migration mechanism.
2. Verify function privileges and active-member/session checks. The RPC `laundry_accounts_service` must only be executable by service_role.
3. Deploy the Edge Function from `supabase/functions/mycroclean-accounts` (version 1 already deployed, unused by the current public frontend).
4. Run authenticated administrator creation/reset and operator first-change verification with designated test accounts.
5. Publish `accounts.js`, `cloud.js`, and `index.html` together.

## Verification performed
- Local PostgreSQL-compatible checks: alias uniqueness, ordinary-admin/Super-Admin restrictions, anonymous service-RPC denial, active session checks, forced change, old-session rejection and login throttling.
- Edge-handler tests: invalid JWT/role denial, create without email, Auth-create rollback, reset metadata, generic login errors and current-password verification for own changes.
- Browser checks: create without email, show-password control, optional reset on edit, mandatory first-change gate and mobile layout; existing production, calendar, rental and PDF tests also passed.
- Live account creation/reset has not been performed; database activation is pending.

`node tests/accounts-edge.cjs` runs the standalone Edge-handler tests with Node 24.
