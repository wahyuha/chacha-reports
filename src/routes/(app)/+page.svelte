<script lang="ts">
	import BarChart from '$lib/components/BarChart.svelte';
	import Kpi from '$lib/components/Kpi.svelte';
	import Status from '$lib/components/Status.svelte';
	import { addDays, change, clock, dateTime, longDate, rupiah, share, today, weekdayOf } from '$lib/format';
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
	let loading = $state(true);
	let error = $state('');

	$effect(() => {
		const code = outlets.code;
		const day = date;
		loading = true;
		error = '';
		rpc<Report>('report_daily', { p_outlet: code, p_date: day })
			.then((r) => {
				if (day === date) report = r;
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
	const percentages = (levels: Record<string, number>, order: string[]) => {
		const total = Object.values(levels).reduce((a, b) => a + Number(b), 0);
		return order.map((l) => `${l[0].toUpperCase()}${l.slice(1)} ${share(Number(levels[l] ?? 0), total)}%`).join(' · ');
	};
	const topMax = $derived(Math.max(1, ...(report?.top ?? []).map((p) => Number(p.cups))));
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
		<Kpi label="Prep time (median)" value={report.prep_median_min == null ? '–' : `${report.prep_median_min} min`} note="Paid to done" />
	</section>

	{#if !hasSales}
		<Status empty={`No sales recorded on ${longDate(date)}.`} />
	{:else}
		<div class="flex flex-wrap gap-4">
			<section class="card min-w-0 flex-[2_1_480px]">
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

			<section class="card min-w-0 flex-[1_1_300px]">
				<div class="flex items-baseline justify-between gap-3">
					<h2 class="card-title m-0">Best sellers</h2>
					<a class="text-forest underline" href="/products">See all</a>
				</div>
				<ol class="m-0 mt-4 flex list-none flex-col gap-3.5 p-0">
					{#each report.top as p, i}
						<li>
							<div class="flex justify-between gap-3">
								<span class="font-semibold">{i + 1}. {p.name}</span>
								<span class="num whitespace-nowrap">{p.cups} cups</span>
							</div>
							<div class="mt-1 h-2 rounded bg-mist-soft"><div class="h-2 rounded bg-forest" style:width="{(Number(p.cups) / topMax) * 100}%"></div></div>
							<div class="num text-[13px] text-muted">{rupiah(p.sales)}</div>
						</li>
					{/each}
				</ol>
			</section>
		</div>

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
				<h2 class="m-0 mb-3 font-display text-xl font-medium">Sugar and ice</h2>
				<div class="flex justify-between gap-3"><span>Sugar</span><span>{percentages(report.sugar, ['normal', 'less', 'zero'])}</span></div>
				<div class="mt-1.5 flex justify-between gap-3"><span>Ice</span><span>{percentages(report.ice, ['normal', 'less'])}</span></div>
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
