<script lang="ts">
	let { loading = false, error = '', empty = '' }: { loading?: boolean; error?: string; empty?: string } = $props();
</script>

{#if loading}
	<p class="card text-muted" role="status">Loading…</p>
{:else if error}
	<p class="card text-danger" role="alert">Couldn't load this report: {error}</p>
{:else if empty}
	<p class="card text-muted">{empty}</p>
{/if}
