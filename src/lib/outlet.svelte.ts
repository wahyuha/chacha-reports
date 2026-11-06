import { rpc } from './supabase';

export type Outlet = { code: string; name: string };

class Outlets {
	list = $state<Outlet[]>([]);
	code = $state('MAIN');

	async load() {
		this.list = await rpc<Outlet[]>('report_outlets');
		if (this.list.length && !this.list.some((o) => o.code === this.code)) this.code = this.list[0].code;
	}
}

export const outlets = new Outlets();
