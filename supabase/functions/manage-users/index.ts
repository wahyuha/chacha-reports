// Invites and removes dashboard users. This needs the secret key, so it can't run in the browser.
// Only a signed-in owner may call it.
import { createClient } from 'npm:@supabase/supabase-js@2';

const SITE_URL = 'https://reports.chacha.id';
const ALLOWED_ORIGINS = [SITE_URL, 'http://localhost:5173'];

function headers(req: Request) {
	const origin = req.headers.get('Origin') ?? '';
	return {
		'Access-Control-Allow-Origin': ALLOWED_ORIGINS.includes(origin) ? origin : SITE_URL,
		'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
		'Access-Control-Allow-Methods': 'POST, OPTIONS',
		'Content-Type': 'application/json',
		Vary: 'Origin'
	};
}

Deno.serve(async (req) => {
	const reply = (status: number, body: unknown) =>
		new Response(JSON.stringify(body), { status, headers: headers(req) });

	if (req.method === 'OPTIONS') return new Response('ok', { headers: headers(req) });
	if (req.method !== 'POST') return reply(405, { error: 'Method not allowed' });

	const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
		auth: { persistSession: false, autoRefreshToken: false }
	});

	const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
	const { data: caller } = await admin.auth.getUser(token);
	if (!caller?.user) return reply(401, { error: 'Please sign in again' });

	const { data: me } = await admin
		.from('dashboard_users')
		.select('role')
		.eq('user_id', caller.user.id)
		.maybeSingle();
	if (me?.role !== 'owner') return reply(403, { error: 'Only an owner can manage users' });

	const body = await req.json().catch(() => ({}));
	const redirectTo = `${SITE_URL}/set-password`;

	if (body.action === 'invite' || body.action === 'resend') {
		const email = String(body.email ?? '').trim().toLowerCase();
		const role = body.role === 'owner' ? 'owner' : 'viewer';
		if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return reply(400, { error: 'Enter a valid email' });

		const { data, error } = await admin.auth.admin.inviteUserByEmail(email, { redirectTo });
		if (error) return reply(400, { error: error.message });

		if (body.action === 'invite') {
			const { error: rowError } = await admin.from('dashboard_users').upsert({
				user_id: data.user.id,
				email,
				role,
				must_change_password: true,
				invited_by: caller.user.id
			});
			if (rowError) return reply(500, { error: rowError.message });
		}
		return reply(200, { ok: true });
	}

	if (body.action === 'remove') {
		const userId = String(body.user_id ?? '');
		if (userId === caller.user.id) return reply(400, { error: "You can't remove yourself" });
		const { error } = await admin.auth.admin.deleteUser(userId);
		if (error) return reply(400, { error: error.message });
		return reply(200, { ok: true });
	}

	return reply(400, { error: 'Unknown action' });
});
