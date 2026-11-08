<script lang="ts">
	import { goto } from '$app/navigation';
	import { auth } from '$lib/auth.svelte';
	import Status from '$lib/components/Status.svelte';
	import { dateTime, dayMonthYear, longDate, rupiah, today } from '$lib/format';
	import { foodCost, HIGH_FOOD_COST, pct } from '$lib/margin';
	import { outlets } from '$lib/outlet.svelte';
	import { rpc } from '$lib/supabase';

	type Cost = { from: string; ingredients: number; packaging: number; updated_at?: string };
	type Drink = { code: string; name: string; category: string; price: number; active: boolean; current: Cost | null; history: Cost[] };

	let drinks = $state<Drink[] | null>(null);
	let loading = $state(true);
	let error = $state('');
	let open = $state<string | null>(null);
	let form = $state({ ingredients: '', packaging: '', from: today() });
	let removing = $state<string | null>(null);
	let busy = $state(false);
	let actionError = $state('');

	$effect(() => {
		if (!auth.isOwner) goto('/');
	});

	async function load() {
		loading = true;
		try {
			drinks = await rpc<Drink[]>('menu_costs_list', { p_outlet: outlets.code });
			error = '';
		} catch (e) {
			error = (e as Error).message;
		} finally {
			loading = false;
		}
	}

	$effect(() => {
		void outlets.code;
		open = null;
		load();
	});

	const hpp = (c: Cost | null) => (c ? Number(c.ingredients) + Number(c.packaging) : null);
	const amount = (s: string) => Number(s.replace(/\D/g, ''));
	const preview = $derived(amount(form.ingredients) + amount(form.packaging));
	const missing = $derived((drinks ?? []).filter((d) => d.active && !d.current).length);
	const high = $derived((drinks ?? []).filter((d) => d.current && (foodCost(hpp(d.current)!, Number(d.price)) ?? 0) > HIGH_FOOD_COST).length);

	function toggle(d: Drink) {
		if (open === d.code) {
			open = null;
			return;
		}
		open = d.code;
		removing = null;
		actionError = '';
		form = {
			ingredients: d.current ? String(d.current.ingredients) : '',
			packaging: d.current ? String(d.current.packaging) : '',
			from: today()
		};
	}

	async function act(fn: () => Promise<unknown>) {
		busy = true;
		actionError = '';
		try {
			await fn();
			await load();
		} catch (e) {
			actionError = (e as Error).message;
		} finally {
			busy = false;
		}
	}

	function save(e: SubmitEvent, d: Drink) {
		e.preventDefault();
		act(async () => {
			await rpc('menu_cost_save', {
				p_outlet: outlets.code,
				p_code: d.code,
				p_from: form.from,
				p_ingredients: amount(form.ingredients),
				p_packaging: amount(form.packaging)
			});
			open = null;
		});
	}

	function remove(d: Drink, from: string) {
		act(async () => {
			await rpc('menu_cost_delete', { p_outlet: outlets.code, p_code: d.code, p_from: from });
			removing = null;
		});
	}
</script>

<svelte:head><title>Menu costs · Chacha Reports</title></svelte:head>

