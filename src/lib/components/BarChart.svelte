<script lang="ts">
	export type Bar = { label: string; sublabel?: string; value: number; tip: string; highlight?: boolean };

	let {
		bars,
		title,
		format = (v: number) => String(v),
		reference = null
	}: {
		bars: Bar[];
		title: string;
		format?: (v: number) => string;
		reference?: number | null;
	} = $props();

	const max = $derived(Math.max(1, ...bars.map((b) => b.value)));
	const height = (v: number) => `${(v / max) * 88}%`;
</script>

<figure class="m-0" role="img" aria-label={title}>
	<div class="relative flex h-60 items-end gap-1 border-b border-stone sm:gap-1.5">
		{#if reference}
			<div class="absolute inset-x-0 border-t-2 border-dashed border-muted" style:bottom={height(reference)}></div>
		{/if}
		{#each bars as bar}
			<div class="group relative flex h-full min-w-0 flex-1 flex-col items-center justify-end">
				{#if bar.highlight && bar.value > 0}
					<div class="num text-xs font-semibold whitespace-nowrap">{format(bar.value)}</div>
				{/if}
				<div
					class="w-full max-w-11 rounded-t {bar.highlight ? 'bg-brass' : 'bg-forest'}"
					style:height={height(bar.value)}
					style:min-height={bar.value > 0 ? '2px' : '0'}
				></div>
				<div
					class="pointer-events-none absolute bottom-full left-1/2 z-10 hidden w-max max-w-52 -translate-x-1/2 rounded-md bg-pine px-2 py-1 text-xs text-white group-hover:block"
				>
					{bar.tip}
				</div>
			</div>
		{/each}
	</div>
	<div class="mt-1.5 flex gap-1 sm:gap-1.5">
		{#each bars as bar}
			<div class="min-w-0 flex-1 text-center text-xs leading-4 text-muted">
				{bar.label}{#if bar.sublabel}<br />{bar.sublabel}{/if}
			</div>
		{/each}
	</div>
</figure>
