<script lang="ts">
	import { goto } from '$app/navigation';
	import { auth } from '$lib/auth.svelte';
	import Status from '$lib/components/Status.svelte';
	import { dateTime, monthName, rupiah, shortDate, today } from '$lib/format';
	import { outlets } from '$lib/outlet.svelte';
	import { rpc } from '$lib/supabase';

	type Line = {
		staff_code: string;
		staff_name: string;
		days_worked: number;
		base_salary: number;
		commission: number;
		correction: number;
		total: number;
		days: { date: string; cups: number; commission: number }[];
	};
	type Report = {
		month: string;
		status: 'draft' | 'locked';
		locked_at: string | null;
		can_lock: boolean;
		rule: { from: string; threshold_cups: number; rate_per_cup: number; split: boolean } | null;
		outlet_days: { date: string; cups: number; commission: number }[];
		lines: Line[];
	};

	const thisMonth = today().slice(0, 7);
	let month = $state(thisMonth);
	let report = $state<Report | null>(null);
	let loading = $state(true);
	let error = $state('');
	let open = $state<string | null>(null);
	let editing = $state<{ code: string; amount: string } | null>(null);
	let confirming = $state(false);
	let busy = $state(false);
	let actionError = $state('');
	let ruleForm = $state<{ from: string; startCup: string; rate: string; split: boolean } | null>(null);

	$effect(() => {
		if (!auth.isOwner) goto('/');
	});

	async function load() {
		loading = true;
		try {
			report = await rpc<Report>('payroll_month', { p_outlet: outlets.code, p_month: `${month}-01` });
			error = '';
		} catch (e) {
			error = (e as Error).message;
		} finally {
			loading = false;
		}
	}

	$effect(() => {
		void outlets.code;
		void month;
		confirming = false;
		load();
	});

	// People without a base salary only show in months they clocked in or are owed something.
	const lines = $derived(
		(report?.lines ?? []).filter((l) => Number(l.base_salary) || Number(l.days_worked) || Number(l.commission) || Number(l.correction))
	);
	const sum = (key: 'base_salary' | 'commission' | 'correction' | 'total') => lines.reduce((a, l) => a + Number(l[key]), 0);
	const daysWithCommission = $derived((report?.outlet_days ?? []).filter((d) => Number(d.commission) > 0).length);

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

	function saveRule(e: SubmitEvent) {
		e.preventDefault();
		const f = ruleForm!;
		act(async () => {
			await rpc('commission_rule_save', {
				p_outlet: outlets.code,
				p_from: `${f.from}-01`,
				p_threshold: Math.max(0, Number(f.startCup) - 1),
				p_rate: Number(f.rate.replace(/\D/g, '')),
				p_split: f.split
			});
			ruleForm = null;
		});
	}

	function saveSalary(e: SubmitEvent) {
		e.preventDefault();
		const target = editing;
		if (!target) return;
		act(async () => {
			await rpc('set_base_salary', {
				p_outlet: outlets.code,
				p_staff_code: target.code,
				p_amount: Number(target.amount.replace(/\D/g, '')),
				p_from: `${month}-01`
			});
			editing = null;
		});
	}
</script>

<svelte:head><title>Salary and commission · Chacha Reports</title></svelte:head>