<header class="flex flex-wrap items-end justify-between gap-4">
	<div>
		<div class="eyebrow">Owner only</div>
		<h1 class="page-title m-0 mt-1">Menu costs (HPP)</h1>
	</div>
	{#if outlets.list.length > 1}
		<label class="flex items-center gap-2 text-muted">
			Outlet
			<select class="input" bind:value={outlets.code}>
				{#each outlets.list as o}<option value={o.code}>{o.name}</option>{/each}
			</select>
		</label>
	{/if}
</header>

<section class="flex flex-wrap items-center justify-between gap-x-8 gap-y-3 rounded-xl bg-mist-soft px-5 py-4">
	<div>
		<div class="eyebrow">HPP per cup</div>
		<div class="mt-1 text-xl leading-7 font-semibold">Ingredients + packaging</div>
	</div>
	<div class="min-w-0 flex-[1_1_320px]">
		Staff, rent and utilities aren't included. A change applies from the date you choose, and earlier days keep the HPP they
		were sold at. Food cost above {HIGH_FOOD_COST}% of the price is marked High.
	</div>
</section>

{#if actionError}<p class="card m-0 text-danger" role="alert">{actionError}</p>{/if}

{#if error || (loading && !drinks)}
	<Status {loading} {error} />
{:else if drinks}
	<section class="card">
		<div class="flex flex-wrap items-baseline justify-between gap-2">
			<h2 class="card-title m-0">{drinks.length} drinks</h2>
			<div class="text-muted">
				{#if missing}<strong class="text-danger">{missing} without HPP.</strong>{/if}
				{high} with high food cost.
			</div>
		</div>
		<div class="mt-3 overflow-x-auto">
			<table class="num w-full min-w-[880px] border-collapse text-right">
				<thead>
					<tr>
						<th scope="col" class="th pl-0 text-left">Drink</th>
						<th scope="col" class="th">Price</th>
						<th scope="col" class="th">Ingredients</th>
						<th scope="col" class="th">Packaging</th>
						<th scope="col" class="th">HPP / cup</th>
						<th scope="col" class="th">Food cost</th>
						<th scope="col" class="th">Margin / cup</th>
						<th scope="col" class="th pr-0">Since</th>
					</tr>
				</thead>
				<tbody>
					{#each drinks as d (d.code)}
						{@const cost = hpp(d.current)}
						{@const fc = cost == null ? null : foodCost(cost, Number(d.price))}
						<tr class={open === d.code ? 'bg-mist-soft' : ''}>
							<th scope="row" class="td pl-0 text-left font-normal">
								<button class="min-h-11 text-left font-semibold text-forest underline" aria-expanded={open === d.code} onclick={() => toggle(d)}>
									{d.name}
								</button>
								<div class="text-[13px] text-muted">{d.category}{d.active ? '' : ' · off the menu'}</div>
							</th>
							<td class="td">{rupiah(d.price)}</td>
							{#if d.current && cost != null}
								<td class="td">{rupiah(d.current.ingredients)}</td>
								<td class="td">{rupiah(d.current.packaging)}</td>
								<td class="td font-bold">{rupiah(cost)}</td>
								<td class="td {fc != null && fc > HIGH_FOOD_COST ? 'font-semibold text-danger' : ''}">
									{pct(fc)}{#if fc != null && fc > HIGH_FOOD_COST}&nbsp;High{/if}
								</td>
								<td class="td font-semibold">{rupiah(Number(d.price) - cost)}</td>
								<td class="td pr-0 whitespace-nowrap text-muted">{dayMonthYear(d.current.from)}</td>
							{:else}
								<td class="td text-left text-danger" colspan="6">
									No HPP yet. <button class="min-h-11 px-1 text-forest underline" onclick={() => toggle(d)}>Set HPP</button>
								</td>
							{/if}
						</tr>
						{#if open === d.code}
							<tr>
								<td colspan="8" class="border-t border-stone bg-ivory px-3 py-4 text-left">
									<form class="flex flex-wrap items-end gap-3" onsubmit={(e) => save(e, d)}>
										<label class="flex flex-col gap-1 text-muted">
											Ingredients
											<input class="input w-32 text-right" inputmode="numeric" bind:value={form.ingredients} required />
										</label>
										<label class="flex flex-col gap-1 text-muted">
											Packaging
											<input class="input w-32 text-right" inputmode="numeric" bind:value={form.packaging} required />
										</label>
										<label class="flex flex-col gap-1 text-muted">
											Applies from
											<input class="input" type="date" bind:value={form.from} required />
										</label>
										<div class="min-h-11 py-2">
											HPP {rupiah(preview)} · food cost {pct(foodCost(preview, Number(d.price)))} · margin {rupiah(Number(d.price) - preview)} a cup
										</div>
										<button class="btn btn-primary" disabled={busy}>Save</button>
										<button type="button" class="btn" onclick={() => (open = null)}>Cancel</button>
									</form>
									<p class="m-0 mt-2 text-[13px] text-muted">
										Saving on a date that already has an HPP replaces it. Days from {longDate(form.from || today())} onward use the new HPP.
									</p>
									{#if d.history.length}
										<h3 class="m-0 mt-4 text-base font-semibold">History</h3>
										<table class="num mt-1 w-full max-w-2xl border-collapse text-right">
											<thead>
												<tr>
													<th scope="col" class="th pl-0 text-left">From</th>
													<th scope="col" class="th">Ingredients</th>
													<th scope="col" class="th">Packaging</th>
													<th scope="col" class="th">HPP</th>
													<th scope="col" class="th">Changed</th>
													<th scope="col" class="th pr-0"><span class="sr-only">Actions</span></th>
												</tr>
											</thead>
											<tbody>
												{#each d.history as h (h.from)}
													<tr>
														<td class="td pl-0 text-left">{longDate(h.from)}</td>
														<td class="td">{rupiah(h.ingredients)}</td>
														<td class="td">{rupiah(h.packaging)}</td>
														<td class="td font-semibold">{rupiah(hpp(h))}</td>
														<td class="td text-muted">{h.updated_at ? dateTime(h.updated_at) : ''}</td>
														<td class="td pr-0">
															{#if removing === h.from}
																<button class="btn" disabled={busy} onclick={() => remove(d, h.from)}>Remove</button>
																<button class="btn" onclick={() => (removing = null)}>Keep</button>
															{:else}
																<button class="min-h-11 px-1 text-forest underline" onclick={() => (removing = h.from)}>Remove</button>
															{/if}
														</td>
													</tr>
												{/each}
											</tbody>
										</table>
										<p class="m-0 mt-2 text-[13px] text-muted">Removing a row makes those days use the HPP before it, or none.</p>
									{/if}
								</td>
							</tr>
						{/if}
					{/each}
				</tbody>
			</table>
		</div>
	</section>
{/if}
