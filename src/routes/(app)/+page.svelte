<script lang="ts">
	import { auth } from '$lib/auth.svelte';
	import BarChart from '$lib/components/BarChart.svelte';
	import ItemCards from '$lib/components/ItemCards.svelte';
	import ItemTable from '$lib/components/ItemTable.svelte';
	import Kpi from '$lib/components/Kpi.svelte';
	import Status from '$lib/components/Status.svelte';
	import { addDays, change, dateTime, longDate, rupiah, today, weekdayOf } from '$lib/format';
	import type { Item } from '$lib/items';
	import { loadMargin, marginOf, marginPct, pct, type MarginReport } from '$lib/margin';
	import { outlets } from '$lib/outlet.svelte';
	import { rpc } from '$lib/supabase';

	type Totals = { sales: number; orders: number; cups: number; avg_order: number };
	type Hour = { hour: number; orders: number; cups: number; sales: number };
	type Report = {
		totals: Totals;
		compare: Totals;
		prep_median_min: number | null;
		hours: Hour[];
		top: { name: string; cups: number; sales: number }[];
		payments: { cash: number; qris: number };
		cashiers: { name: string; cups: number; sales: number }[];
		sugar: Record<string, number>;
		ice: Record<string, number>;
		cancelled: { orders: number; amount: number; top_reason: string | null };
		freshness: { last_received_at: string | null; device_seen_at: string | null };
	};
	type Metric = 'orders' | 'cups' | 'sales';

	let date = $state(today());
	let metric = $state<Metric>('orders');
	let report = $state<Report | null>(null);
	let items = $state<Item[]>([]);
	let margin = $state<MarginReport | null>(null);
	let marginBefore = $state<MarginReport | null>(null);
	let loading = $state(true);
	let error = $state('');

	$effect(() => {
		const code = outlets.code;
		const day = date;
		const owner = auth.isOwner;
		const week = addDays(day, -7);
		loading = true;
		error = '';
		Promise.all([
			rpc<Report>('report_daily', { p_outlet: code, p_date: day }),
			rpc<Item[]>('report_products', { p_outlet: code, p_from: day, p_to: day }),
			owner ? loadMargin(code, day, day) : null,
			owner ? loadMargin(code, week, week) : null
		])
			.then(([r, list, m, before]) => {
				if (day !== date) return;
				report = r;
				items = list;
				margin = m;
				marginBefore = before;
			})
			.catch((e) => (error = e.message))
			.finally(() => (loading = false));
	});

	const hours = $derived.by(() => {
		const rows = report?.hours ?? [];
		const first = Math.min(8, ...rows.map((h) => h.hour));
		const last = Math.max(21, ...rows.map((h) => h.hour));
		const out: Hour[] = [];
		for (let h = first; h <= last; h++) {
			out.push(rows.find((r) => r.hour === h) ?? { hour: h, orders: 0, cups: 0, sales: 0 });
		}
		return out;
	});
	const peak = $derived(
		hours.reduce<Hour | null>((best, h) => (h[metric] > 0 && (!best || h[metric] > best[metric]) ? h : best), null)
	);
	const pad = (h: number) => String(h).padStart(2, '0');
	const bars = $derived(
		hours.map((h) => ({
			label: pad(h.hour),
			value: Number(h[metric]),
			highlight: h.hour === peak?.hour,
			tip: `${pad(h.hour)}:00, ${h.orders} orders, ${h.cups} cups, ${rupiah(h.sales)}`
		}))
	);
	const lastWeekday = $derived(`vs last ${weekdayOf(date)}`);
	const compared = (now: number, before: number) => {
		const c = change(now, before);
		return c ? `${c} ${lastWeekday}` : `No sales last ${weekdayOf(date)}`;
	};
	const hasSales = $derived(Number(report?.totals.orders ?? 0) > 0);
	const itemCups = $derived(items.reduce((a, r) => a + Number(r.cups), 0));
	const itemSales = $derived(items.reduce((a, r) => a + Number(r.sales), 0));
	const marginNote = $derived.by(() => {
		if (!margin) return '';
		const parts = [`${pct(marginPct(margin.totals))} of sales`];
		if (marginBefore) parts.push(compared(marginOf(margin.totals), marginOf(marginBefore.totals)));
		return parts.join(' · ');
	});
</script>

<svelte:head><title>Daily · Chacha Reports</title></svelte:head>

