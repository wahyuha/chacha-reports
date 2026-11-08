// Drinks sold in a period, with their margin when the viewer is an owner.
import { EMPTY, type MarginReport, type MarginRow } from './margin';

export type Item = { code: string; name: string; category: string; cups: number; sales: number };

export const sumMargin = (rows: MarginRow[]): MarginRow =>
	rows.reduce(
		(a, r) => ({
			cups: a.cups + Number(r.cups),
			sales: a.sales + Number(r.sales),
			cost: a.cost + Number(r.cost),
			costed_sales: a.costed_sales + Number(r.costed_sales),
			uncosted_cups: a.uncosted_cups + Number(r.uncosted_cups)
		}),
		{ ...EMPTY }
	);

export type Group = { name: string; cups: number; sales: number; margin: MarginRow | null };

/** Category totals, most cups first, each with its margin when a margin report is given. */
export function groupByCategory(items: Item[], margin: MarginReport | null): Group[] {
	const byCode = new Map((margin?.products ?? []).map((p) => [p.code, p]));
	const map = new Map<string, Item[]>();
	for (const r of items) map.set(r.category, [...(map.get(r.category) ?? []), r]);
	return [...map.entries()]
		.map(([name, list]) => ({
			name,
			cups: list.reduce((a, r) => a + Number(r.cups), 0),
			sales: list.reduce((a, r) => a + Number(r.sales), 0),
			margin: margin ? sumMargin(list.map((r) => byCode.get(r.code) ?? EMPTY)) : null
		}))
		.sort((a, b) => b.cups - a.cups);
}
