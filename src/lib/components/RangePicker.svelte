<script lang="ts">
	import { addDays, today } from '$lib/format';

	let {
		from = $bindable(),
		to = $bindable(),
		presets = [7, 14, 30, 90],
		singleDays = false
	}: { from: string; to: string; presets?: number[]; singleDays?: boolean } = $props();

	let custom = $state(false);
	const active = (days: number) => !custom && to === today() && from === addDays(to, 1 - days);
	const activeDay = (back: number) => !custom && from === to && to === addDays(today(), -back);

	function pick(days: number) {
		custom = false;
		to = today();
		from = addDays(to, 1 - days);
	}

	function pickDay(back: number) {
		custom = false;
		to = addDays(today(), -back);
		from = to;
	}
</script>

<div class="flex flex-wrap items-center gap-2">
	{#if singleDays}
		{#each [['Today', 0], ['Yesterday', 1]] as const as [label, back]}
			<button class="btn {activeDay(back) ? 'btn-primary' : ''}" aria-pressed={activeDay(back)} onclick={() => pickDay(back)}>
				{label}
			</button>
		{/each}
	{/if}
	{#each presets as days}
		<button class="btn {active(days) ? 'btn-primary' : ''}" aria-pressed={active(days)} onclick={() => pick(days)}>
			{days} days
		</button>
	{/each}
	<button class="btn {custom ? 'btn-primary' : ''}" aria-pressed={custom} onclick={() => (custom = true)}>Custom</button>
	{#if custom}
		<label class="flex items-center gap-2 text-muted">From <input class="input" type="date" bind:value={from} max={to} /></label>
		<label class="flex items-center gap-2 text-muted">To <input class="input" type="date" bind:value={to} min={from} max={today()} /></label>
	{/if}
</div>
