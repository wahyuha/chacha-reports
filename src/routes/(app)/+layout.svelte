<script lang="ts">
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import { auth } from '$lib/auth.svelte';
	import { outlets } from '$lib/outlet.svelte';

	let { children } = $props();

	const sections = $derived([
		{
			title: '',
			links: [
				{ href: '/', label: 'Daily' },
				{ href: '/sales', label: 'Sales' },
				{ href: '/products', label: 'Best sellers' },
				{ href: '/time', label: 'By time' }
			]
		},
		...(auth.isOwner
			? [
					{
						title: 'Team',
						links: [
							{ href: '/attendance', label: 'Attendance' },
							{ href: '/payroll', label: 'Salary and commission' }
						]
					},
					{ title: 'Account', links: [{ href: '/users', label: 'Users' }] }
				]
			: [])
	]);

	const allowed = $derived(auth.ready && !!auth.session && !!auth.access && !auth.access.must_change_password && !auth.recovering);

	$effect(() => {
		if (!auth.ready) return;
		if (!auth.session) goto('/login');
		else if (auth.recovering || auth.access?.must_change_password) goto('/set-password');
	});

	$effect(() => {
		if (allowed) outlets.load().catch(() => {});
	});
</script>

{#if !auth.ready}
	<p class="p-8 text-muted" role="status">Loading…</p>
{:else if auth.failed}
	<div class="p-8">
		<p class="text-danger" role="alert">Couldn't check your access. Check your connection and try again.</p>
		<button class="btn mt-4" onclick={() => auth.load()}>Try again</button>
	</div>
{:else if auth.session && !auth.access}
	<div class="p-8">
		<p>This account doesn't have access to Chacha Reports. Ask the owner for an invitation.</p>
		<button class="btn mt-4" onclick={() => auth.signOut()}>Sign out</button>
	</div>
{:else if allowed}
	<div class="flex min-h-dvh flex-col md:flex-row">
		<nav aria-label="Reports" class="flex shrink-0 flex-col gap-1 bg-forest px-4 py-6 text-white md:w-56">
			<div class="px-3 pb-5 font-display text-xs leading-4 font-medium tracking-[0.32em]">REPORTS</div>
			{#each sections as section}
				{#if section.title}<div class="px-3 pt-5 pb-1 text-xs text-mist">{section.title}</div>{/if}
				{#each section.links as link}
					{@const current = page.url.pathname === link.href}
					<a
						href={link.href}
						aria-current={current ? 'page' : undefined}
						class="flex min-h-11 items-center rounded-xl px-3 text-white no-underline {current ? 'bg-pine font-semibold' : ''}"
					>
						{link.label}
					</a>
				{/each}
			{/each}
			<div class="mt-5 border-t border-white/20 px-3 pt-3 text-xs break-all text-mist md:mt-auto">{auth.access?.email}</div>
			<button class="flex min-h-11 items-center rounded-xl px-3 text-left text-white" onclick={() => auth.signOut()}>Sign out</button>
		</nav>
		<main class="flex min-w-0 flex-1 flex-col gap-6 p-4 sm:p-8">
			{@render children()}
		</main>
	</div>
{/if}
