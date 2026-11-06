<script lang="ts">
	import type { Snippet } from 'svelte';

	let { title, intro = '', children }: { title: string; intro?: string; children: Snippet } = $props();
</script>

<div class="flex min-h-dvh items-center justify-center bg-forest p-4">
	<main class="flex w-full max-w-[420px] flex-col gap-4 rounded-3xl bg-raised p-8">
		<div>
			<div class="eyebrow">Reports</div>
			<h1 class="mt-2 font-display text-[32px] leading-10 font-medium text-forest">{title}</h1>
			{#if intro}<p class="mt-2 text-muted">{intro}</p>{/if}
		</div>
		{@render children()}
	</main>
</div>
