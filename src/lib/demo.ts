// Sample data for checking screens locally without signing in. Only loaded in `pnpm dev`,
// when the URL has ?demo (remembered for the browser tab). Never part of a production build.
import { addDays, today } from './format';

export const demoEnabled = () => {
	if (!import.meta.env.DEV || typeof window === 'undefined') return false;
	if (new URLSearchParams(location.search).has('demo')) sessionStorage.setItem('demo', '1');
	return sessionStorage.getItem('demo') === '1';
};

const MENU = [
	['cmt', 'Classic Milk Tea', 'Milk Tea', 14000, 12],
	['mcr', 'Crumble Matcha', 'Matcha', 15000, 10],
	['pom', 'Premium Oolong Milk Tea', 'Milk Tea', 16000, 9],
	['pot', 'Peach Oolong Tea', 'Fresh Drink', 12000, 8],
	['mcl', 'Classic Matcha', 'Matcha', 14000, 6],
	['jmt', 'Jasmine Milk Tea', 'Milk Tea', 14000, 5],
	['mgt', 'Mango Tea', 'Fresh Drink', 12000, 2]
] as const;
const PROFILE = [0, 1, 3, 4, 6, 4, 3, 4, 7, 9, 5, 3, 3, 0]; // 08:00 to 21:00
const STAFF = [
	{ code: 'meirisa', name: 'Meirisa' },
	{ code: 'neli', name: 'Neli' },
	{ code: 'ugan', name: 'Ugan' },
	{ code: 'laura', name: 'Laura' }
];

type Order = { date: string; hour: number; cups: number; total: number; cash: boolean; items: { i: number; qty: number }[]; prep: number };

let seed = 7;
const rand = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);

function makeOrders(): Order[] {
	const out: Order[] = [];
	for (let back = 120; back >= 0; back--) {
		const date = addDays(today(), -back);
		const dow = new Date(`${date}T00:00:00Z`).getUTCDay();
		const target = Math.round((dow === 0 || dow === 6 ? 95 : 48) * (0.8 + rand() * 0.4));
		let cups = 0;
		while (cups < target) {
			const weights = PROFILE.flatMap((w, h) => Array(w).fill(h + 8));
			const hour = weights[Math.floor(rand() * weights.length)];
			const qty = rand() < 0.7 ? 1 : 2;
			const pick = MENU.flatMap((m, i) => Array(m[4]).fill(i))[Math.floor(rand() * 52)];
			cups += qty;
			out.push({ date, hour, cups: qty, total: MENU[pick][3] * qty, cash: rand() < 0.6, items: [{ i: pick, qty }], prep: 3 + Math.round(rand() * 8) });
		}
	}
	return out;
}
const ORDERS = makeOrders();

const inRange = (from: string, to: string) => ORDERS.filter((o) => o.date >= from && o.date <= to);
const totals = (orders: Order[]) => {
	const sales = orders.reduce((a, o) => a + o.total, 0);
	return { sales, orders: orders.length, cups: orders.reduce((a, o) => a + o.cups, 0), avg_order: orders.length ? Math.round(sales / orders.length) : 0 };
};
const group = <T>(items: T[], key: (t: T) => string | number) => {
	const map = new Map<string | number, T[]>();
	for (const t of items) map.set(key(t), [...(map.get(key(t)) ?? []), t]);
	return map;
};
const dayCups = (date: string) => inRange(date, date).reduce((a, o) => a + o.cups, 0);
const isoDow = (date: string) => ((new Date(`${date}T00:00:00Z`).getUTCDay() + 6) % 7) + 1;
const at = (date: string, h: number, m = 0) => `${date}T${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:00+07:00`;

/** Who worked which day: two people a day, rotating, nobody on their weekly day off. */
const working = (date: string) => {
	const n = Math.round(Date.parse(date) / 86400000);
	return STAFF.filter((_, i) => (n + i) % 4 !== 0 && (n + i) % 4 !== 1 ? true : false).slice(0, 2);
};

function products(from: string, to: string) {
	const lines = inRange(from, to).flatMap((o) => o.items);
	return [...group(lines, (l) => l.i)].map(([i, ls]) => {
		const m = MENU[i as number];
		const cups = ls.reduce((a, l) => a + l.qty, 0);
		return { code: m[0], name: m[1], category: m[2], cups, sales: cups * m[3] };
	});
}

function payroll(month: string) {
	const first = `${month.slice(0, 7)}-01`;
	const days: string[] = [];
	for (let d = first; d.slice(0, 7) === first.slice(0, 7) && d <= today(); d = addDays(d, 1)) days.push(d);
	const commissionOn = (d: string) => Math.max(0, dayCups(d) - 20) * 1000;
	return {
		month: first,
		status: 'draft',
		locked_at: null,
		can_lock: first < `${today().slice(0, 7)}-01`,
		rule: { threshold_cups: 20, rate_per_cup: 1000 },
		outlet_days: days.map((d) => ({ date: d, cups: dayCups(d), commission: commissionOn(d) })),
		lines: STAFF.map((s) => {
			const mine = days.filter((d) => working(d).some((w) => w.code === s.code));
			const commission = mine.reduce((a, d) => a + commissionOn(d), 0);
			return {
				staff_code: s.code, staff_name: s.name, days_worked: mine.length, base_salary: 1500000, commission, correction: 0,
				total: 1500000 + commission, days: mine.map((d) => ({ date: d, cups: dayCups(d), commission: commissionOn(d) }))
			};
		})
	};
}