<header class="flex flex-wrap items-end justify-between gap-4">
	<h1 class="page-title m-0">Daily report</h1>
	<div class="flex flex-wrap items-center gap-2">
		<button class="btn w-11 text-lg" aria-label="Previous day" onclick={() => (date = addDays(date, -1))}>‹</button>
		<label class="relative">
			<span class="sr-only">Date</span>
			<input class="input font-semibold" type="date" bind:value={date} max={today()} aria-label={longDate(date)} />
		</label>
		<button class="btn w-11 text-lg" aria-label="Next day" disabled={date >= today()} onclick={() => (date = addDays(date, 1))}>›</button>
		{#if outlets.list.length > 1}
			<label class="flex items-center gap-2 text-muted">
				Outlet
				<select class="input" bind:value={outlets.code}>
					{#each outlets.list as o}<option value={o.code}>{o.name}</option>{/each}
				</select>
			</label>
		{/if}
	</div>
</header>

{#if report}
	<div class="flex flex-wrap gap-x-6 gap-y-1 rounded-xl bg-mist-soft px-4 py-3">
		<span>
			{#if report.freshness.last_received_at}
				<strong>Last order received {dateTime(report.freshness.last_received_at)}.</strong>
			{:else}
				<strong>No orders have reached the server yet.</strong>
			{/if}
		</span>
		<span class="text-muted">
			{#if report.freshness.device_seen_at}Tablet last seen {dateTime(report.freshness.device_seen_at)}.{/if}
			Orders on an offline tablet appear when it reconnects.
		</span>
	</div>
{/if}

{#if error || (loading && !report)}
	<Status {loading} {error} />
{:else if report}
	<section aria-label="Day totals" class="grid grid-cols-[repeat(auto-fit,minmax(170px,1fr))] gap-4">
		<Kpi label="Sales" value={rupiah(report.totals.sales)} note={compared(report.totals.sales, report.compare.sales)} />
		<Kpi label="Cups" value={String(report.totals.cups)} note={compared(report.totals.cups, report.compare.cups)} />
		<Kpi label="Orders" value={String(report.totals.orders)} note={compared(report.totals.orders, report.compare.orders)} />
		<Kpi label="Average order" value={rupiah(report.totals.avg_order)} note={compared(report.totals.avg_order, report.compare.avg_order)} />
		{#if margin}
			<Kpi label="Gross margin" value={rupiah(marginOf(margin.totals))} note={marginNote} />
		{/if}
		<Kpi label="Prep time (median)" value={report.prep_median_min == null ? '–' : `${report.prep_median_min} min`} note="Paid to done" />
	</section>

	{#if !hasSales}
		<Status empty={`No sales recorded on ${longDate(date)}.`} />
	{:else}
		<section class="card min-w-0">
				<div class="flex flex-wrap items-center justify-between gap-3">
					<div>
						<h2 class="card-title m-0">{metric === 'orders' ? 'Orders' : metric === 'cups' ? 'Cups' : 'Sales'} by hour</h2>
						{#if peak}<div class="text-muted">Peak at {pad(peak.hour)}:00, shown in brass</div>{/if}
					</div>
					<div role="group" aria-label="Measure" class="flex gap-1">
						{#each ['orders', 'cups', 'sales'] as const as m}
							<button class="btn capitalize {metric === m ? 'btn-primary' : ''}" aria-pressed={metric === m} onclick={() => (metric = m)}>{m}</button>
						{/each}
					</div>
				</div>
				<div class="mt-5">
					<BarChart {bars} title="{metric} by hour" format={(v) => (metric === 'sales' ? `${Math.round(v / 1000)}k` : String(v))} />
				</div>
		</section>

		<section class="card min-w-0">
			<h2 class="card-title m-0">Sales by item</h2>
			<div class="num mb-4 text-muted">{items.length} drinks · {itemCups} cups · {rupiah(itemSales)}</div>
			<ItemCards {items} {margin} foodCost={false} />
			<div class="mt-6">
				<ItemTable {items} {margin} title="Every drink" foodCost={false} />
			</div>
		</section>

		<div class="grid grid-cols-[repeat(auto-fit,minmax(240px,1fr))] gap-4">
			<section class="card !p-5">
				<h2 class="m-0 mb-3 font-display text-xl font-medium">Payments</h2>
				<div class="flex justify-between"><span>Cash</span><strong class="num">{rupiah(report.payments.cash)}</strong></div>
				<div class="flex justify-between"><span>QRIS</span><strong class="num">{rupiah(report.payments.qris)}</strong></div>
				<div class="mt-2.5 border-t border-stone pt-2.5 text-muted">Totals come from recorded orders.</div>
			</section>
			<section class="card !p-5">
				<h2 class="m-0 mb-3 font-display text-xl font-medium">Cashiers</h2>
				{#each report.cashiers as c}
					<div class="flex justify-between gap-2"><span>{c.name}</span><span class="num">{c.cups} cups · {rupiah(c.sales)}</span></div>
				{/each}
				<div class="mt-2.5 border-t border-stone pt-2.5 text-muted">By who was signed in when the order was charged.</div>
			</section>
			<section class="card !p-5">
				<div class="mb-3 flex items-baseline justify-between gap-3">
					<h2 class="m-0 font-display text-xl font-medium">Sugar and ice</h2>
					<a class="text-forest underline" href="/products?date={date}&custom#custom-title">Which drinks?</a>
				</div>
				{#each [['Sugar', report.sugar, ['normal', 'less', 'zero']], ['Ice', report.ice, ['normal', 'less']]] as const as [name, levels, order], g}
					<h3 class="m-0 text-base font-semibold {g ? 'mt-3' : ''}">{name}</h3>
					<dl class="m-0">
						{#each order as level}
							<div class="flex justify-between gap-3">
								<dt class="capitalize">{level}</dt>
								<dd class="num m-0">{Number(levels[level] ?? 0)} {Number(levels[level] ?? 0) === 1 ? 'cup' : 'cups'}</dd>
							</div>
						{/each}
					</dl>
				{/each}
			</section>
			<section class="card !p-5">
				<h2 class="m-0 mb-3 font-display text-xl font-medium">Cancelled</h2>
				<div class="font-bold">{report.cancelled.orders} orders · {rupiah(report.cancelled.amount)}</div>
				<div class="mt-1.5 text-muted">
					{#if report.cancelled.top_reason}Most common reason: {report.cancelled.top_reason}. {/if}Not counted in sales.
				</div>
			</section>
		</div>
	{/if}
{/if}
