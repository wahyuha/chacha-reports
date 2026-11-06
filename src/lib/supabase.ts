import { createClient } from '@supabase/supabase-js';

// The publishable key is meant for clients: it reaches only the functions granted in supabase/migrations.
// The secret key must never be added here.
const SUPABASE_URL = 'https://yndyjqthzcqrnokafxvp.supabase.co';
const PUBLISHABLE_KEY = 'sb_publishable_4jQUOWY2K9Lsd1YpJLaTow_eA4DSLpz';

export const supabase = createClient(SUPABASE_URL, PUBLISHABLE_KEY, {
	auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true, flowType: 'implicit' }
});

export async function rpc<T>(fn: string, args?: Record<string, unknown>): Promise<T> {
	if (import.meta.env.DEV) {
		const demo = await import('./demo');
		if (demo.demoEnabled()) return demo.demoRpc(fn, args) as T;
	}
	const { data, error } = await supabase.rpc(fn, args);
	if (error) throw new Error(error.message);
	return data as T;
}

export async function manageUsers(body: Record<string, unknown>): Promise<void> {
	const { data, error } = await supabase.functions.invoke('manage-users', { body });
	if (error) {
		const detail = await (error.context as Response | undefined)?.json?.().catch(() => null);
		throw new Error(detail?.error ?? error.message);
	}
	if (data?.error) throw new Error(data.error);
}
