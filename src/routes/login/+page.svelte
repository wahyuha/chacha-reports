<script lang="ts">
	import { goto } from '$app/navigation';
	import { auth } from '$lib/auth.svelte';
	import AuthCard from '$lib/components/AuthCard.svelte';
	import { supabase } from '$lib/supabase';

	let email = $state('');
	let password = $state('');
	let busy = $state(false);
	let error = $state('');
	let notice = $state('');
	let forgot = $state(false);

	$effect(() => {
		if (auth.ready && auth.session && !auth.recovering) goto('/');
	});

	async function signIn(e: SubmitEvent) {
		e.preventDefault();
		busy = true;
		error = '';
		const result = await supabase.auth.signInWithPassword({ email: email.trim(), password });
		busy = false;
		if (result.error) {
			error = /invalid/i.test(result.error.message) ? 'Wrong email or password.' : result.error.message;
		}
	}

	async function sendReset(e: SubmitEvent) {
		e.preventDefault();
		busy = true;
		error = '';
		const result = await supabase.auth.resetPasswordForEmail(email.trim(), {
			redirectTo: `${location.origin}/set-password`
		});
		busy = false;
		if (result.error) error = result.error.message;
		else notice = 'If that email has access, a reset link is on its way.';
	}
</script>

<svelte:head><title>Sign in · Chacha Reports</title></svelte:head>

<AuthCard title={forgot ? 'Reset password' : 'Sign in'}>
	<form class="flex flex-col gap-4" onsubmit={forgot ? sendReset : signIn}>
		<label class="flex flex-col gap-1 font-semibold">
			Email
			<input class="input" type="email" autocomplete="username" required bind:value={email} />
		</label>
		{#if !forgot}
			<label class="flex flex-col gap-1 font-semibold">
				Password
				<input class="input" type="password" autocomplete="current-password" required bind:value={password} />
			</label>
		{/if}
		{#if error}<p class="m-0 text-danger" role="alert">{error}</p>{/if}
		{#if notice}<p class="m-0 text-forest" role="status">{notice}</p>{/if}
		<button class="btn btn-primary" disabled={busy}>
			{busy ? 'Please wait…' : forgot ? 'Send reset link' : 'Sign in'}
		</button>
	</form>
	<button
		class="min-h-11 self-center text-forest underline"
		onclick={() => {
			forgot = !forgot;
			error = '';
			notice = '';
		}}
	>
		{forgot ? 'Back to sign in' : 'Forgot password?'}
	</button>
	<p class="m-0 border-t border-stone pt-4 text-center text-muted">Access is by invitation only.</p>
</AuthCard>
