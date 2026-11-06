<script lang="ts">
	let { label, value, note = '' }: { label: string; value: string; note?: string | null } = $props();
</script>

<div class="rounded-xl border border-stone bg-raised p-4">
	<div class="text-muted">{label}</div>
	<div class="num mt-1 text-[26px] leading-[34px] font-bold">{value}</div>
	<div class="min-h-5 text-[13px] text-muted">{note}</div>
</div>
