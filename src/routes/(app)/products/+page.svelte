<script lang="ts">
	import { auth } from '$lib/auth.svelte';
	import ItemCards from '$lib/components/ItemCards.svelte';
	import ItemTable from '$lib/components/ItemTable.svelte';
	import RangePicker from '$lib/components/RangePicker.svelte';
	import Status from '$lib/components/Status.svelte';
	import { longDate, rupiah, today } from '$lib/format';
	import type { Item } from '$lib/items';
	import { loadMargin, type MarginReport } from '$lib/margin';
	import { outlets } from '$lib/outlet.svelte';
	import { rpc } from '$lib/supabase';

	let to = $state(today());
	let from = $state(today());
	let rows = $state<Item[] | null>(null);
	let margin = $state<MarginReport | null>(null);
	let loading = $state(true);
	let error = $state('');
	let category = $state('All');

	$effect(() => {
		const args = { p_outlet: outlets.code, p_from: from, p_to: to };
		const owner = auth.isOwner;
		loading = true;
		error = '';
		Promise.all([rpc<Item[]>('report_products', args), owner ? loadMargin(args.p_outlet, args.p_from, args.p_to) : null])
			.then(([r, m]) => {
				if (args.p_from !== from || args.p_to !== to) return;
				rows = r;
				margin = m;
			})
			.catch((e) => (error = e.message))
			.finally(() => (loading = false));
	});

	const categories = $derived([...new Set((rows ?? []).map((r) => r.category))].sort());
	const shown = $derived((rows ?? []).filter((r) => category === 'All' || r.category === category));
	const shownCups = $derived(shown.reduce((a, r) => a + Number(r.cups), 0));
	const shownSales = $derived(shown.reduce((a, r) => a + Number(r.sales), 0));
</script>

<svelte:head><title>Best sellers · Chacha Reports</title></svelte:head>

<header class="flex flex-wrap items-end justify-between gap-4">
	<h1 class="page-title m-0">Best sellers</h1>
	<div class="flex flex-wrap items-center gap-2">
		<RangePicker bind:from bind:to singleDays />
		<label class="flex items-center gap-2 text-muted">
			Category
			<select class="input" bind:value={category}>
				<option>All</option>
				{#each categories as c}<option>{c}</option>{/each}
			</select>
		</label>
	</div>
</header>

{#if error || (loading && !rows)}
	<Status {loading} {error} />
{:else if rows && !rows.length}
	<Status empty={from === to ? `No sales recorded on ${longDate(from)}.` : `No sales recorded from ${longDate(from)} to ${longDate(to)}.`} />
{:else if rows}
	<section aria-label="Category totals">
		<ItemCards items={rows} {margin} />
	</section>

	<section class="card">
		<ItemTable items={shown} {margin} title={category === 'All' ? 'All drinks' : category} subtitle="{shownCups} cups · {rupiah(shownSales)}" />
	</section>
{/if}
