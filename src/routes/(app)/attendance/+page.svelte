<script lang="ts">
	import { goto } from '$app/navigation';
	import { auth } from '$lib/auth.svelte';
	import Status from '$lib/components/Status.svelte';
	import { clock, longDate, monthName, shortDate, today } from '$lib/format';
	import { outlets } from '$lib/outlet.svelte';
	import { rpc } from '$lib/supabase';

	type Row = {
		id: string;
		staff_code: string;
		staff_name: string;
		date: string;
		clock_in_at: string;
		clock_out_at: string | null;
		source: 'tablet' | 'owner';
		edited: boolean;
	};
	type Report = {
		month: string;
		today: string;
		staff: { code: string; name: string }[];
		rows: Row[];
		missing_clock_out: Omit<Row, 'clock_out_at' | 'source' | 'edited'>[];
	};
	type Draft = { id: string | null; staff_code: string; date: string; clock_in: string; clock_out: string };

	let month = $state(today().slice(0, 7));
	let report = $state<Report | null>(null);
	let loading = $state(true);
	let error = $state('');
	let draft = $state<Draft | null>(null);
	let saving = $state(false);
	let formError = $state('');

	$effect(() => {
		if (!auth.isOwner) goto('/');
	});

	async function load() {
		loading = true;
		try {
			report = await rpc<Report>('attendance_month', { p_outlet: outlets.code, p_month: `${month}-01` });
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
		load();
	});

	const days = $derived.by(() => {
		const [y, m] = month.split('-').map(Number);
		const count = new Date(Date.UTC(y, m, 0)).getUTCDate();
		return Array.from({ length: count }, (_, i) => `${month}-${String(i + 1).padStart(2, '0')}`);
	});
	const worked = (code: string, date: string) => report?.rows.filter((r) => r.staff_code === code && r.date === date) ?? [];
	const daysWorked = (code: string) => new Set(report?.rows.filter((r) => r.staff_code === code).map((r) => r.date)).size;
	const hours = (r: { clock_in_at: string; clock_out_at: string | null }) => {
		if (!r.clock_out_at) return null;
		const min = Math.round((Date.parse(r.clock_out_at) - Date.parse(r.clock_in_at)) / 60000);
		return `${Math.floor(min / 60)}h ${String(min % 60).padStart(2, '0')}m`;
	};
	const todayRows = $derived(report?.rows.filter((r) => r.date === report?.today) ?? []);

	/** Times are entered in outlet time (WIB). */
	const toIso = (date: string, time: string) => (time ? `${date}T${time}:00+07:00` : null);

	function edit(r: Row | Report['missing_clock_out'][number]) {
		formError = '';
		draft = {
			id: r.id,
			staff_code: r.staff_code,
			date: r.date,
			clock_in: clock(r.clock_in_at),
			clock_out: 'clock_out_at' in r ? clock(r.clock_out_at) : ''
		};
	}

	function add() {
		formError = '';
		draft = { id: null, staff_code: report?.staff[0]?.code ?? '', date: today(), clock_in: '', clock_out: '' };
	}

	async function save(e: SubmitEvent) {
		e.preventDefault();
		if (!draft) return;
		saving = true;
		formError = '';
		try {
			// A clock-out earlier than the clock-in means the shift ran past midnight.
			let out = toIso(draft.date, draft.clock_out);
			const inAt = toIso(draft.date, draft.clock_in)!;
			if (out && Date.parse(out) < Date.parse(inAt)) out = new Date(Date.parse(out) + 86400000).toISOString();
			await rpc('attendance_save', {
				p_outlet: outlets.code,
				p_id: draft.id,
				p_staff_code: draft.staff_code,
				p_date: draft.date,
				p_clock_in: inAt,
				p_clock_out: out
			});
			draft = null;
			await load();
		} catch (err) {
			formError = (err as Error).message;
		} finally {
			saving = false;
		}
	}

	async function remove() {
		if (!draft?.id) return;
		saving = true;
		try {
			await rpc('attendance_delete', { p_outlet: outlets.code, p_id: draft.id });
			draft = null;
			await load();
		} catch (err) {
			formError = (err as Error).message;
		} finally {
			saving = false;
		}
	}
</script>

<svelte:head><title>Attendance · Chacha Reports</title></svelte:head>

<header class="flex flex-wrap items-end justify-between gap-4">
	<div>
		<div class="eyebrow">Owner only</div>
		<h1 class="page-title m-0 mt-1">Attendance</h1>
	</div>
	<div class="flex flex-wrap items-center gap-2">
		<label class="flex items-center gap-2 text-muted">Month <input class="input" type="month" bind:value={month} max={today().slice(0, 7)} /></label>
		<button class="btn" onclick={add} disabled={!report}>Add attendance</button>
	</div>
</header>

