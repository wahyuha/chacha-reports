<script lang="ts">
	import { goto } from '$app/navigation';
	import { auth } from '$lib/auth.svelte';
	import Status from '$lib/components/Status.svelte';
	import { dateTime, monthName, rupiah, today } from '$lib/format';
	import { outlets } from '$lib/outlet.svelte';
	import { rpc } from '$lib/supabase';

	type Entry = { from: string; amount: number; name?: string; updated_at?: string };
	type Cost = { code: string; name: string; current: Entry | null; history: Entry[] };

	const thisMonth = today().slice(0, 7);
	let costs = $state<Cost[] | null>(null);
	let loading = $state(true);
	let error = $state('');
	let open = $state<string | null>(null); // a cost code, or 'new'
	let form = $state({ name: '', amount: '', from: thisMonth });
	let removing = $state<string | null>(null);
	let busy = $state(false);
	let actionError = $state('');

	$effect(() => {
		if (!auth.isOwner) goto('/');
	});

	async function load() {
		loading = true;
		try {
			costs = await rpc<Cost[]>('operating_costs_list', { p_outlet: outlets.code });
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

	const amount = (s: string) => Number(s.replace(/\D/g, ''));
	const total = $derived((costs ?? []).reduce((a, c) => a + Number(c.current?.amount ?? 0), 0));

	function edit(c: Cost | null) {
		removing = null;
		actionError = '';
		if (c && open === c.code) {
			open = null;
			return;
		}
		open = c ? c.code : 'new';
		form = { name: c?.name ?? '', amount: c?.current ? String(c.current.amount) : '', from: thisMonth };
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

	function save(e: SubmitEvent) {
		e.preventDefault();
		const code = open === 'new' ? null : open;
		act(async () => {
			await rpc('operating_cost_save', {
				p_outlet: outlets.code,
				p_code: code,
				p_name: form.name,
				p_from: `${form.from}-01`,
				p_amount: amount(form.amount)
			});
			open = null;
		});
	}
</script>

<svelte:head><title>Monthly costs · Chacha Reports</title></svelte:head>

{#snippet editor()}
	<form class="flex flex-wrap items-end gap-3" onsubmit={save}>
		<label class="flex flex-col gap-1 text-muted">
			Name
			<input class="input w-44" bind:value={form.name} required />
		</label>
		<label class="flex flex-col gap-1 text-muted">
			Amount a month
			<input class="input w-36 text-right" inputmode="numeric" bind:value={form.amount} required />
		</label>
		<label class="flex flex-col gap-1 text-muted">
			Applies from
			<input class="input" type="month" bind:value={form.from} required />
		</label>
		<button class="btn btn-primary" disabled={busy}>Save</button>
		<button type="button" class="btn" onclick={() => (open = null)}>Cancel</button>
	</form>
	<p class="m-0 mt-2 text-[13px] text-muted">
		Earlier months keep their amount. Set Rp 0 when a cost is no longer paid.
	</p>
{/snippet}

<header class="flex flex-wrap items-end justify-between gap-4">
	<div>
		<div class="eyebrow">Owner only</div>
		<h1 class="page-title m-0 mt-1">Monthly costs</h1>
	</div>
	<button class="btn btn-primary" onclick={() => edit(null)}>Add a cost</button>
</header>

<section class="flex flex-wrap items-center justify-between gap-x-8 gap-y-3 rounded-xl bg-mist-soft px-5 py-4">
	<div>
		<div class="eyebrow">Fixed costs</div>
		<div class="mt-1 text-xl leading-7 font-semibold">Paid every month, whatever the sales</div>
	</div>
	<div class="min-w-0 flex-[1_1_320px]">
		Profit and loss spreads each amount evenly over the days of its month, so a month still running counts only the days so far.
		Staff pay comes from <a class="text-forest underline" href="/payroll">Salary and commission</a>.
	</div>
</section>

{#if actionError}<p class="card m-0 text-danger" role="alert">{actionError}</p>{/if}

{#if open === 'new'}
	<section class="card">
		<h2 class="card-title m-0 mb-3">New cost</h2>
		{@render editor()}
	</section>
{/if}

{#if error || (loading && !costs)}
	<Status {loading} {error} />
{:else if costs}
	<section class="card">
		<div class="overflow-x-auto">
			<table class="num w-full min-w-[560px] border-collapse text-right">
				<thead>
					<tr>
						<th scope="col" class="th pl-0 text-left">Cost</th>
						<th scope="col" class="th">Amount a month</th>
						<th scope="col" class="th pr-0">Since</th>
					</tr>
				</thead>
				<tbody>
					{#each costs as c (c.code)}
						<tr class={open === c.code ? 'bg-mist-soft' : ''}>
							<th scope="row" class="td pl-0 text-left">
								<button class="min-h-11 text-left font-semibold text-forest underline" aria-expanded={open === c.code} onclick={() => edit(c)}>
									{c.name}
								</button>
							</th>
							<td class="td {Number(c.current?.amount ?? 0) ? 'font-semibold' : 'text-muted'}">
								{c.current ? rupiah(c.current.amount) : 'Starts later'}
							</td>
							<td class="td pr-0 text-muted">{c.current ? monthName(c.current.from) : ''}</td>
						</tr>
						{#if open === c.code}
							<tr>
								<td colspan="3" class="border-t border-stone bg-ivory px-3 py-4 text-left">
									{@render editor()}
									<h3 class="m-0 mt-4 text-base font-semibold">History</h3>
									<table class="num mt-1 w-full max-w-xl border-collapse text-right">
										<thead>
											<tr>
												<th scope="col" class="th pl-0 text-left">From</th>
												<th scope="col" class="th">Amount</th>
												<th scope="col" class="th">Changed</th>
												<th scope="col" class="th pr-0"><span class="sr-only">Actions</span></th>
											</tr>
										</thead>
										<tbody>
											{#each c.history as h (h.from)}
												<tr>
													<td class="td pl-0 text-left">{monthName(h.from)}</td>
													<td class="td">{rupiah(h.amount)}</td>
													<td class="td text-muted">{h.updated_at ? dateTime(h.updated_at) : ''}</td>
													<td class="td pr-0">
														{#if removing === h.from}
															<button class="btn" disabled={busy} onclick={() => act(async () => { await rpc('operating_cost_delete', { p_outlet: outlets.code, p_code: c.code, p_from: h.from }); removing = null; })}>Remove</button>
															<button class="btn" onclick={() => (removing = null)}>Keep</button>
														{:else}
															<button class="min-h-11 px-1 text-forest underline" onclick={() => (removing = h.from)}>Remove</button>
														{/if}
													</td>
												</tr>
											{/each}
										</tbody>
									</table>
								</td>
							</tr>
						{/if}
					{/each}
					<tr class="border-t-2 border-ink">
						<th scope="row" class="py-2.5 text-left font-bold">Total from {monthName(`${thisMonth}-01`)}</th>
						<td class="px-2 py-2.5 font-bold">{rupiah(total)}</td>
						<td></td>
					</tr>
				</tbody>
			</table>
		</div>
	</section>
{/if}
