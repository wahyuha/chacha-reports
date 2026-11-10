<script lang="ts">
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import { auth } from '$lib/auth.svelte';
	import { cupsNeeded, type Roi } from '$lib/business';
	import Kpi from '$lib/components/Kpi.svelte';
	import NetChart from '$lib/components/NetChart.svelte';
	import Status from '$lib/components/Status.svelte';
	import { longDate, monthName, rupiah, shortDate, today } from '$lib/format';
	import { outlets } from '$lib/outlet.svelte';
	import { rpc } from '$lib/supabase';

	type Line = { name: string; month_amount: number; amount: number };
	type Pnl = {
		month: string;
		opened_on: string;
		from: string | null;
		to: string | null;
		days_in_month: number;
		days_counted: number;
		complete?: boolean;
		totals?: { cups: number; sales: number; cost: number; costed_sales: number; uncosted_cups: number; commission: number };
		staff?: Line[];
		costs?: (Line & { code: string })[];
		days?: { date: string; cups: number; gross: number; net: number }[];
	};

	const thisMonth = today().slice(0, 7);
	// ROI links here with ?month=YYYY-MM.
	const asked = page.url.searchParams.get('month');
	let month = $state(asked && /^\d{4}-\d{2}$/.test(asked) && asked <= thisMonth ? asked : thisMonth);
	let pnl = $state<Pnl | null>(null);
	let roi = $state<Roi | null>(null);
	let loading = $state(true);
	let error = $state('');

	$effect(() => {
		if (!auth.isOwner) goto('/');
	});

	$effect(() => {
		const m = month;
		const code = outlets.code;
		loading = true;
		error = '';
		Promise.all([rpc<Pnl>('report_pnl', { p_outlet: code, p_month: `${m}-01` }), rpc<Roi>('report_roi', { p_outlet: code })])
			.then(([p, r]) => {
				if (m !== month) return;
				pnl = p;
				roi = r;
			})
			.catch((e) => (error = e.message))
			.finally(() => (loading = false));
	});

	const n = (v: unknown) => Number(v ?? 0);
	const t = $derived(pnl?.totals);
	const gross = $derived(n(t?.costed_sales) - n(t?.cost));
	const base = $derived((pnl?.staff ?? []).reduce((a, l) => a + n(l.amount), 0));
	const fixed = $derived((pnl?.costs ?? []).reduce((a, l) => a + n(l.amount), 0));
	const net = $derived(gross - base - n(t?.commission) - fixed);
	const sales = $derived(n(t?.sales));
	const pctOf = (v: number) => (sales ? `${Math.round((v / sales) * 100)}%` : '–');
	const salesDays = $derived((pnl?.days ?? []).filter((d) => n(d.cups) > 0).length);
	const cupsADay = $derived(salesDays ? Math.round(n(t?.cups) / salesDays) : 0);
	const breakEven = $derived(roi ? cupsNeeded(roi) : null);
	const partial = $derived(pnl && pnl.from ? pnl.days_counted < pnl.days_in_month : false);
	const daysLeftCounted = $derived.by(() => {
		if (!pnl?.from) return 0;
		const end = new Date(`${pnl.month}T00:00:00Z`);
		end.setUTCMonth(end.getUTCMonth() + 1);
		return Math.round((end.getTime() - Date.parse(`${pnl.from}T00:00:00Z`)) / 86400000);
	});
	const onTrack = $derived(pnl && !pnl.complete && pnl.days_counted ? Math.round((net / pnl.days_counted) * daysLeftCounted) : null);
	const share = $derived(pnl ? `${pnl.days_counted}/${pnl.days_in_month} days` : '');
	const openedThisMonth = $derived(pnl ? pnl.opened_on.slice(0, 7) === month : false);
	const bars = $derived(
		(pnl?.days ?? []).map((d) => ({
			label: d.date.slice(8).replace(/^0/, ''),
			value: n(d.net),
			tip: `${shortDate(d.date)}: ${d.cups} cups, gross margin ${rupiah(d.gross)}, net ${rupiah(d.net)}`
		}))
	);

	function step(by: number) {
		const d = new Date(`${month}-01T00:00:00Z`);
		d.setUTCMonth(d.getUTCMonth() + by);
		month = d.toISOString().slice(0, 7);
	}
</script>

<svelte:head><title>Profit and loss · Chacha Reports</title></svelte:head>

<header class="flex flex-wrap items-end justify-between gap-4">
	<div>
		<div class="eyebrow">Owner only</div>
		<h1 class="page-title m-0 mt-1">Profit and loss</h1>
	</div>
	<div class="flex flex-wrap items-center gap-2">
		<button class="btn w-11 text-lg" aria-label="Previous month" disabled={!!pnl && month <= pnl.opened_on.slice(0, 7)} onclick={() => step(-1)}>‹</button>
		<label><span class="sr-only">Month</span><input class="input font-semibold" type="month" bind:value={month} max={thisMonth} /></label>
		<button class="btn w-11 text-lg" aria-label="Next month" disabled={month >= thisMonth} onclick={() => step(1)}>›</button>
	</div>
</header>

