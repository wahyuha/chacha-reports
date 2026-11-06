<script lang="ts">
	import '@fontsource-variable/jost';
	import '@fontsource-variable/plus-jakarta-sans';
	import '../app.css';
	import { onMount } from 'svelte';
	import { auth } from '$lib/auth.svelte';

	let { children } = $props();

	onMount(() => auth.start());
</script>

{@render children()}
