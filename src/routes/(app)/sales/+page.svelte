<script lang="ts">
	import { auth } from '$lib/auth.svelte';
	import BarChart from '$lib/components/BarChart.svelte';
	import Kpi from '$lib/components/Kpi.svelte';
	import RangePicker from '$lib/components/RangePicker.svelte';
	import Status from '$lib/components/Status.svelte';
	import { addDays, change, longDate, rupiah, shortDate, today, weekdayShort, WEEKDAYS } from '$lib/format';
	import { EMPTY, foodCostOf, HIGH_FOOD_COST, loadMargin, marginOf, marginPct, pct, type MarginReport } from '$lib/margin';
	import { outlets } from '$lib/outlet.svelte';
	import { rpc } from '$lib/supabase';

	type Totals = { sales: number; orders: number; cups: number };
	type Day = { date: string; orders: number; cups: number; sales: number; cash: number; qris: number };
	type Report = {
		totals: Totals;
		previous: Totals;
		days: Day[];
		weekdays: { dow: number; avg_sales: number; avg_cups: number }[];
	};

	let to = $state(today());
	let from = $state(addDays(today(), -13));
	let report = $state<Report | null>(null);
	let margin = $state<MarginReport | null>(null);
	let marginBefore = $state<MarginReport | null>(null);
	let loading = $state(true);
	let error = $state('');

	$effect(() => {
		const args = { p_outlet: outlets.code, p_from: from, p_to: to };
		loading = true;
		error = '';
		const owner = auth.isOwner;
		const len = Math.round((Date.parse(to) - Date.parse(from)) / 86400000) + 1;
		Promise.all([
			rpc<Report>('report_sales', args),
			owner ? loadMargin(args.p_outlet, from, to) : null,
			owner ? loadMargin(args.p_outlet, addDays(from, -len), addDays(from, -1)) : null
		])
			.then(([r, m, before]) => {
				if (args.p_from !== from || args.p_to !== to) return;
				report = r;
				margin = m;
				marginBefore = before;
			})
			.catch((e) => (error = e.message))
			.finally(() => (loading = false));
	});

	const allDays = $derived.by(() => {
		const out: Day[] = [];
		for (let d = from; d <= to; d = addDays(d, 1)) {
			out.push(report?.days.find((x) => x.date === d) ?? { date: d, orders: 0, cups: 0, sales: 0, cash: 0, qris: 0 });
		}
		return out;
	});
	const average = $derived(allDays.length ? Number(report?.totals.sales ?? 0) / allDays.length : 0);
	const compact = $derived(allDays.length > 31);
	const bars = $derived(
		allDays.map((d) => ({
			label: compact ? '' : weekdayShort(d.date),
			sublabel: compact ? '' : d.date.slice(8).replace(/^0/, ''),
			value: Number(d.sales),
			highlight: d.date === today(),
			tip: `${shortDate(d.date)}, ${rupiah(d.sales)}, ${d.cups} cups, ${d.orders} orders`
		}))
	);
	const note = (now: number, before: number) => {
		const c = change(now, before);
		return c ? `${c} vs previous ${allDays.length} days` : 'Nothing to compare with yet';
	};
	const maxWeekday = $derived(Math.max(1, ...(report?.weekdays ?? []).map((w) => Number(w.avg_sales))));

	const marginDay = $derived(new Map((margin?.days ?? []).map((d) => [d.date, d])));
	const dayMargin = (date: string) => marginDay.get(date) ?? EMPTY;
	const marginAverage = $derived(margin && allDays.length ? marginOf(margin.totals) / allDays.length : 0);
	const marginBars = $derived(
		allDays.map((d) => {
			const m = dayMargin(d.date);
			return {
				label: compact ? '' : weekdayShort(d.date),
				sublabel: compact ? '' : d.date.slice(8).replace(/^0/, ''),
				value: Math.max(0, marginOf(m)),
				highlight: d.date === today(),
				tip: `${shortDate(d.date)}, margin ${rupiah(marginOf(m))} (${pct(marginPct(m))}), HPP ${rupiah(m.cost)}`
			};
		})
	);

	function exportCsv() {
		const head = ['date', 'orders', 'cups', 'sales', 'cash', 'qris', ...(margin ? ['hpp_total', 'gross_margin', 'cups_without_hpp'] : [])];
		const rows = [
			head,
			...allDays.map((d) => {
				const m = dayMargin(d.date);
				return [d.date, d.orders, d.cups, d.sales, d.cash, d.qris, ...(margin ? [m.cost, marginOf(m), m.uncosted_cups] : [])];
			})
		];
		const blob = new Blob([rows.map((r) => r.join(',')).join('\n')], { type: 'text/csv' });
		const a = document.createElement('a');
		a.href = URL.createObjectURL(blob);
		a.download = `chacha-sales-${from}-to-${to}.csv`;
		a.click();
		URL.revokeObjectURL(a.href);
	}
