<script lang="ts">
	import RangePicker from '$lib/components/RangePicker.svelte';
	import Status from '$lib/components/Status.svelte';
	import { addDays, longDate, today, WEEKDAYS } from '$lib/format';
	import { outlets } from '$lib/outlet.svelte';
	import { rpc } from '$lib/supabase';

	type Report = {
		grid: { dow: number; hour: number; cups: number; avg_cups: number }[];
		weekday_cups: { dow: number; avg_cups: number }[];
		peak_hour: number | null;
		prep: { median: number | null; peak_median: number | null; over_10_pct: number | null };
		dayparts: { part: number; name: string; cups: number }[];
	};

	let to = $state(today());
	let from = $state(addDays(today(), -27));
	let report = $state<Report | null>(null);
	let loading = $state(true);
	let error = $state('');

	$effect(() => {
		const args = { p_outlet: outlets.code, p_from: from, p_to: to };
		loading = true;
		error = '';
		rpc<Report>('report_time', args)
			.then((r) => (report = r))
			.catch((e) => (error = e.message))
			.finally(() => (loading = false));
	});

	const pad = (h: number) => String(h).padStart(2, '0');
	const hours = $derived.by(() => {
		const seen = (report?.grid ?? []).map((g) => g.hour);
		const first = Math.min(8, ...seen);
		const last = Math.max(21, ...seen);
		return Array.from({ length: last - first + 1 }, (_, i) => first + i);
	});
	const max = $derived(Math.max(1, ...(report?.grid ?? []).map((g) => Number(g.avg_cups))));
	const cell = (dow: number, hour: number) => report?.grid.find((g) => g.dow === dow && g.hour === hour);

	/** One green, light to dark. Text flips to white where the fill gets dark. */
	function shade(v: number) {
		const t = v / max;
		if (v === 0) return 'background:#f7f4ee;color:#5a6964';
		if (t <= 0.2) return 'background:#e3eae6;color:#1a2e2a';
		if (t <= 0.4) return 'background:#c9d5cf;color:#1a2e2a';
		if (t <= 0.6) return 'background:#819a89;color:#1a2e2a';
		if (t <= 0.8) return 'background:#4f6a62;color:#fff';
		return 'background:#164942;color:#fff';
	}

	const busiest = $derived(
		[...(report?.grid ?? [])].sort((a, b) => Number(b.avg_cups) - Number(a.avg_cups))[0] ?? null
	);
	const busiestDay = $derived(report?.weekday_cups[0] ?? null);
	const quietestDay = $derived(report?.weekday_cups.at(-1) ?? null);
	const PARTS = ['Morning (before 11)', 'Midday (11 to 15)', 'Afternoon (15 to 18)', 'Evening (from 18)'];
</script>

<svelte:head><title>By time · Chacha Reports</title></svelte:head>

<header class="flex flex-wrap items-end justify-between gap-4">
	<h1 class="page-title m-0">By time</h1>
	<RangePicker bind:from bind:to presets={[14, 28, 90]} />
</header>

{#if error || (loading && !report)}
	<Status {loading} {error} />
{:else if report && !report.grid.length}
	<Status empty={`No sales recorded from ${longDate(from)} to ${longDate(to)}.`} />
{:else if report}
	<section class="card">
		<h2 class="card-title m-0">Average cups per hour</h2>
		<div class="text-muted">Darker means busier. Hours use outlet time (WIB). Averages count only days with sales.</div>
		<div class="mt-4 overflow-x-auto">
			<table class="num w-full min-w-[760px] table-fixed border-separate border-spacing-[3px]">
				<thead>
					<tr>
						<th scope="col" class="w-12"><span class="sr-only">Day</span></th>
						{#each hours as h}<th scope="col" class="pb-1 text-xs font-semibold text-muted">{pad(h)}</th>{/each}
					</tr>
				</thead>
				<tbody>
					{#each WEEKDAYS as day, i}
						<tr>
							<th scope="row" class="text-left font-semibold">{day}</th>
							{#each hours as h}
								{@const c = cell(i + 1, h)}
								{@const v = Number(c?.avg_cups ?? 0)}
								<td class="h-11 rounded text-center font-semibold" style={shade(v)} title="{day} {pad(h)}:00, average {v} cups">
									{v ? (v < 10 ? v.toFixed(1) : Math.round(v)) : ''}
								</td>
							{/each}
						</tr>
					{/each}
				</tbody>
			</table>
		</div>
	</section>

	<div class="grid grid-cols-[repeat(auto-fit,minmax(260px,1fr))] gap-4">
		<section class="card !p-5">
			<h2 class="m-0 mb-3 font-display text-xl font-medium">Busiest and quietest</h2>
			{#if busiest}
				<div class="flex justify-between gap-3"><span>Busiest hour</span><strong class="num">{WEEKDAYS[busiest.dow - 1]} {pad(busiest.hour)}:00</strong></div>
			{/if}
			{#if busiestDay}
				<div class="mt-1.5 flex justify-between gap-3"><span>Busiest day</span><strong class="num">{WEEKDAYS[busiestDay.dow - 1]}, {busiestDay.avg_cups} cups</strong></div>
			{/if}
			{#if quietestDay}
				<div class="mt-1.5 flex justify-between gap-3"><span>Quietest day</span><strong class="num">{WEEKDAYS[quietestDay.dow - 1]}, {quietestDay.avg_cups} cups</strong></div>
			{/if}
		</section>

		<section class="card !p-5">
			<h2 class="m-0 mb-3 font-display text-xl font-medium">Prep time</h2>
			{#if report.prep.median == null}
				<div class="text-muted">No orders marked Done in this period.</div>
			{:else}
				<div class="flex justify-between gap-3"><span>All day (median)</span><strong class="num">{report.prep.median} min</strong></div>
				{#if report.peak_hour != null && report.prep.peak_median != null}
					<div class="mt-1.5 flex justify-between gap-3"><span>At peak, {pad(report.peak_hour)}:00</span><strong class="num">{report.prep.peak_median} min</strong></div>
				{/if}
				<div class="mt-1.5 flex justify-between gap-3"><span>Waited over 10 min</span><strong class="num">{report.prep.over_10_pct}% of orders</strong></div>
				<div class="mt-2.5 border-t border-stone pt-2.5 text-muted">Paid to Done, so it's only as accurate as tapping Done on time.</div>
			{/if}
		</section>

		<section class="card !p-5">
			<h2 class="m-0 mb-3 font-display text-xl font-medium">Top drink by time of day</h2>
			{#each report.dayparts as p, i}
				<div class="flex justify-between gap-3 {i ? 'mt-1.5' : ''}"><span>{PARTS[p.part - 1]}</span><strong class="text-right">{p.name}</strong></div>
			{/each}
		</section>
	</div>
{/if}
