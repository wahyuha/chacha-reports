<script lang="ts">
	import BarChart from '$lib/components/BarChart.svelte';
	import Kpi from '$lib/components/Kpi.svelte';
	import RangePicker from '$lib/components/RangePicker.svelte';
	import Status from '$lib/components/Status.svelte';
	import { addDays, change, longDate, rupiah, shortDate, today, weekdayShort, WEEKDAYS } from '$lib/format';
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
	let loading = $state(true);
	let error = $state('');

	$effect(() => {
		const args = { p_outlet: outlets.code, p_from: from, p_to: to };
		loading = true;
		error = '';
		rpc<Report>('report_sales', args)
			.then((r) => (report = r))
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

	function exportCsv() {
		const rows = [
			['date', 'orders', 'cups', 'sales', 'cash', 'qris'],
			...allDays.map((d) => [d.date, d.orders, d.cups, d.sales, d.cash, d.qris])
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

		<div class="flex flex-wrap gap-4">
			<section class="card min-w-0 flex-[2_1_520px]">
				<h2 class="card-title m-0 mb-3">Day by day</h2>
				<div class="overflow-x-auto">
					<table class="num w-full min-w-[520px] border-collapse text-right">
						<thead>
							<tr>
								<th scope="col" class="th text-left">Date</th>
								<th scope="col" class="th">Orders</th>
								<th scope="col" class="th">Cups</th>
								<th scope="col" class="th">Cash</th>
								<th scope="col" class="th">QRIS</th>
								<th scope="col" class="th">Sales</th>
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