{#if error || (loading && !pnl)}
	<Status {loading} {error} />
{:else if pnl && !pnl.from}
	<Status empty={`Nothing to count in ${monthName(`${month}-01`)}: the outlet opened on ${longDate(pnl.opened_on)}.`} />
{:else if pnl && t}
	<section class="rounded-xl bg-mist-soft px-5 py-4">
		<strong>{monthName(pnl.month)}{pnl.complete ? '' : ' so far'}:</strong>
		{shortDate(pnl.from!)} to {shortDate(pnl.to!)}, {pnl.days_counted} of {pnl.days_in_month} days.
		{#if openedThisMonth}Counted from the opening day; costs before it are part of the starting capital.{/if}
		{#if partial}Monthly costs and base salaries count only for these days.{/if}
	</section>

	<section aria-label="Month totals" class="grid grid-cols-[repeat(auto-fit,minmax(200px,1fr))] gap-4">
		<Kpi
			label="Net profit"
			value={rupiah(net)}
			note={onTrack != null ? `On track for ${rupiah(onTrack)} this month` : pnl.complete ? 'Whole month' : ''}
		/>
		<Kpi label="Net margin" value={pctOf(net)} note="Of sales, after all costs" />
		<Kpi label="Break-even" value={breakEven == null ? '–' : `${breakEven} cups a day`} note="To cover HPP, staff and monthly costs" />
		<Kpi
			label="Cups a day"
			value={String(cupsADay)}
			note={breakEven == null ? `Over ${salesDays} days with sales` : cupsADay >= breakEven ? `${cupsADay - breakEven} above break-even` : `${breakEven - cupsADay} below break-even`}
		/>
	</section>

	<section class="card">
		<h2 class="card-title m-0 mb-3">Statement</h2>
		<div class="overflow-x-auto">
			<table class="num w-full min-w-[620px] border-collapse text-right">
				<thead>
					<tr>
						<th scope="col" class="th pl-0 text-left"><span class="sr-only">Line</span></th>
						<th scope="col" class="th">{pnl.complete ? 'Month' : 'So far'}</th>
						<th scope="col" class="th">Of sales</th>
						<th scope="col" class="th pr-0 text-left">Counted as</th>
					</tr>
				</thead>
				<tbody>
					<tr>
						<th scope="row" class="td pl-0 text-left font-semibold">Sales</th>
						<td class="td font-semibold">{rupiah(sales)}</td>
						<td class="td">100%</td>
						<td class="td pr-0 text-left text-muted">{t.cups} cups</td>
					</tr>
					<tr>
						<th scope="row" class="td pl-0 text-left font-normal">− HPP (ingredients + packaging)</th>
						<td class="td">{rupiah(t.cost)}</td>
						<td class="td">{pctOf(n(t.cost))}</td>
						<td class="td pr-0 text-left text-muted"><a class="text-forest underline" href="/costs">Menu costs</a></td>
					</tr>
					<tr class="bg-mist-soft">
						<th scope="row" class="td pl-2 text-left font-semibold">= Gross margin</th>
						<td class="td font-semibold">{rupiah(gross)}</td>
						<td class="td">{pctOf(gross)}</td>
						<td class="td pr-2 text-left text-muted">
							{#if n(t.uncosted_cups)}<span class="text-danger">{t.uncosted_cups} cups without HPP left out</span>{/if}
						</td>
					</tr>
					{#each pnl.staff ?? [] as s}
						<tr>
							<th scope="row" class="td pl-0 text-left font-normal">− {s.name}, base salary</th>
							<td class="td">{rupiah(s.amount)}</td>
							<td class="td">{pctOf(n(s.amount))}</td>
							<td class="td pr-0 text-left text-muted">{rupiah(s.month_amount)} a month{partial ? `, ${share}` : ''}</td>
						</tr>
					{/each}
					<tr>
						<th scope="row" class="td pl-0 text-left font-normal">− Staff commission</th>
						<td class="td">{rupiah(t.commission)}</td>
						<td class="td">{pctOf(n(t.commission))}</td>
						<td class="td pr-0 text-left text-muted">Actual, <a class="text-forest underline" href="/payroll">from clock-ins</a></td>
					</tr>
					{#each pnl.costs ?? [] as c (c.code)}
						<tr>
							<th scope="row" class="td pl-0 text-left font-normal">− {c.name}</th>
							<td class="td">{rupiah(c.amount)}</td>
							<td class="td">{pctOf(n(c.amount))}</td>
							<td class="td pr-0 text-left text-muted">{rupiah(c.month_amount)} a month{partial ? `, ${share}` : ''}</td>
						</tr>
					{/each}
					<tr class="border-t-2 border-ink">
						<th scope="row" class="py-2.5 text-left font-bold">= Net profit</th>
						<td class="px-2 py-2.5 font-bold {net < 0 ? 'text-danger' : ''}">{rupiah(net)}</td>
						<td class="px-2 py-2.5 font-bold">{pctOf(net)}</td>
						<td class="py-2.5 text-left text-muted">{net < 0 ? 'Loss' : 'Profit'}</td>
					</tr>
				</tbody>
			</table>
		</div>
		<p class="m-0 mt-3 text-[13px] text-muted">
			Change rent and utilities in <a class="text-forest underline" href="/monthly-costs">Monthly costs</a>, and base salaries in
			<a class="text-forest underline" href="/payroll">Salary and commission</a>.
		</p>
	</section>

	<section class="card">
		<h2 class="card-title m-0">Net profit by day</h2>
		<div class="text-muted">Each day's gross margin minus commission and its share of salaries and monthly costs. Loss days are in red, below the line.</div>
		<div class="mt-4 overflow-x-auto">
			<div class={bars.length > 14 ? 'min-w-[640px]' : ''}>
				<NetChart {bars} title="Net profit by day" />
			</div>
		</div>
	</section>
{/if}
