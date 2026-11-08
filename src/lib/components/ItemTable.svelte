<script lang="ts">
	import { rupiah, share } from '$lib/format';
	import type { Item } from '$lib/items';
	import { costedCups, EMPTY, foodCostOf, HIGH_FOOD_COST, marginOf, pct, type MarginReport } from '$lib/margin';

	let {
		items,
		margin = null,
		title,
		subtitle = '',
		foodCost = true
	}: { items: Item[]; margin?: MarginReport | null; title: string; subtitle?: string; foodCost?: boolean } = $props();

	type Sort = 'cups' | 'sales' | 'margin';
	let sortBy = $state<Sort>('cups');

	const byCode = $derived(new Map((margin?.products ?? []).map((p) => [p.code, p])));
	const totalCups = $derived(items.reduce((a, r) => a + Number(r.cups), 0));

	const rows = $derived(
		items
			.map((r) => {
				const m = byCode.get(r.code) ?? EMPTY;
				const n = costedCups(m);
				return {
					...r,
					hasCost: margin != null && n > 0,
					hpp: n ? Number(m.cost) / n : 0,
					perCup: n ? marginOf(m) / n : 0,
					margin: marginOf(m),
					foodCost: foodCostOf(m),
					uncosted: Number(m.uncosted_cups)
				};
			})
			.sort((a, b) => Number(b[sortBy]) - Number(a[sortBy]) || Number(b.cups) - Number(a.cups))
	);
	const topCups = $derived(Math.max(1, ...items.map((r) => Number(r.cups))));
	const sorts = $derived<[Sort, string][]>([
		['cups', 'Most cups'],
		['sales', 'Most sales'],
		...(margin ? [['margin', 'Most margin'] as [Sort, string]] : [])
	]);
</script>

<div class="flex flex-wrap items-center justify-between gap-3">
	<div>
		<h2 class="card-title m-0">{title}</h2>
		{#if subtitle}<div class="num text-muted">{subtitle}</div>{/if}
	</div>
	<div role="group" aria-label="Sort by" class="flex flex-wrap gap-1">
		{#each sorts as [key, label]}
			<button class="btn {sortBy === key ? 'btn-primary' : ''}" aria-pressed={sortBy === key} onclick={() => (sortBy = key)}>{label}</button>
		{/each}
	</div>
</div>
<div class="mt-3 overflow-x-auto">
	<table class="num w-full border-collapse text-right {margin ? 'min-w-[1000px]' : 'min-w-[640px]'}">
		<thead>
			<tr>
				<th scope="col" class="th w-8 text-left">#</th>
				<th scope="col" class="th text-left">Drink</th>
				<th scope="col" class="th text-left">Category</th>
				<th scope="col" class="th">Cups</th>
				<th scope="col" class="th w-44 text-left">Share of cups</th>
				<th scope="col" class="th">Sales</th>
				{#if margin}
					<th scope="col" class="th">HPP / cup</th>
					<th scope="col" class="th">Margin / cup</th>
					<th scope="col" class="th">Margin</th>
					{#if foodCost}<th scope="col" class="th">Food cost</th>{/if}
				{/if}
			</tr>
		</thead>
		<tbody>
			{#each rows as r, i (r.code)}
				<tr>
					<td class="td text-left text-muted">{i + 1}</td>
					<td class="td text-left font-semibold">{r.name}</td>
					<td class="td text-left text-muted">{r.category}</td>
					<td class="td">{r.cups}</td>
					<td class="td">
						<div class="flex items-center gap-2">
							<div class="h-2 flex-auto rounded bg-mist-soft"><div class="h-2 rounded bg-forest" style:width="{(Number(r.cups) / topCups) * 100}%"></div></div>
							<span class="w-9">{share(Number(r.cups), totalCups)}%</span>
						</div>
					</td>
					<td class="td">{rupiah(r.sales)}</td>
					{#if margin}
						{#if r.hasCost}
							<td class="td">{rupiah(Math.round(r.hpp))}</td>
							<td class="td">{rupiah(Math.round(r.perCup))}</td>
							<td class="td font-semibold">{rupiah(r.margin)}</td>
							{#if foodCost}
								<td class="td {r.foodCost != null && r.foodCost > HIGH_FOOD_COST ? 'font-semibold text-danger' : ''}">
									{pct(r.foodCost)}{#if r.foodCost != null && r.foodCost > HIGH_FOOD_COST}&nbsp;High{/if}
								</td>
							{/if}
						{:else}
							<td class="td text-danger" colspan={foodCost ? 4 : 3}>No HPP set</td>
						{/if}
					{/if}
				</tr>
			{/each}
		</tbody>
	</table>
</div>
{#if margin}
	<p class="m-0 mt-3 text-[13px] text-muted">
		Margin = price charged − HPP (ingredients + packaging), before staff, rent and utilities.{#if foodCost}
		Food cost above {HIGH_FOOD_COST}% is marked High.{/if} If HPP changed during the period, HPP per cup is the average.
	</p>
{/if}
