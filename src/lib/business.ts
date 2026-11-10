// Profit, break-even and payback forecasts. Owners only.

export type Roi = {
	today: string;
	opened_on: string;
	days_open: number;
	payback_months: number;
	staff_per_day: number;
	capital: { id: string; name: string; amount: number }[];
	net_to_date: number;
	months: { month: string; net: number }[];
	recent: { days: number; sales_days: number; cups: number; net: number; gross: number; costed_cups: number };
	month_base: number;
	month_costs: number;
	rule: { threshold_cups: number; rate_per_cup: number } | null;
};

export const DAYS_PER_MONTH = 365 / 12;
/** Forecasts wait for this many days of sales, so a few strong days can't mislead. */
export const MIN_DAYS = 14;

export const capitalTotal = (r: Roi) => r.capital.reduce((a, c) => a + Number(c.amount), 0);

/** Average gross margin per cup over the last 30 days, or null before the first costed sale. */
export const marginPerCup = (r: Roi) =>
	Number(r.recent.costed_cups) ? Number(r.recent.gross) / Number(r.recent.costed_cups) : null;

/** Staff base salaries plus monthly costs, per day. */
export const fixedPerDay = (r: Roi) => (Number(r.month_base) + Number(r.month_costs)) / DAYS_PER_MONTH;

/**
 * Cups a day needed to cover HPP, staff and monthly costs and still make `extraPerDay` net profit.
 * Each cup above the commission threshold pays commission to every staff member on duty.
 * Null when the margin per cup can't cover it.
 */
export function cupsNeeded(r: Roi, extraPerDay = 0): number | null {
	const m = marginPerCup(r);
	if (m == null || m <= 0) return null;
	const target = fixedPerDay(r) + extraPerDay;
	const t = Number(r.rule?.threshold_cups ?? 0);
	const perCupCommission = Number(r.rule?.rate_per_cup ?? 0) * Number(r.staff_per_day);
	if (m * t >= target) return Math.ceil(target / m);
	const slope = m - perCupCommission;
	if (slope <= 0) return null;
	return Math.ceil(t + (target - m * t) / slope);
}

/** Net profit a month needed to pay back the capital within `months` of opening. */
export const neededPerMonth = (r: Roi, months: number) => capitalTotal(r) / months;

/** Average net profit per day over the last 30 days (fixed costs included on every day). */
export const netPerDay = (r: Roi) => (Number(r.recent.days) ? Number(r.recent.net) / Number(r.recent.days) : 0);

/** Average cups per day over the last 30 days, counting only days with sales. */
export const cupsPerDay = (r: Roi) => (Number(r.recent.sales_days) ? Number(r.recent.cups) / Number(r.recent.sales_days) : 0);

export function addMonths(date: string, months: number) {
	const d = new Date(`${date}T00:00:00Z`);
	d.setUTCMonth(d.getUTCMonth() + months);
	return d.toISOString().slice(0, 10);
}
