<script lang="ts">
	import { goto } from '$app/navigation';
	import { auth } from '$lib/auth.svelte';
	import Status from '$lib/components/Status.svelte';
	import { dateTime } from '$lib/format';
	import { manageUsers, rpc } from '$lib/supabase';

	type User = {
		user_id: string;
		email: string;
		role: 'owner' | 'viewer';
		invited: boolean;
		last_sign_in_at: string | null;
		is_me: boolean;
	};

	let users = $state<User[] | null>(null);
	let loading = $state(true);
	let error = $state('');
	let email = $state('');
	let role = $state<'viewer' | 'owner'>('viewer');
	let busy = $state(false);
	let message = $state('');
	let failure = $state('');
	let confirming = $state<string | null>(null);

	$effect(() => {
		if (!auth.isOwner) goto('/');
	});

	async function load() {
		try {
			users = await rpc<User[]>('list_dashboard_users');
			error = '';
		} catch (e) {
			error = (e as Error).message;
		} finally {
			loading = false;
		}
	}
	load();

	async function run(action: () => Promise<void>, done: string) {
		busy = true;
		message = '';
		failure = '';
		try {
			await action();
			message = done;
			await load();
		} catch (e) {
			failure = (e as Error).message;
		} finally {
			busy = false;
			confirming = null;
		}
	}

	function invite(e: SubmitEvent) {
		e.preventDefault();
		const address = email.trim();
		run(async () => {
			await manageUsers({ action: 'invite', email: address, role });
			email = '';
		}, `Invitation sent to ${address}.`);
	}
</script>

<svelte:head><title>Users · Chacha Reports</title></svelte:head>

<header>
	<div class="eyebrow">Owner only</div>
	<h1 class="page-title m-0 mt-1">Users</h1>
</header>

<section class="card">
	<h2 class="card-title m-0 mb-3">Invite someone</h2>
	<form class="flex flex-wrap items-end gap-3" onsubmit={invite}>
		<label class="flex flex-[3_1_260px] flex-col gap-1 font-semibold">
			Email
			<input class="input" type="email" required bind:value={email} />
		</label>
		<label class="flex flex-[1_1_160px] flex-col gap-1 font-semibold">
			Role
			<select class="input" bind:value={role}>
				<option value="viewer">Viewer</option>
				<option value="owner">Owner</option>
			</select>
		</label>
		<button class="btn btn-primary" disabled={busy}>Send invitation</button>
	</form>
	<p class="mt-3 mb-0 text-muted">Viewer sees sales reports only. Owner also sees attendance, salary and users.</p>
	{#if message}<p class="mt-3 mb-0 text-forest" role="status">{message}</p>{/if}
	{#if failure}<p class="mt-3 mb-0 text-danger" role="alert">{failure}</p>{/if}
</section>

{#if error || (loading && !users)}
	<Status {loading} {error} />
{:else if users}
	<section class="card">
		<h2 class="card-title m-0 mb-3">People with access</h2>
		<div class="overflow-x-auto">
			<table class="w-full min-w-[680px] border-collapse text-left">
				<thead>
					<tr>
						<th scope="col" class="th">Email</th>
						<th scope="col" class="th">Role</th>
						<th scope="col" class="th">Status</th>
						<th scope="col" class="th">Last sign-in</th>
						<th scope="col" class="th text-right">Action</th>
					</tr>
				</thead>
				<tbody>
					{#each users as u (u.user_id)}
						<tr>
							<td class="td font-semibold">{u.email}</td>
							<td class="td capitalize">{u.role}</td>
							<td class="td">{u.invited ? 'Invited' : 'Active'}</td>
							<td class="td text-muted">{u.last_sign_in_at ? dateTime(u.last_sign_in_at) : 'Not yet'}</td>
							<td class="td text-right">
								{#if u.is_me}
									<span class="text-muted">You</span>
								{:else if confirming === u.user_id}
									<span class="mr-2">Remove {u.email}?</span>
									<button class="btn btn-danger" disabled={busy} onclick={() => run(() => manageUsers({ action: 'remove', user_id: u.user_id }), `Removed ${u.email}.`)}>Remove</button>
									<button class="btn" onclick={() => (confirming = null)}>Keep</button>
								{:else}
									{#if u.invited}
										<button class="btn" disabled={busy} onclick={() => run(() => manageUsers({ action: 'resend', email: u.email, role: u.role }), `Invitation sent again to ${u.email}.`)}>Resend</button>
									{/if}
									<button class="btn btn-danger" disabled={busy} onclick={() => (confirming = u.user_id)}>{u.invited ? 'Cancel invite' : 'Remove access'}</button>
								{/if}
							</td>
						</tr>
					{/each}
				</tbody>
			</table>
		</div>
	</section>
{/if}
