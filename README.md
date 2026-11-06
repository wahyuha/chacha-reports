# Chacha Reports

The owner dashboard for the Chacha POS: daily sales, best sellers, sales by time, attendance, and salary with commission. It runs at [reports.chacha.id](https://reports.chacha.id).

It's a client-side SvelteKit app on Netlify, reading the POS data in Supabase through functions only. See [docs/PLAN.md](docs/PLAN.md) for the decisions and security model.

## Screens

| Screen | Who | What |
|---|---|---|
| Daily | Everyone | Sales, cups, orders and average order against the same weekday last week; orders by hour; best sellers; payments; cashiers; sugar and ice; cancellations |
| Sales | Everyone | A date range, day by day, average by weekday, CSV export |
| Best sellers | Everyone | Every drink ranked by cups or sales, with category totals |
| By time | Everyone | Average cups per weekday and hour, prep time, top drink by time of day |
| Attendance | Owner | Who clocked in, missed clock-outs, adding or correcting a day |
| Salary and commission | Owner | Base salary plus commission per month, day-by-day detail, approve and lock |
| Users | Owner | Invite, resend, remove |

Numbers match the POS Today screen: cancelled orders are left out and cups are the sum of quantities. Hours use outlet time (WIB), and the `TEST` outlet never appears.

## Pay rules

- Monthly base salary, Rp 1.500.000 to start, no deductions. Change it per person on the Salary screen; it applies from the month shown onward.
- Commission: Rp 1.000 per cup from cup 21, counted on the outlet's cups for the day. Everyone who clocked in that day earns the full amount. No minimum time.
- Approving a month locks it. Orders that sync or are cancelled later are paid as a correction the next month.
- To change the rule, add a row to `commission_rules` with a new `effective_from` date; earlier months keep the old rule.

## Develop

```bash
pnpm install
```

```bash
pnpm dev
```

Open `http://localhost:5173/?demo` to see every screen with sample data, without signing in. Demo mode exists only in `pnpm dev`; production builds leave it out.

```bash
pnpm check
```

## Deploy

```bash
pnpm build && netlify deploy --prod --dir build
```

## Database

The migrations are in `supabase/migrations` and continue the POS project's `001` and `002`. Run them in order in the Supabase SQL editor. The `manage-users` Edge Function is in `supabase/functions` and is deployed from the Supabase dashboard.

The first owner comes from the `dashboard_bootstrap` table, which is filled in directly in the database, never in this public repository. Creating that email's user in Supabase makes it an owner, and it must set a new password at first sign-in.
