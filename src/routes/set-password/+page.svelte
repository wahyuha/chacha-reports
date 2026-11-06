<script lang="ts">
	import { goto } from '$app/navigation';
	import { auth } from '$lib/auth.svelte';
	import AuthCard from '$lib/components/AuthCard.svelte';
	import { rpc, supabase } from '$lib/supabase';

	const MIN_LENGTH = 10;

	let password = $state('');
	let confirm = $state('');
	let busy = $state(false);
	let error = $state('');

	$effect(() => {
		if (auth.ready && !auth.session) goto('/login');
	});

	async function save(e: SubmitEvent) {
		e.preventDefault();
		error = '';
		if (password.length < MIN_LENGTH) {
			error = `Use at least ${MIN_LENGTH} characters.`;
			return;
		}
		if (password !== confirm) {
			error = "The two passwords don't match.";
			return;
		}
		busy = true;
		const result = await supabase.auth.updateUser({ password });
		if (result.error) {
			busy = false;
			error = /different/i.test(result.error.message)
				? 'Choose a password different from your current one.'
				: result.error.message;
			return;
		}
		await rpc('password_changed');
		auth.recovering = false;
		await auth.load();
		busy = false;
		goto('/');
	}
</script>

<svelte:head><title>Set password · Chacha Reports</title></svelte:head>

<AuthCard title="Set your password" intro="Choose a password only you know. You'll use it to sign in from now on.">
	{#if !auth.ready}
		<p class="m-0 text-muted" role="status">Loading…</p>
	{:else if auth.session}
		<form class="flex flex-col gap-4" onsubmit={save}>
			<label class="flex flex-col gap-1 font-semibold">
				Email
				<input class="input bg-ivory text-muted" type="email" readonly autocomplete="username" value={auth.session.user.email} />
			</label>
			<label class="flex flex-col gap-1 font-semibold">
				New password
				<input class="input" type="password" autocomplete="new-password" required bind:value={password} />
			</label>
			<label class="flex flex-col gap-1 font-semibold">
				Confirm password
				<input class="input" type="password" autocomplete="new-password" required bind:value={confirm} />
			</label>
			<p class="m-0 text-muted">At least {MIN_LENGTH} characters.</p>
			{#if error}<p class="m-0 text-danger" role="alert">{error}</p>{/if}
			<button class="btn btn-primary" disabled={busy}>{busy ? 'Saving…' : 'Save and continue'}</button>
		</form>
	{/if}
</AuthCard>
