# Chacha Reports

The owner dashboard for the Chacha POS: daily sales, best sellers, sales by time, attendance, and salary with commission. It runs at [reports.chacha.id](https://reports.chacha.id).

It's a client-side SvelteKit app on Netlify, reading the POS data in Supabase through functions only. See [docs/PLAN.md](docs/PLAN.md) for the decisions and security model.

## Screens

| Screen | Who | What |
|---|---|---|
| Daily | Everyone | Sales, cups, orders and average order against the same weekday last week; orders by hour; sales by item (every drink sold, with category totals); payments; cashiers; sugar and ice; cancellations |
| Sales | Everyone | A date range, day by day, average by weekday, CSV export |
| Best sellers | Everyone | Every drink ranked by cups or sales, with a total and category totals; opens on today, with yesterday or a range one tap away; a closed "Custom sugar and ice" section lists drinks ordered with less sugar, zero sugar or less ice |
| By time | Everyone | Average cups per weekday and hour, prep time, top drink by time of day |
| Profit and loss | Owner | Sales − HPP − staff (base + actual commission) − monthly costs, per month, with break-even cups a day and net profit by day |
| Return on investment | Owner | Starting capital, how much net profit has paid back, payback at the current pace, cups a day needed for a payback target |
| Monthly costs | Owner | Rent and utilities per month, each change applying from a chosen month |
| Menu costs (HPP) | Owner | HPP per cup (ingredients + packaging) per drink, food cost and margin per cup, changes with an "applies from" date and history |
| Attendance | Owner | Who clocked in, missed clock-outs, adding or correcting a day |
| Salary and commission | Owner | Base salary plus commission per month, day-by-day detail, approve and lock |
| Users | Owner | Invite, resend, remove |

Numbers match the POS Today screen: cancelled orders are left out and cups are the sum of quantities. Hours use outlet time (WIB), and the `TEST` outlet never appears.

## Margin

Owners also see gross margin on Daily, Sales and Best sellers. Viewers don't see costs or margin.

- HPP per cup = ingredients + packaging, from the "Final HPP_Chacha" sheet. Staff, rent and utilities aren't included.
- Margin = price charged − HPP, per cup sold. Cancelled orders don't count.
- A new HPP applies from the date chosen; earlier days keep the HPP they were sold at.
- Drinks with no HPP are counted as "cups without HPP" and left out of the margin, never counted as pure profit.
- Food cost above 45% of the price is marked High.
- Sugar level doesn't change HPP: every cup uses the standard recipe.

## Profit and payback

- Net profit = gross margin − base salaries − actual commission − monthly costs (rent, water, electricity, internet).
- Monthly amounts are spread evenly over the days of their month; a month still running counts only the days so far.
- Counting starts on the opening day. Costs before it are part of the starting capital.
- Forecasts (break-even, payback, cups needed) use the last 30 days' margin per cup and the staff-per-day setting on the ROI screen, and wait for 14 days of sales.

## Pay rules

- Monthly base salary: Neli and Ugan Rp 1.250.000 each and Meirisa and Laura Rp 0, from November 2026 (commission only). No deductions. Change it per person on the Salary screen; it applies from the month shown onward.
- Commission: Rp 1.000 per cup from cup 21, counted on the outlet's cups for the day. From November 2026 the amount is shared equally (rounded down to whole rupiah) by everyone who clocked in that day, so Rp 500 each for two people. No minimum time.
- Approving a month locks it. Orders that sync or are cancelled later are paid as a correction the next month.
- Change the rule on the Salary and commission screen ("Change the rule"). It applies from the month chosen; approved months keep their rule.

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

Netlify builds and deploys every push to `main`. Work on a `feature/…` branch and merge it into `main` to release.

## Database

The migrations (`003` reports, `004` attendance and payroll, `005` HPP and margin, `006` custom sugar and ice, `007` monthly costs, profit and ROI, `008` shared commission) are in `supabase/migrations` and continue the POS project's `001` and `002`. Run them in order in the Supabase SQL editor. The `manage-users` Edge Function is in `supabase/functions` and is deployed from the Supabase dashboard.

The first owner comes from the `dashboard_bootstrap` table, which is filled in directly in the database, never in this public repository. Creating that email's user in Supabase makes it an owner, and it must set a new password at first sign-in.
