<script lang="ts">
	import { addDays, today } from '$lib/format';

	let {
		from = $bindable(),
		to = $bindable(),
		presets = [7, 14, 30, 90]
	}: { from: string; to: string; presets?: number[] } = $props();

	let custom = $state(false);
	const active = (days: number) => !custom && to === today() && from === addDays(to, 1 - days);

	function pick(days: number) {
		custom = false;
		to = today();
		from = addDays(to, 1 - days);
	}
</script>

<div class="flex flex-wrap items-center gap-2">
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
