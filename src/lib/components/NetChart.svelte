<script lang="ts">
	// Bars above or below a zero line: profit days up in forest, loss days down in red.
	export type NetBar = { label: string; value: number; tip: string };

	let { bars, title }: { bars: NetBar[]; title: string } = $props();

	const top = $derived(Math.max(0, ...bars.map((b) => b.value)));
	const bottom = $derived(Math.max(0, ...bars.map((b) => -b.value)));
	const span = $derived(Math.max(1, top + bottom));
	const zero = $derived(`${(top / span) * 100}%`); // distance of the zero line from the top
</script>

<figure class="m-0" role="img" aria-label={title}>
	<div class="relative flex h-56 gap-1 sm:gap-1.5">
		<div class="absolute inset-x-0 border-t border-ink" style:top={zero}></div>
		{#each bars as bar}
			<div class="group relative h-full min-w-0 flex-1">
				<div
					class="absolute left-1/2 w-full max-w-11 -translate-x-1/2 {bar.value >= 0 ? 'rounded-t bg-forest' : 'rounded-b bg-danger'}"
					style:top={bar.value >= 0 ? `calc(${zero} - ${(bar.value / span) * 100}%)` : zero}
					style:height="{(Math.abs(bar.value) / span) * 100}%"
					style:min-height={bar.value ? '2px' : '0'}
				></div>
				<div
					class="pointer-events-none absolute top-0 left-1/2 z-10 hidden w-max max-w-56 -translate-x-1/2 rounded-md bg-pine px-2 py-1 text-xs text-white group-hover:block"
				>
					{bar.tip}
				</div>
			</div>
		{/each}
	</div>
	<div class="mt-1.5 flex gap-1 sm:gap-1.5">
		{#each bars as bar}
			<div class="min-w-0 flex-1 text-center text-xs leading-4 text-muted">{bar.label}</div>
		{/each}
	</div>
</figure>