</script>

<svelte:head><title>Sales · Chacha Reports</title></svelte:head>

<header class="flex flex-wrap items-end justify-between gap-4">
	<h1 class="page-title m-0">Sales</h1>
	<div class="flex flex-wrap items-center gap-2">
		<RangePicker bind:from bind:to />
		<button class="btn" onclick={exportCsv} disabled={!report}>Export CSV</button>
	</div>
</header>

{#if error || (loading && !report)}
	<Status {loading} {error} />
{:else if report}
	<section aria-label="Period totals" class="grid grid-cols-[repeat(auto-fit,minmax(170px,1fr))] gap-4">
		<Kpi label="Sales" value={rupiah(report.totals.sales)} note={note(report.totals.sales, report.previous.sales)} />
		<Kpi label="Cups" value={String(report.totals.cups)} note={note(report.totals.cups, report.previous.cups)} />
		<Kpi label="Orders" value={String(report.totals.orders)} note={note(report.totals.orders, report.previous.orders)} />
		<Kpi label="Average per day" value={rupiah(average)} note="{Math.round(Number(report.totals.cups) / allDays.length)} cups a day" />
		{#if margin}
			<Kpi
				label="Gross margin"
				value={rupiah(marginOf(margin.totals))}
				note={marginBefore ? note(marginOf(margin.totals), marginOf(marginBefore.totals)) : `${pct(marginPct(margin.totals))} of sales`}
			/>
		{/if}
	</section>

	{#if !report.days.length}
		<Status empty={`No sales recorded from ${longDate(from)} to ${longDate(to)}.`} />
	{:else}
		<section class="card">
			<h2 class="card-title m-0">Sales per day</h2>
			<div class="text-muted">{longDate(from)} to {longDate(to)}. Dashed line: daily average, {rupiah(average)}.</div>
			<div class="mt-5 overflow-x-auto">
				<div class={allDays.length > 14 ? 'min-w-[640px]' : ''}>
					<BarChart {bars} title="Sales per day" format={(v) => `${Math.round(v / 1000)}k`} reference={average} />
				</div>
			</div>
		</section>

		{#if margin}
			{@const t = margin.totals}
			{@const fc = foodCostOf(t)}
			<section class="card" aria-labelledby="margin-title">
				<div class="flex flex-wrap items-baseline justify-between gap-2">
					<h2 id="margin-title" class="card-title m-0">Gross margin</h2>
					<a class="text-forest underline" href="/costs">Menu costs (HPP)</a>
				</div>
				<div class="text-muted">Price charged − HPP (ingredients + packaging), before staff, rent and utilities.</div>
				<dl class="m-0 mt-4 grid grid-cols-2 gap-4 sm:grid-cols-3 xl:grid-cols-5">
					<div class="rounded-xl bg-mist-soft p-4">
						<dt class="text-muted">Gross margin</dt>
						<dd class="num m-0 mt-1 text-2xl leading-8 font-bold whitespace-nowrap">{rupiah(marginOf(t))}</dd>
						<dd class="m-0 text-[13px] text-muted">{pct(marginPct(t))} of sales</dd>
					</div>
					<div class="rounded-xl bg-mist-soft p-4">
						<dt class="text-muted">HPP total</dt>
						<dd class="num m-0 mt-1 text-2xl leading-8 font-bold whitespace-nowrap">{rupiah(t.cost)}</dd>
						<dd class="m-0 text-[13px] {fc != null && fc > HIGH_FOOD_COST ? 'font-semibold text-danger' : 'text-muted'}">Food cost {pct(fc)}</dd>
					</div>
					<div class="rounded-xl bg-mist-soft p-4">
						<dt class="text-muted">Margin per cup</dt>
						<dd class="num m-0 mt-1 text-2xl leading-8 font-bold whitespace-nowrap">
							{rupiah(Number(t.cups) - Number(t.uncosted_cups) ? Math.round(marginOf(t) / (Number(t.cups) - Number(t.uncosted_cups))) : 0)}
						</dd>
						<dd class="m-0 text-[13px] text-muted">Average over {Number(t.cups) - Number(t.uncosted_cups)} cups</dd>
					</div>
					<div class="rounded-xl bg-mist-soft p-4">
						<dt class="text-muted">Margin per day</dt>
						<dd class="num m-0 mt-1 text-2xl leading-8 font-bold whitespace-nowrap">{rupiah(Math.round(marginAverage))}</dd>
						<dd class="m-0 text-[13px] text-muted">Over {allDays.length} days</dd>
					</div>
					<div class="rounded-xl bg-mist-soft p-4">
						<dt class="text-muted">Cups without HPP</dt>
						<dd class="num m-0 mt-1 text-2xl leading-8 font-bold {Number(t.uncosted_cups) ? 'text-danger' : ''}">{t.uncosted_cups}</dd>
						<dd class="m-0 text-[13px] text-muted">{Number(t.uncosted_cups) ? 'Not in the margin' : 'Every cup has an HPP'}</dd>
					</div>
				</dl>
				<h3 class="m-0 mt-6 text-base font-semibold">Margin per day</h3>
				<div class="text-muted">Dashed line: daily average, {rupiah(Math.round(marginAverage))}.</div>
				<div class="mt-4 overflow-x-auto">
					<div class={allDays.length > 14 ? 'min-w-[640px]' : ''}>
						<BarChart bars={marginBars} title="Gross margin per day" format={(v) => `${Math.round(v / 1000)}k`} reference={marginAverage} />
					</div>
				</div>
			</section>
		{/if}

		<div class="flex flex-wrap gap-4">
			<section class="card min-w-0 flex-[2_1_520px]">
				<h2 class="card-title m-0 mb-3">Day by day</h2>
				<div class="overflow-x-auto">
					<table class="num w-full {margin ? 'min-w-[720px]' : 'min-w-[520px]'} border-collapse text-right">
						<thead>
							<tr>
								<th scope="col" class="th text-left">Date</th>
								<th scope="col" class="th">Orders</th>
								<th scope="col" class="th">Cups</th>
								<th scope="col" class="th">Cash</th>
								<th scope="col" class="th">QRIS</th>
								<th scope="col" class="th">Sales</th>
								{#if margin}
									<th scope="col" class="th">HPP</th>
									<th scope="col" class="th">Margin</th>
								{/if}
							</tr>
						</thead>
						<tbody>
							{#each [...report.days].reverse() as d}
								<tr>
									<td class="td text-left">{shortDate(d.date)}</td>
									<td class="td">{d.orders}</td>
									<td class="td">{d.cups}</td>
									<td class="td">{rupiah(d.cash)}</td>
									<td class="td">{rupiah(d.qris)}</td>
									<td class="td font-semibold">{rupiah(d.sales)}</td>
									{#if margin}
										{@const m = dayMargin(d.date)}
										<td class="td">{rupiah(m.cost)}</td>
										<td class="td font-semibold">
											{rupiah(marginOf(m))}
											<div class="text-[13px] font-normal text-muted">{pct(marginPct(m))}{Number(m.uncosted_cups) ? ` · ${m.uncosted_cups} cups no HPP` : ''}</div>
										</td>
									{/if}
								</tr>
							{/each}
						</tbody>
					</table>
				</div>
			</section>

			<section class="card min-w-0 flex-[1_1_280px]">
				<h2 class="card-title m-0 mb-3">Average by weekday</h2>
				<div class="flex flex-col gap-2.5">
					{#each report.weekdays as w}
						<div class="grid grid-cols-[36px_1fr_96px] items-center gap-2">
							<span>{WEEKDAYS[w.dow - 1]}</span>
							<div class="h-2 rounded bg-mist-soft"><div class="h-2 rounded bg-forest" style:width="{(Number(w.avg_sales) / maxWeekday) * 100}%"></div></div>
							<span class="num text-right">{rupiah(w.avg_sales)}</span>
						</div>
					{/each}
				</div>
			</section>
		</div>
	{/if}
{/if}
