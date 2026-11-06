# Chacha Reports: implementation plan

A client-side SvelteKit app on Netlify, reading the POS data in Supabase.

## Decisions

| Topic | Decision |
|---|---|
| Hosting | Netlify, static single-page app, `reports.chacha.id` |
| Stack | SvelteKit (adapter-static), Svelte 5, Tailwind, supabase-js |
| Login | Email and password, public sign-up off, invitation only |
| Roles | Owner sees everything. Viewer sees sales reports only |
| Sales numbers | Same as the POS Today screen: cancelled orders excluded, cups are the sum of quantities |
| Cash | No drawer tracking. Money figures come from orders |
| Salary | Monthly base of Rp 1.500.000 plus commission, no deductions |
| Commission | Rp 1.000 per cup from cup 21, counted per outlet per day. Everyone who clocked in that day earns the full amount. No minimum time |

## Security model

- The browser only holds the publishable key. It can call the functions below and read no table.
- Every report function checks the signed-in user against `dashboard_users`, and salary functions also require the owner role.
- Inviting and removing people needs the secret key, so it runs in the `manage-users` Edge Function, which checks the caller is an owner.
- The first owner is set by the `dashboard_bootstrap` table, which is filled in directly in the database so the email stays out of this public repository.

## Phase 1: login and sales dashboard

1. **Database** (`003_reports.sql`): `dashboard_users`, `dashboard_bootstrap`, report functions.
2. **Edge Function** (`manage-users`): invite, resend, remove.
3. **Auth settings**: sign-up off, site URL and redirect URLs.
4. **App**: sign in, set password, Daily, Sales, Best sellers, By time, Users.
5. **Hosting**: GitHub repository, Netlify project, custom domain and HTTPS.

## Phase 2: attendance and payroll

1. **Database** (`004_employees.sql`): `attendance`, `pay_rates`, `commission_rules`, `payroll_periods`, `payroll_lines`, and functions.
2. **POS**: clock in and clock out on the tablet, offline first through the existing sync queue, with a Room migration. A separate `sync_attendance` function leaves `sync_push` untouched, so tablets on the old version keep working.
3. **App**: Attendance and Salary screens.
4. **Locking**: an approved month never changes. If orders arrive or are cancelled after locking, the commission difference moves to the next month as a correction.

## Applying database changes

Run the files in `supabase/migrations` in order in the Supabase SQL editor. `001` and `002` live in the POS project. Then set the first owner once:

```sql
insert into public.dashboard_bootstrap (email) values ('owner@example.com');
```

Creating that user in Supabase (Authentication, Users, Add user, auto confirm) makes them the owner, and they are asked to replace the starter password at first sign-in.

## Before inviting other people

Supabase's built-in mail is rate limited and meant for testing. Connect your own SMTP sender in Authentication settings before relying on invitation emails.
