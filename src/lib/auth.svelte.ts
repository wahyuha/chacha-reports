import type { Session } from '@supabase/supabase-js';
import { rpc, supabase } from './supabase';

export type Access = { email: string; role: 'owner' | 'viewer'; must_change_password: boolean };

class Auth {
	session = $state<Session | null>(null);
	access = $state<Access | null>(null);
	ready = $state(false);
	/** True once the user arrived from a password-reset email. */
	recovering = $state(false);
	/** The access check failed for a reason other than having no access. */
	failed = $state(false);

	get isOwner() {
		return this.access?.role === 'owner';
	}

	private userId: string | null = null;

	start() {
		supabase.auth.onAuthStateChange((event, session) => {
			this.session = session;
			if (event === 'PASSWORD_RECOVERY') this.recovering = true;
			const id = session?.user.id ?? null;
			if (id === this.userId && this.ready) return;
			this.userId = id;
			// Calling Supabase inside this callback can deadlock its auth lock, so step out of it first.
			setTimeout(() => this.load(), 0);
		});
	}

	async load() {
		this.failed = false;
		if (!this.session) {
			this.access = null;
			this.ready = true;
			return;
		}
		try {
			this.access = await rpc<Access | null>('my_access');
		} catch {
			this.access = null;
			this.failed = true;
		}
		this.ready = true;
	}

	async signOut() {
		await supabase.auth.signOut();
		this.recovering = false;
		this.access = null;
		this.session = null;
	}
}

export const auth = new Auth();
