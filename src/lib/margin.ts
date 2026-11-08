// Gross margin = sales of drinks with an HPP, minus cups × HPP per cup. Owners only.
import { rpc } from './supabase';

export type MarginRow = { cups: number; sales: number; cost: number; costed_sales: number; uncosted_cups: number };
export type MarginReport = {
	totals: MarginRow;
	products: (MarginRow & { code: string })[];
	days: (MarginRow & { date: string })[];
};

/** Food cost above this share of the price is marked High, as in the HPP sheet. */
export const HIGH_FOOD_COST = 45;

export const EMPTY: MarginRow = { cups: 0, sales: 0, cost: 0, costed_sales: 0, uncosted_cups: 0 };

export const marginOf = (r: MarginRow) => Number(r.costed_sales) - Number(r.cost);
export const costedCups = (r: MarginRow) => Number(r.cups) - Number(r.uncosted_cups);

/** Margin as a share of the sales it covers, rounded; null when nothing has an HPP. */
export const marginPct = (r: MarginRow) => (Number(r.costed_sales) ? Math.round((marginOf(r) / Number(r.costed_sales)) * 100) : null);

/** Food cost (HPP ÷ price) with one decimal, as the sheet shows it. */
export const foodCost = (cost: number, price: number) => (price ? Math.round((cost / price) * 1000) / 10 : null);
export const foodCostOf = (r: MarginRow) => foodCost(Number(r.cost), Number(r.costed_sales));

export const pct = (n: number | null) => (n == null ? '–' : `${String(n).replace('.', ',')}%`);

export function loadMargin(outlet: string, from: string, to: string) {
	return rpc<MarginReport>('report_margin', { p_outlet: outlet, p_from: from, p_to: to });
}

export function byCode(report: MarginReport | null) {
	return new Map((report?.products ?? []).map((p) => [p.code, p]));
}