function attendance(month: string) {
	const first = `${month.slice(0, 7)}-01`;
	const rows = [];
	for (let d = first; d.slice(0, 7) === first.slice(0, 7) && d <= today(); d = addDays(d, 1)) {
		for (const [k, s] of working(d).entries()) {
			const open = d === today() && k === 1;
			rows.push({
				id: `${d}-${s.code}`, staff_code: s.code, staff_name: s.name, date: d,
				clock_in_at: at(d, k ? 14 : 7, 50 + k), clock_out_at: open ? null : at(d, k ? 21 : 15, 4), source: 'tablet', edited: false
			});
		}
	}
	const yesterday = addDays(today(), -1);
	const missing = rows.filter((r) => r.date === yesterday).slice(0, 1).map((r) => ({ ...r, clock_out_at: null }));
	return { month: first, today: today(), staff: STAFF, rows: rows.map((r) => missing.some((m) => m.id === r.id) ? { ...r, clock_out_at: null } : r), missing_clock_out: missing };
}

export function demoRpc(fn: string, a: Record<string, any> = {}): unknown {
	switch (fn) {
		case 'my_access':
			return { email: 'demo@example.com', role: 'owner', must_change_password: false };
		case 'report_outlets':
			return [{ code: 'MAIN', name: 'Chacha' }];
		case 'report_daily': {
			const day = inRange(a.p_date, a.p_date);
			const items = day.flatMap((o) => o.items);
			return {
				totals: totals(day),
				compare: totals(inRange(addDays(a.p_date, -7), addDays(a.p_date, -7))),
				prep_median_min: day.length ? 6 : null,
				hours: [...group(day, (o) => o.hour)].map(([hour, os]) => ({ hour, orders: os.length, cups: totals(os).cups, sales: totals(os).sales })),
				top: products(a.p_date, a.p_date).sort((x, y) => y.cups - x.cups).slice(0, 5),
				payments: { cash: totals(day.filter((o) => o.cash)).sales, qris: totals(day.filter((o) => !o.cash)).sales },
				cashiers: working(a.p_date).map((s, i) => ({ name: s.name, cups: Math.round(totals(day).cups * (i ? 0.4 : 0.6)), sales: Math.round(totals(day).sales * (i ? 0.4 : 0.6)) })),
				sugar: { normal: Math.round(items.length * 0.6), less: Math.round(items.length * 0.3), zero: Math.round(items.length * 0.1) },
				ice: { normal: Math.round(items.length * 0.73), less: Math.round(items.length * 0.27) },
				cancelled: { orders: 2, amount: 30000, top_reason: 'Customer changed mind' },
				freshness: { last_received_at: new Date(Date.now() - 120000).toISOString(), device_seen_at: new Date(Date.now() - 60000).toISOString() }
			};
		}
		case 'report_sales': {
			const len = Math.round((Date.parse(a.p_to) - Date.parse(a.p_from)) / 86400000) + 1;
			const range = inRange(a.p_from, a.p_to);
			const days = [...group(range, (o) => o.date)].map(([date, os]) => ({
				date, ...totals(os), cash: totals(os.filter((o) => o.cash)).sales, qris: totals(os.filter((o) => !o.cash)).sales
			}));
			return {
				totals: totals(range),
				previous: totals(inRange(addDays(a.p_from, -len), addDays(a.p_from, -1))),
				days,
				weekdays: [...group(days, (d) => isoDow(d.date as string))].map(([dow, ds]) => ({
					dow, avg_sales: Math.round(ds.reduce((x, d) => x + d.sales, 0) / ds.length), avg_cups: Math.round(ds.reduce((x, d) => x + d.cups, 0) / ds.length)
				})).sort((x, y) => (x.dow as number) - (y.dow as number))
			};
		}
		case 'report_products':
			return products(a.p_from, a.p_to);
		case 'report_time': {
			const range = inRange(a.p_from, a.p_to);
			const openDays = (dow: number) => new Set(range.filter((o) => isoDow(o.date) === dow).map((o) => o.date)).size;
			const grid = [...group(range, (o) => `${isoDow(o.date)}-${o.hour}`)].map(([k, os]) => {
				const [dow, hour] = String(k).split('-').map(Number);
				const cups = totals(os).cups;
				return { dow, hour, cups, avg_cups: Math.round((cups / openDays(dow)) * 10) / 10 };
			});
			const weekday = [1, 2, 3, 4, 5, 6, 7].map((dow) => ({ dow, avg_cups: Math.round((totals(range.filter((o) => isoDow(o.date) === dow)).cups / Math.max(1, openDays(dow))) * 10) / 10 })).sort((x, y) => y.avg_cups - x.avg_cups);
			return {
				grid, weekday_cups: weekday, peak_hour: 17,
				prep: { median: 6, peak_median: 9, over_10_pct: 8 },
				dayparts: [{ part: 1, name: 'Classic Milk Tea', cups: 40 }, { part: 2, name: 'Peach Oolong Tea', cups: 52 }, { part: 3, name: 'Crumble Matcha', cups: 61 }, { part: 4, name: 'Classic Milk Tea', cups: 44 }]
			};
		}
		case 'list_dashboard_users':
			return [
				{ user_id: '1', email: 'demo@example.com', role: 'owner', invited: false, last_sign_in_at: new Date().toISOString(), is_me: true },
				{ user_id: '2', email: 'viewer@example.com', role: 'viewer', invited: true, last_sign_in_at: null, is_me: false }
			];
		case 'attendance_month':
			return attendance(a.p_month);
		case 'payroll_month':
			return payroll(a.p_month);
		default:
			return null;
	}
}
