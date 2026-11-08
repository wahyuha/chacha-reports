<script lang="ts">
	import { rupiah, share } from '$lib/format';
	import { groupByCategory, type Item } from '$lib/items';
	import { foodCostOf, HIGH_FOOD_COST, marginOf, marginPct, pct, type MarginReport, type MarginRow } from '$lib/margin';

	let { items, margin = null, foodCost = true }: { items: Item[]; margin?: MarginReport | null; foodCost?: boolean } = $props();

	const groups = $derived(groupByCategory(items, margin));
	const cups = $derived(items.reduce((a, r) => a + Number(r.cups), 0));
	const sales = $derived(items.reduce((a, r) => a + Number(r.sales), 0));
</script>

{#snippet marginLine(m: MarginRow)}
	{@const fc = foodCostOf(m)}
	<div class="mt-2 border-t border-stone pt-2">
		{#if Number(m.costed_sales)}
			<div class="num font-semibold">Margin {rupiah(marginOf(m))} · {pct(marginPct(m))}</div>
			{#if foodCost}
				<div class="num text-[13px] {fc != null && fc > HIGH_FOOD_COST ? 'font-semibold text-danger' : 'text-muted'}">
					Food cost {pct(fc)}{#if fc != null && fc > HIGH_FOOD_COST}, High{/if}
				</div>
			{/if}
		{:else}
			<div class="text-muted">No HPP set</div>
		{/if}
		{#if Number(m.uncosted_cups) && Number(m.costed_sales)}
			<div class="text-[13px] text-danger">{m.uncosted_cups} cups without HPP</div>
		{/if}
	</div>
{/snippet}

<div class="grid grid-cols-2 gap-4 xl:grid-cols-[repeat(auto-fit,minmax(170px,1fr))]">
	<div class="rounded-xl border-2 border-forest bg-raised p-4">
		<div class="eyebrow">Total</div>
		<div class="num mt-2 text-[26px] leading-[34px] font-bold">{cups} cups</div>
		<div class="num text-muted">{rupiah(sales)} · {items.length} drinks</div>
		{#if margin}{@render marginLine(margin.totals)}{/if}
	</div>
	{#each groups as g}
		<div class="rounded-xl border border-stone bg-raised p-4">
			<div class="eyebrow">{g.name}</div>
			<div class="num mt-2 text-[26px] leading-[34px] font-bold">{g.cups} cups</div>
			<div class="num text-muted">{rupiah(g.sales)} · {share(g.cups, cups)}% of cups</div>
			{#if g.margin}{@render marginLine(g.margin)}{/if}
		</div>
	{/each}
</div>