{#if draft}
	<section class="card" aria-label="Edit attendance">
		<h2 class="card-title m-0 mb-3">{draft.id ? 'Correct attendance' : 'Add attendance'}</h2>
		<form class="flex flex-wrap items-end gap-3" onsubmit={save}>
			<label class="flex flex-col gap-1 font-semibold">
				Staff
				<select class="input" bind:value={draft.staff_code} required>
					{#each report?.staff ?? [] as s}<option value={s.code}>{s.name}</option>{/each}
				</select>
			</label>
			<label class="flex flex-col gap-1 font-semibold">Date <input class="input" type="date" bind:value={draft.date} max={today()} required /></label>
			<label class="flex flex-col gap-1 font-semibold">Clock in <input class="input" type="time" bind:value={draft.clock_in} required /></label>
			<label class="flex flex-col gap-1 font-semibold">Clock out <input class="input" type="time" bind:value={draft.clock_out} /></label>
			<button class="btn btn-primary" disabled={saving}>Save</button>
			<button type="button" class="btn" onclick={() => (draft = null)}>Cancel</button>
			{#if draft.id}<button type="button" class="btn btn-danger" disabled={saving} onclick={remove}>Delete</button>{/if}
		</form>
		<p class="mt-3 mb-0 text-muted">Times are outlet time (WIB). Leave clock out empty if you don't know it; a clock-in alone earns that day's commission.</p>
		{#if formError}<p class="mt-3 mb-0 text-danger" role="alert">{formError}</p>{/if}
	</section>
{/if}

{#if error || (loading && !report)}
	<Status {loading} {error} />
{:else if report}
	<div class="flex flex-wrap gap-4">
		<section class="card min-w-0 flex-[2_1_480px]">
			<h2 class="card-title m-0 mb-3">Today, {shortDate(report.today)}</h2>
			{#if !todayRows.length}
				<p class="m-0 text-muted">Nobody has clocked in yet today.</p>
			{:else}
				<div class="overflow-x-auto">
					<table class="num w-full min-w-[440px] border-collapse text-left">
						<thead><tr><th scope="col" class="th pl-0">Name</th><th scope="col" class="th">Clock in</th><th scope="col" class="th">Clock out</th><th scope="col" class="th text-right">Hours</th></tr></thead>
						<tbody>
							{#each todayRows as r}
								<tr>
									<td class="td pl-0 font-semibold">{r.staff_name}</td>
									<td class="td">{clock(r.clock_in_at)}</td>
									<td class="td">{r.clock_out_at ? clock(r.clock_out_at) : 'Working'}</td>
									<td class="td text-right">{hours(r) ?? 'Open'}</td>
								</tr>
							{/each}
						</tbody>
					</table>
				</div>
			{/if}
		</section>

		<section class="card min-w-0 flex-[1_1_300px]">
			<h2 class="card-title m-0 mb-3">Needs review</h2>
			{#if !report.missing_clock_out.length}
				<p class="m-0 text-muted">Nothing to review.</p>
			{/if}
			{#each report.missing_clock_out as r}
				<div class="border-t border-stone py-3">
					<div class="font-semibold">{r.staff_name}, {shortDate(r.date)}</div>
					<div class="text-muted">Clocked in at {clock(r.clock_in_at)}, no clock-out. Commission still counts; this only affects hours.</div>
					<button class="btn mt-2" onclick={() => edit(r)}>Fix time</button>
				</div>
			{/each}
		</section>
	</div>

	<section class="card">
		<div class="flex flex-wrap items-baseline justify-between gap-2">
			<h2 class="card-title m-0">{monthName(`${month}-01`)}</h2>
			<div class="text-muted">A green day means clocked in. Select a day to correct it.</div>
		</div>
		<div class="mt-3 overflow-x-auto">
			<table class="num w-full min-w-[960px] table-fixed border-separate border-spacing-0.5">
				<thead>
					<tr>
						<th scope="col" class="w-20 text-left font-semibold text-muted">Name</th>
						{#each days as d}<th scope="col" class="text-xs font-semibold text-muted">{Number(d.slice(8))}</th>{/each}
						<th scope="col" class="w-12 text-xs font-semibold text-muted">Days</th>
					</tr>
				</thead>
				<tbody>
					{#each report.staff as s}
						<tr>
							<th scope="row" class="truncate text-left font-semibold">{s.name}</th>
							{#each days as d}
								{@const rows = worked(s.code, d)}
								<td class="h-9 p-0 text-center">
									{#if rows.length}
										<button
											class="h-9 w-full rounded bg-forest text-xs font-bold text-white"
											title="{s.name}, {longDate(d)}: in {clock(rows[0].clock_in_at)}{rows[0].clock_out_at ? `, out ${clock(rows[0].clock_out_at)}` : ', no clock-out'}"
											aria-label="{s.name}, {longDate(d)}, clocked in at {clock(rows[0].clock_in_at)}"
											onclick={() => edit(rows[0])}
										>✓</button>
									{/if}
								</td>
							{/each}
							<td class="text-center font-bold">{daysWorked(s.code)}</td>
						</tr>
					{/each}
				</tbody>
			</table>
		</div>
		<p class="mt-3 mb-0 text-muted">Lateness and absence don't reduce salary. Attendance only decides who earns each day's commission.</p>
	</section>
{/if}