<header class="flex flex-wrap items-end justify-between gap-4">
	<div>
		<div class="eyebrow">Owner only</div>
		<h1 class="page-title m-0 mt-1">Salary and commission</h1>
	</div>
	<div class="flex flex-wrap items-center gap-2">
		<label class="flex items-center gap-2 text-muted">Month <input class="input" type="month" bind:value={month} max={thisMonth} /></label>
		{#if report?.can_lock}
			{#if confirming}
				<span>Approve {monthName(report.month)}? It can't be changed afterwards.</span>
				<button class="btn btn-primary" disabled={busy} onclick={() => act(() => rpc('payroll_lock', { p_outlet: outlets.code, p_month: report!.month }))}>Approve and lock</button>
				<button class="btn" onclick={() => (confirming = false)}>Not yet</button>
			{:else}
				<button class="btn btn-primary" onclick={() => (confirming = true)}>Approve and lock</button>
			{/if}
		{/if}
	</div>
</header>

{#if actionError}<p class="card m-0 text-danger" role="alert">{actionError}</p>{/if}

{#if error || (loading && !report)}
	<Status {loading} {error} />
{:else if report}
	<section class="flex flex-wrap items-center justify-between gap-x-8 gap-y-3 rounded-xl bg-mist-soft px-5 py-4">
		<div>
			<div class="eyebrow">Commission rule</div>
			{#if report.rule}
				<div class="mt-1 text-xl leading-7 font-semibold">
					{rupiah(report.rule.rate_per_cup)} per cup from cup {report.rule.threshold_cups + 1},
					{report.rule.split ? 'shared equally by the staff who clock in' : 'for each employee who clocks in'}
				</div>
				<div class="text-[13px] text-muted">
					Since {monthName(report.rule.from)} ·
					<button
						class="min-h-11 text-forest underline"
						onclick={() =>
							(ruleForm = {
								from: month,
								startCup: String(report!.rule!.threshold_cups + 1),
								rate: String(report!.rule!.rate_per_cup),
								split: report!.rule!.split
							})}>Change the rule</button
					>
				</div>
			{:else}
				<div class="mt-1 text-xl leading-7 font-semibold">No rule set for this outlet</div>
			{/if}
		</div>
		<div class="min-w-0 flex-[1_1_320px]">
			The outlet's cups for the day count, cancelled orders excluded.
			{#if report.rule?.split}With two staff on duty, each earns {rupiah(Math.floor(Number(report.rule.rate_per_cup) / 2))} a cup.{:else}Everyone who clocked in earns the full amount.{/if}
			{#if report.status === 'locked'}
				<strong>Approved {dateTime(report.locked_at)}. These amounts are final.</strong>
			{:else if month === thisMonth}
				<strong>This month is still running, so the numbers will grow.</strong>
			{:else}
				<strong>Draft. Approve it once you've checked attendance.</strong>
			{/if}
		</div>
	</section>

	{#if ruleForm}
		<section class="card">
			<h2 class="card-title m-0 mb-3">Commission rule</h2>
			<form class="flex flex-wrap items-end gap-3" onsubmit={saveRule}>
				<label class="flex flex-col gap-1 text-muted">Counted from cup <input class="input w-24 text-right" type="number" min="1" bind:value={ruleForm.startCup} required /></label>
				<label class="flex flex-col gap-1 text-muted">Amount per cup <input class="input w-32 text-right" inputmode="numeric" bind:value={ruleForm.rate} required /></label>
				<fieldset class="m-0 flex flex-col gap-1 border-0 p-0">
					<legend class="mb-1 text-muted">Paid as</legend>
					<label class="flex min-h-11 items-center gap-2"><input type="radio" bind:group={ruleForm.split} value={true} /> Shared equally by the staff who clock in</label>
					<label class="flex min-h-11 items-center gap-2"><input type="radio" bind:group={ruleForm.split} value={false} /> The full amount to each person who clocks in</label>
				</fieldset>
				<label class="flex flex-col gap-1 text-muted">Applies from <input class="input" type="month" bind:value={ruleForm.from} required /></label>
				<button class="btn btn-primary" disabled={busy}>Save</button>
				<button type="button" class="btn" onclick={() => (ruleForm = null)}>Cancel</button>
			</form>
			<p class="m-0 mt-2 text-[13px] text-muted">
				Months already approved keep their rule. A shared amount is split in whole rupiah, rounded down.
			</p>
		</section>
	{/if}

	<section class="card">
		<div class="flex flex-wrap items-baseline justify-between gap-2">
			<h2 class="card-title m-0">{monthName(report.month)}</h2>
			<div class="text-muted">{daysWithCommission} days earned commission at the outlet.</div>
		</div>
		{#if !lines.length}
			<p class="m-0 mt-3 text-muted">No staff for this outlet.</p>
		{:else}
			<div class="mt-3 overflow-x-auto">
				<table class="num w-full min-w-[760px] border-collapse text-right">
					<thead>
						<tr>
							<th scope="col" class="th pl-0 text-left">Employee</th>
							<th scope="col" class="th">Days worked</th>
							<th scope="col" class="th">Base salary</th>
							<th scope="col" class="th">Commission</th>
							<th scope="col" class="th">Corrections</th>
							<th scope="col" class="th pr-0">Take home</th>
						</tr>
					</thead>
					<tbody>
						{#each lines as l (l.staff_code)}
							<tr class={open === l.staff_code ? 'bg-mist-soft' : ''}>
								<th scope="row" class="td pl-0 text-left">
									<button class="min-h-11 font-semibold text-forest underline" aria-expanded={open === l.staff_code} onclick={() => (open = open === l.staff_code ? null : l.staff_code)}>
										{l.staff_name}
									</button>
								</th>
								<td class="td">{l.days_worked}</td>
								<td class="td">
									{#if editing?.code === l.staff_code}
										<form class="flex items-center justify-end gap-2" onsubmit={saveSalary}>
											<label class="sr-only" for="salary-{l.staff_code}">Base salary for {l.staff_name}</label>
											<input id="salary-{l.staff_code}" class="input w-32 text-right" inputmode="numeric" bind:value={editing.amount} required />
											<button class="btn btn-primary" disabled={busy}>Save</button>
											<button type="button" class="btn" onclick={() => (editing = null)}>Cancel</button>
										</form>
									{:else}
										{rupiah(l.base_salary)}
										{#if report.status === 'draft'}
											<button class="ml-1 min-h-11 px-1 text-forest underline" onclick={() => (editing = { code: l.staff_code, amount: String(l.base_salary) })}>Edit</button>
										{/if}
									{/if}
								</td>
								<td class="td">{rupiah(l.commission)}</td>
								<td class="td">{Number(l.correction) ? rupiah(l.correction) : 'None'}</td>
								<td class="td pr-0 font-bold">{rupiah(l.total)}</td>
							</tr>
							{#if open === l.staff_code}
								<tr>
									<td colspan="6" class="border-t border-stone bg-ivory px-3 py-3 text-left">
										{#if !l.days.length}
											<p class="m-0 text-muted">{l.staff_name} didn't clock in this month.</p>
										{:else}
											<table class="num w-full max-w-xl border-collapse text-right">
												<thead><tr><th scope="col" class="th pl-0 text-left">Date</th><th scope="col" class="th">Outlet cups</th><th scope="col" class="th">From cup {(report.rule?.threshold_cups ?? 20) + 1}</th><th scope="col" class="th pr-0">{report.rule?.split ? 'Their share' : 'Commission'}</th></tr></thead>
												<tbody>
													{#each l.days as d}
														<tr>
															<td class="td pl-0 text-left">{shortDate(d.date)}</td>
															<td class="td">{d.cups}</td>
															<td class="td">{Math.max(0, Number(d.cups) - (report.rule?.threshold_cups ?? 20))}</td>
															<td class="td pr-0 font-semibold">{rupiah(d.commission)}</td>
														</tr>
													{/each}
												</tbody>
											</table>
										{/if}
									</td>
								</tr>
							{/if}
						{/each}
						<tr class="border-t-2 border-ink">
							<th scope="row" class="py-2.5 text-left font-bold">Total</th>
							<td></td>
							<td class="px-2 py-2.5 font-bold">{rupiah(sum('base_salary'))}</td>
							<td class="px-2 py-2.5 font-bold">{rupiah(sum('commission'))}</td>
							<td class="px-2 py-2.5 font-bold">{rupiah(sum('correction'))}</td>
							<td class="py-2.5 font-bold">{rupiah(sum('total'))}</td>
						</tr>
					</tbody>
				</table>
			</div>
			<p class="m-0 mt-3 text-muted">
				Select a name to see each day's commission. A new base salary applies from the month shown onward.
				Corrections come from orders that synced or were cancelled after an earlier month was approved.
			</p>
		{/if}
	</section>
{/if}
