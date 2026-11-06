export function rupiah(n: number | string | null | undefined): string {
	const value = Math.round(Number(n ?? 0));
	const digits = Math.abs(value).toString().replace(/\B(?=(\d{3})+(?!\d))/g, '.');
	return `${value < 0 ? '− ' : ''}Rp ${digits}`;
}

/** Today in the outlet's clock, as yyyy-mm-dd. */
export function today(): string {
	return new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Jakarta' }).format(new Date());
}

export function addDays(date: string, days: number): string {
	const d = new Date(`${date}T00:00:00Z`);
	d.setUTCDate(d.getUTCDate() + days);
	return d.toISOString().slice(0, 10);
}

const UTC = { timeZone: 'UTC' } as const;

export function longDate(date: string): string {
	return new Date(`${date}T00:00:00Z`).toLocaleDateString('en-GB', {
		...UTC,
		weekday: 'short',
		day: 'numeric',
		month: 'short',
		year: 'numeric'
	});
}

export function shortDate(date: string): string {
	return new Date(`${date}T00:00:00Z`).toLocaleDateString('en-GB', {
		...UTC,
		weekday: 'short',
		day: 'numeric',
		month: 'short'
	});
}

export function weekdayShort(date: string): string {
	return new Date(`${date}T00:00:00Z`).toLocaleDateString('en-GB', { ...UTC, weekday: 'short' });
}

export function monthName(date: string): string {
	return new Date(`${date}T00:00:00Z`).toLocaleDateString('en-GB', { ...UTC, month: 'long', year: 'numeric' });
}

export function weekdayOf(date: string): string {
	return new Date(`${date}T00:00:00Z`).toLocaleDateString('en-GB', { ...UTC, weekday: 'long' });
}

export function clock(iso: string | null | undefined): string {
	if (!iso) return '';
	return new Date(iso).toLocaleTimeString('en-GB', {
		timeZone: 'Asia/Jakarta',
		hour: '2-digit',
		minute: '2-digit'
	});
}

export function dateTime(iso: string | null | undefined): string {
	if (!iso) return '';
	return new Date(iso).toLocaleString('en-GB', {
		timeZone: 'Asia/Jakarta',
		day: 'numeric',
		month: 'short',
		hour: '2-digit',
		minute: '2-digit'
	});
}

/** "+12%" against a comparison, or null when there is nothing to compare with. */
export function change(now: number | string, before: number | string): string | null {
	const a = Number(now);
	const b = Number(before);
	if (!b) return null;
	const pct = Math.round(((a - b) / b) * 100);
	return `${pct > 0 ? '+' : pct < 0 ? '−' : ''}${Math.abs(pct)}%`;
}

export const WEEKDAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

export function share(part: number, total: number): number {
	return total ? Math.round((part / total) * 100) : 0;
}
