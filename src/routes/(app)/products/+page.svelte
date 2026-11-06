<script lang="ts">
	import RangePicker from '$lib/components/RangePicker.svelte';
	import Status from '$lib/components/Status.svelte';
	import { addDays, longDate, rupiah, share, today } from '$lib/format';
	import { outlets } from '$lib/outlet.svelte';
	import { rpc } from '$lib/supabase';

	type Row = { code: string; name: string; category: string; cups: number; sales: number };

	let to = $state(today());
	let from = $state(addDays(today(), -13));
	let rows = $state<Row[] | null>(null);
	let loading = $state(true);
	let error = $state('');
	let category = $state('All');
	let sortBy = $state<'cups' | 'sales'>('cups');

	$effect(() => {
		const args = { p_outlet: outlets.code, p_from: from, p_to: to };
		loading = true;
		error = '';
		rpc<Row[]>('report_products', args)
			.then((r) => (rows = r))
			.catch((e) => (error = e.message))
			.finally(() => (loading = false));
	});

	const totalCups = $derived((rows ?? []).reduce((a, r) => a + Number(r.cups), 0));
	const totalSales = $derived((rows ?? []).reduce((a, r) => a + Number(r.sales), 0));
	const categories = $derived.by(() => {
		const map = new Map<string, { cups: number; sales: number }>();
		for (const r of rows ?? []) {
			const c = map.get(r.category) ?? { cups: 0, sales: 0 };
			c.cups += Number(r.cups);
			c.sales += Number(r.sales);
			map.set(r.category, c);
		}
		return [...map.entries()].map(([name, v]) => ({ name, ...v })).sort((a, b) => b.cups - a.cups);
	});
	const shown = $derived(
		(rows ?? [])
			.filter((r) => category === 'All' || r.category === category)
			.sort((a, b) => Number(b[sortBy]) - Number(a[sortBy]))
	);
	const topValue = $derived(Math.max(1, ...shown.map((r) => Number(r.cups))));
</script>

<svelte:head><title>Best sellers · Chacha Reports</title></svelte:head>

<header class="flex flex-wrap items-end justify-between gap-4">
	<h1 class="page-title m-0">Best sellers</h1>
	<div class="flex flex-wrap items-center gap-2">
		<RangePicker bind:from bind:to />
		<label class="flex items-center gap-2 text-muted">
			Category
			<select class="input" bind:value={category}>
				<option>All</option>
				{#each categories as c}<option>{c.name}</option>{/each}
			</select>
		</label>
	</div>
</header>

{#if error || (loading && !rows)}
	<Status {loading} {error} />
{:else if rows && !rows.length}
	<Status empty={`No sales recorded from ${longDate(from)} to ${longDate(to)}.`} />
{:else if rows}
	<section aria-label="Category totals" class="grid grid-cols-[repeat(auto-fit,minmax(220px,1fr))] gap-4">
		{#each categories as c}
			<div class="rounded-xl border border-stone bg-raised p-4">
				<div class="eyebrow">{c.name}</div>
				<div class="num mt-2 text-[26px] leading-[34px] font-bold">{c.cups} cups</div>
				<div class="num text-muted">{rupiah(c.sales)} · {share(c.cups, totalCups)}% of cups</div>
			</div>
		{/each}
	</section>

	<section class="card">
		<div class="flex flex-wrap items-center justify-between gap-3">
			<div>
				<h2 class="card-title m-0">All drinks</h2>
				<div class="num text-muted">{totalCups} cups · {rupiah(totalSales)}</div>
			</div>
			<div role="group" aria-label="Sort by" class="flex gap-1">
				<button class="btn {sortBy === 'cups' ? 'btn-primary' : ''}" aria-pressed={sortBy === 'cups'} onclick={() => (sortBy = 'cups')}>Most cups</button>
				<button class="btn {sortBy === 'sales' ? 'btn-primary' : ''}" aria-pressed={sortBy === 'sales'} onclick={() => (sortBy = 'sales')}>Most sales</button>
			</div>
		</div>
		<div class="mt-3 overflow-x-auto">
			<table class="num w-full min-w-[720px] border-collapse text-right">
				<thead>
					<tr>
						<th scope="col" class="th w-8 text-left">#</th>
						<th scope="col" class="th text-left">Drink</th>
						<th scope="col" class="th text-left">Category</th>
						<th scope="col" class="th">Cups</th>
						<th scope="col" class="th w-52 text-left">Share of cups</th>
						<th scope="col" class="th">Sales</th>
					</tr>
				</thead>
				<tbody>
					{#each shown as r, i}
						<tr>
							<td class="td text-left text-muted">{i + 1}</td>
							<td class="td text-left font-semibold">{r.name}</td>
							<td class="td text-left text-muted">{r.category}</td>
							<td class="td">{r.cups}</td>
							<td class="td">
								<div class="flex items-center gap-2">
									<div class="h-2 flex-auto rounded bg-mist-soft"><div class="h-2 rounded bg-forest" style:width="{(Number(r.cups) / topValue) * 100}%"></div></div>
									<span class="w-9">{share(Number(r.cups), totalCups)}%</span>
								</div>
							</td>
							<td class="td">{rupiah(r.sales)}</td>
						</tr>
					{/each}
				</tbody>
			</table>
		</div>
	</section>
{/if}
