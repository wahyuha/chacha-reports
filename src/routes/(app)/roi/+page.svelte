<script lang="ts">
	import { goto } from '$app/navigation';
	import { auth } from '$lib/auth.svelte';
	import {
		addMonths,
		capitalTotal,
		cupsNeeded,
		cupsPerDay,
		DAYS_PER_MONTH,
		fixedPerDay,
		marginPerCup,
		MIN_DAYS,
		netPerDay,
		type Roi
	} from '$lib/business';
	import Kpi from '$lib/components/Kpi.svelte';
	import Status from '$lib/components/Status.svelte';
	import { longDate, monthName, rupiah } from '$lib/format';
	import { outlets } from '$lib/outlet.svelte';
	import { rpc } from '$lib/supabase';

	let roi = $state<Roi | null>(null);
	let loading = $state(true);
	let error = $state('');
	let busy = $state(false);
	let actionError = $state('');
	let editing = $state<{ id: string | null; name: string; amount: string } | null>(null);
	let removing = $state<string | null>(null);
	let settings = $state<{ opened_on: string; payback_months: string; staff_per_day: string } | null>(null);

	$effect(() => {
		if (!auth.isOwner) goto('/');
	});

	async function load() {
		loading = true;
		try {
			roi = await rpc<Roi>('report_roi', { p_outlet: outlets.code });
			error = '';
		} catch (e) {
			error = (e as Error).message;
		} finally {
			loading = false;
		}
	}

	$effect(() => {
		void outlets.code;
		load();
	});

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

	const amount = (s: string) => Number(s.replace(/\D/g, ''));
	const days = (from: string, to: string) => Math.round((Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / 86400000);
	const plusDays = (date: string, n: number) => new Date(Date.parse(`${date}T00:00:00Z`) + n * 86400000).toISOString().slice(0, 10);

	const capital = $derived(roi ? capitalTotal(roi) : 0);
	const recovered = $derived(Number(roi?.net_to_date ?? 0));
	const remaining = $derived(Math.max(0, capital - recovered));
	const progress = $derived(capital ? Math.min(100, Math.max(0, (recovered / capital) * 100)) : 0);
	const roiPct = $derived(capital ? Math.round(((recovered - capital) / capital) * 100) : null);
	const enoughData = $derived(Number(roi?.recent.sales_days ?? 0) >= MIN_DAYS);
	const pace = $derived(roi ? netPerDay(roi) : 0);
	const paybackDate = $derived(roi && pace > 0 ? plusDays(roi.today, Math.ceil(remaining / pace)) : null);
	const cupsNow = $derived(roi ? Math.round(cupsPerDay(roi)) : 0);
	const margin = $derived(roi ? marginPerCup(roi) : null);

	/** What paying back within `months` of opening takes from today: net profit a month and cups a day. */
	function target(months: number) {
		if (!roi) return null;
		const by = addMonths(roi.opened_on, months);
		const daysLeft = days(roi.today, by);
		if (daysLeft <= 0) return { months, by, passed: true, perMonth: 0, cups: null as number | null };
		const perDay = remaining / daysLeft;
		return { months, by, passed: false, perMonth: perDay * DAYS_PER_MONTH, cups: cupsNeeded(roi, perDay) };
	}
	const goal = $derived(roi ? target(roi.payback_months) : null);
	const options = $derived(
		roi ? [...new Set([6, 12, 18, 24, roi.payback_months])].sort((a, b) => a - b).map((m) => target(m)!) : []
	);
	const breakEven = $derived(roi ? cupsNeeded(roi) : null);
	const cumulative = $derived.by(() => {
		let sum = 0;
		return (roi?.months ?? []).map((m) => ({ ...m, total: (sum += Number(m.net)) }));
	});

	function saveItem(e: SubmitEvent) {
		e.preventDefault();
		const item = editing!;
		act(async () => {
			await rpc('capital_item_save', { p_outlet: outlets.code, p_id: item.id, p_name: item.name, p_amount: amount(item.amount) });
			editing = null;
		});
	}

	function saveSettings(e: SubmitEvent) {
		e.preventDefault();
		const s = settings!;
		act(async () => {
			await rpc('business_settings_save', {
				p_outlet: outlets.code,
				p_opened_on: s.opened_on,
				p_payback_months: Number(s.payback_months),
				p_staff_per_day: Number(s.staff_per_day)
			});
			settings = null;
		});
	}
</script>

<svelte:head><title>Return on investment · Chacha Reports</title></svelte:head>

<header class="flex flex-wrap items-end justify-between gap-4">
	<div>
		<div class="eyebrow">Owner only</div>
		<h1 class="page-title m-0 mt-1">Return on investment</h1>
	</div>
	{#if roi && !settings}
		<button class="btn" onclick={() => (settings = { opened_on: roi!.opened_on, payback_months: String(roi!.payback_months), staff_per_day: String(roi!.staff_per_day) })}>
			Edit target and assumptions
		</button>
	{/if}
</header>

{#if actionError}<p class="card m-0 text-danger" role="alert">{actionError}</p>{/if}

{#if settings}
	<section class="card">
		<h2 class="card-title m-0 mb-3">Target and assumptions</h2>
		<form class="flex flex-wrap items-end gap-3" onsubmit={saveSettings}>
			<label class="flex flex-col gap-1 text-muted">Opened on <input class="input" type="date" bind:value={settings.opened_on} required /></label>
			<label class="flex flex-col gap-1 text-muted">Pay back within (months) <input class="input w-28 text-right" type="number" min="1" max="120" bind:value={settings.payback_months} required /></label>
			<label class="flex flex-col gap-1 text-muted">Staff clocked in a day <input class="input w-28 text-right" type="number" min="0" max="10" bind:value={settings.staff_per_day} required /></label>
			<button class="btn btn-primary" disabled={busy}>Save</button>
			<button type="button" class="btn" onclick={() => (settings = null)}>Cancel</button>
		</form>
		<p class="m-0 mt-2 text-[13px] text-muted">
			Staff per day is only for forecasts. Real months use the real clock-ins and the commission rule on the Salary screen.
		</p>
	</section>
{/if}

{#if error || (loading && !roi)}
	<Status {loading} {error} />
{:else if roi}
	<section aria-label="Return so far" class="grid grid-cols-[repeat(auto-fit,minmax(200px,1fr))] gap-4">
		<Kpi label="Starting capital" value={rupiah(capital)} note="Opened {longDate(roi.opened_on)}" />
		<Kpi label="Paid back so far" value={rupiah(recovered)} note="{Math.round(progress)}% of the capital, {roi.days_open} days open" />
		<Kpi label="Still to pay back" value={rupiah(remaining)} note={roiPct == null ? '' : `ROI so far ${roiPct}%`} />
		<Kpi
			label="Payback at the current pace"
			value={!enoughData ? 'Too early' : paybackDate ? monthName(paybackDate) : 'Not yet'}
			note={!enoughData
				? `${roi.recent.sales_days} of ${MIN_DAYS} days of sales needed`
				: paybackDate
					? `${rupiah(Math.round(pace * DAYS_PER_MONTH))} net profit a month`
					: 'Net profit is not positive yet'}
		/>
	</section>

	<section class="card">
		<div class="flex flex-wrap items-baseline justify-between gap-2">
			<h2 class="card-title m-0">Paid back</h2>
			<div class="num text-muted">{rupiah(recovered)} of {rupiah(capital)}</div>
		</div>
		<div class="mt-3 h-4 rounded-full bg-mist-soft" role="progressbar" aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(progress)} aria-label="Capital paid back">
			<div class="h-4 rounded-full bg-forest" style:width="{progress}%" style:min-width={progress > 0 ? '8px' : '0'}></div>
		</div>
		<p class="m-0 mt-2 text-muted">Net profit since opening, after HPP, staff and monthly costs. {recovered < 0 ? 'It is negative so far, so nothing is paid back yet.' : ''}</p>
	</section>

	{#if goal}
		<section class="card">
			<h2 class="card-title m-0">Your target: pay back within {goal.months} months</h2>
			{#if goal.passed}
				<p class="m-0 mt-2 text-danger">The target date, {longDate(goal.by)}, has passed. Set a new target.</p>
			{:else}
				<div class="mt-1 text-muted">By {longDate(goal.by)}.</div>
				<div class="mt-4 grid grid-cols-[repeat(auto-fit,minmax(200px,1fr))] gap-4">
					<div class="rounded-xl bg-mist-soft p-4">
						<div class="text-muted">Net profit needed</div>
						<div class="num mt-1 text-2xl leading-8 font-bold whitespace-nowrap">{rupiah(Math.round(goal.perMonth))}</div>
						<div class="text-[13px] text-muted">a month from now on</div>
					</div>
					<div class="rounded-xl bg-mist-soft p-4">
						<div class="text-muted">Cups needed</div>
						<div class="num mt-1 text-2xl leading-8 font-bold">{goal.cups ?? '–'} a day</div>
						<div class="text-[13px] text-muted">at today's margin per cup</div>
					</div>
					<div class="rounded-xl bg-mist-soft p-4">
						<div class="text-muted">You're averaging</div>
						<div class="num mt-1 text-2xl leading-8 font-bold">{cupsNow} a day</div>
						<div class="text-[13px] {goal.cups != null && cupsNow >= goal.cups ? 'font-semibold text-forest' : 'font-semibold text-danger'}">
							{#if goal.cups == null}Can't tell yet{:else if cupsNow >= goal.cups}✓ On track, {cupsNow - goal.cups} above{:else}✗ {goal.cups - cupsNow} cups a day short{/if}
						</div>
					</div>
				</div>
			{/if}
		</section>
	{/if}

	<section class="card">
		<h2 class="card-title m-0">What it takes</h2>
		<div class="text-muted">Cups a day needed from today, for each payback period counted from opening.</div>
		<div class="mt-3 overflow-x-auto">
			<table class="num w-full min-w-[520px] border-collapse text-right">
				<thead>
					<tr>
						<th scope="col" class="th pl-0 text-left">Pay back within</th>
						<th scope="col" class="th text-left">By</th>
						<th scope="col" class="th">Net profit a month</th>
						<th scope="col" class="th pr-0">Cups a day</th>
					</tr>
				</thead>
				<tbody>
					{#each options as o (o.months)}
						<tr class={o.months === roi.payback_months ? 'bg-mist-soft font-semibold' : ''}>
							<th scope="row" class="td pl-0 text-left font-normal">{o.months} months{o.months === roi.payback_months ? ' (your target)' : ''}</th>
							<td class="td text-left">{monthName(o.by)}</td>
							<td class="td">{o.passed ? '–' : rupiah(Math.round(o.perMonth))}</td>
							<td class="td pr-0">{o.passed ? 'Passed' : (o.cups ?? '–')}</td>
						</tr>
					{/each}
					<tr>
						<th scope="row" class="td pl-0 text-left font-normal">Break even only</th>
						<td class="td text-left text-muted">No payback</td>
						<td class="td">{rupiah(0)}</td>
						<td class="td pr-0">{breakEven ?? '–'}</td>
					</tr>
				</tbody>
			</table>
		</div>
		<p class="m-0 mt-3 text-[13px] text-muted">
			Assumes the last 30 days' gross margin of {margin == null ? '–' : rupiah(Math.round(margin))} a cup, {rupiah(Math.round(fixedPerDay(roi) * DAYS_PER_MONTH))}
			a month in base salaries and monthly costs, and commission of {rupiah(roi.rule?.rate_per_cup ?? 0)} a cup from cup
			{(roi.rule?.threshold_cups ?? 0) + 1}{roi.rule?.split
				? `, shared by ${roi.staff_per_day} staff a day`
				: ` for each of ${roi.staff_per_day} staff a day`}.
		</p>
	</section>

	<div class="flex flex-wrap gap-4">
		<section class="card min-w-0 flex-[1_1_360px]">
			<div class="flex flex-wrap items-baseline justify-between gap-2">
				<h2 class="card-title m-0">Starting capital</h2>
				{#if !editing}<button class="min-h-11 px-1 text-forest underline" onclick={() => (editing = { id: null, name: '', amount: '' })}>Add a part</button>{/if}
			</div>
			<table class="num mt-2 w-full border-collapse text-right">
				<tbody>
					{#each roi.capital as c (c.id)}
						<tr>
							<th scope="row" class="td pl-0 text-left font-normal">{c.name}</th>
							<td class="td">{rupiah(c.amount)}</td>
							<td class="td pr-0 whitespace-nowrap">
								{#if removing === c.id}
									<button class="btn" disabled={busy} onclick={() => act(async () => { await rpc('capital_item_delete', { p_outlet: outlets.code, p_id: c.id }); removing = null; })}>Remove</button>
									<button class="btn" onclick={() => (removing = null)}>Keep</button>
								{:else}
									<button class="min-h-11 px-1 text-forest underline" onclick={() => (editing = { id: c.id, name: c.name, amount: String(c.amount) })}>Edit</button>
									<button class="min-h-11 px-1 text-forest underline" onclick={() => (removing = c.id)}>Remove</button>
								{/if}
							</td>
						</tr>
					{/each}
					<tr class="border-t-2 border-ink">
						<th scope="row" class="py-2.5 text-left font-bold">Total</th>
						<td class="px-2 py-2.5 font-bold">{rupiah(capital)}</td>
						<td></td>
					</tr>
				</tbody>
			</table>
			{#if editing}
				<form class="mt-3 flex flex-wrap items-end gap-3" onsubmit={saveItem}>
					<label class="flex flex-col gap-1 text-muted">Part <input class="input w-48" bind:value={editing.name} placeholder="Equipment" required /></label>
					<label class="flex flex-col gap-1 text-muted">Amount <input class="input w-36 text-right" inputmode="numeric" bind:value={editing.amount} required /></label>
					<button class="btn btn-primary" disabled={busy}>Save</button>
					<button type="button" class="btn" onclick={() => (editing = null)}>Cancel</button>
				</form>
			{/if}
			<p class="m-0 mt-3 text-[13px] text-muted">Split it into equipment, renovation, first stock and so on whenever you like; the total updates everywhere.</p>
		</section>

		<section class="card min-w-0 flex-[1_1_360px]">
			<h2 class="card-title m-0">Paid back by month</h2>
			<table class="num mt-2 w-full border-collapse text-right">
				<thead>
					<tr>
						<th scope="col" class="th pl-0 text-left">Month</th>
						<th scope="col" class="th">Net profit</th>
						<th scope="col" class="th">Since opening</th>
						<th scope="col" class="th pr-0">Of capital</th>
					</tr>
				</thead>
				<tbody>
					{#each cumulative as m (m.month)}
						<tr>
							<td class="td pl-0 text-left"><a class="text-forest underline" href="/profit?month={m.month.slice(0, 7)}">{monthName(m.month)}</a></td>
							<td class="td {Number(m.net) < 0 ? 'text-danger' : ''}">{rupiah(m.net)}</td>
							<td class="td">{rupiah(m.total)}</td>
							<td class="td pr-0">{capital ? `${Math.round((m.total / capital) * 100)}%` : '–'}</td>
						</tr>
					{:else}
						<tr><td colspan="4" class="td pl-0 text-left text-muted">No days counted yet.</td></tr>
					{/each}
				</tbody>
			</table>
		</section>
	</div>
{/if}
