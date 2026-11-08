<script lang="ts">
	import { longDate } from '$lib/format';
	import { outlets } from '$lib/outlet.svelte';
	import { rpc } from '$lib/supabase';
	import Status from './Status.svelte';

	type Drink = { code: string; name: string; category: string; cups: number; less_sugar: number; zero_sugar: number; less_ice: number };

	let { from, to, category = 'All', open = $bindable(false) }: { from: string; to: string; category?: string; open?: boolean } = $props();

	let rows = $state<Drink[] | null>(null);
	let loading = $state(false);
	let error = $state('');

	// Loads only while open, so the section costs nothing when it stays closed.
	$effect(() => {
		if (!open) return;
		const args = { p_outlet: outlets.code, p_from: from, p_to: to };
		loading = true;
		error = '';
		rpc<Drink[]>('report_custom', args)
			.then((r) => {
				if (args.p_from !== from || args.p_to !== to) return;
				rows = r;
				// Arriving from Daily's link: the anchor exists only now, so scroll to it once.
				if (location.hash === '#custom-title') {
					setTimeout(() => document.getElementById('custom-title')?.scrollIntoView({ block: 'start' }), 0);
					history.replaceState(history.state, '', location.pathname + location.search);
				}
			})
			.catch((e) => (error = e.message))
			.finally(() => (loading = false));
	});

	const shown = $derived((rows ?? []).filter((r) => category === 'All' || r.category === category));
	const sum = (key: 'less_sugar' | 'zero_sugar' | 'less_ice') => shown.reduce((a, r) => a + Number(r[key]), 0);
	const period = $derived(from === to ? longDate(from) : `${longDate(from)} to ${longDate(to)}`);
	const count = (n: number) => (Number(n) ? String(n) : '–');
</script>

<section class="card" aria-labelledby="custom-title">
	<div class="flex flex-wrap items-center justify-between gap-3">
		<h2 id="custom-title" class="card-title m-0">Custom sugar and ice</h2>
		<button class="btn" aria-expanded={open} aria-controls="custom-body" onclick={() => (open = !open)}>{open ? 'Hide' : 'Show'}</button>
	</div>
	{#if !open}
		<p class="m-0 mt-1 text-muted">Drinks ordered with less sugar, zero sugar or less ice.</p>
	{:else}
		<div id="custom-body">
			{#if error || (loading && !rows)}
				<div class="mt-3"><Status {loading} {error} /></div>
			{:else if rows}
				{#if !shown.length}
					<p class="m-0 mt-2 text-muted">No less sugar, zero sugar or less ice on {period}.</p>
				{:else}
					<div class="num mt-1 text-muted">
						{period} · Less sugar {sum('less_sugar')} · Zero sugar {sum('zero_sugar')} · Less ice {sum('less_ice')}
					</div>
					<div class="mt-3 overflow-x-auto">
						<table class="num w-full min-w-[560px] border-collapse text-right">
							<thead>
								<tr>
									<th scope="col" class="th text-left">Drink</th>
									<th scope="col" class="th">Less sugar</th>
									<th scope="col" class="th">Zero sugar</th>
									<th scope="col" class="th">Less ice</th>
									<th scope="col" class="th"><span class="sr-only">Cups sold</span></th>
								</tr>
							</thead>
							<tbody>
								{#each shown as r (r.code)}
									<tr>
										<td class="td text-left font-semibold">{r.name}</td>
										<td class="td">{count(r.less_sugar)}</td>
										<td class="td">{count(r.zero_sugar)}</td>
										<td class="td">{count(r.less_ice)}</td>
										<td class="td text-[13px] text-muted">of {r.cups} {Number(r.cups) === 1 ? 'cup' : 'cups'}</td>
									</tr>
								{/each}
							</tbody>
						</table>
					</div>
					<p class="m-0 mt-3 text-[13px] text-muted">Counts are cups. Drinks always ordered with normal sugar and ice aren't listed.</p>
				{/if}
			{/if}
		</div>
	{/if}
</section>
