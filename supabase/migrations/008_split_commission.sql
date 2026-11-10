-- Chacha Reports: commission shared among the staff on duty, and an owner editor for the rule.
--
-- A rule with split = true puts rate_per_cup for each outlet cup above threshold_cups into one pool for the day,
-- shared equally (whole rupiah, rounded down) among everyone who clocked in that day. split = false keeps the
-- old rule: everyone who clocked in earns the full amount.

alter table public.commission_rules add column split boolean not null default false;

-- Decided by the owner on 2026-11-10: from cup 21, Rp 1.000 a cup shared by the staff on duty (Rp 500 each for two).
insert into public.commission_rules (outlet_id, effective_from, threshold_cups, rate_per_cup, split)
select o.id, date '2026-11-01', 20, 1000, true from public.outlets o
on conflict (outlet_id, effective_from) do update
  set threshold_cups = excluded.threshold_cups, rate_per_cup = excluded.rate_per_cup, split = excluded.split;

-- Two staff clock in each day, for forecasts.
update public.business_settings set staff_per_day = 2, updated_at = now();

-- ── Internal helpers ─────────────────────────────────────────────────────────

create function public.commission_rule_at(p_outlet uuid, p_date date) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('from', r.effective_from, 'threshold_cups', r.threshold_cups,
                            'rate_per_cup', r.rate_per_cup, 'split', r.split)
  from public.commission_rules r
  where r.outlet_id = p_outlet and r.effective_from <= p_date
  order by r.effective_from desc limit 1
$$;

-- One row per employee per day they clocked in, with that day's outlet cups and the commission they earn.
create or replace function public.payroll_earned(p_outlet uuid, p_from date, p_to date)
returns table (staff_code text, business_date date, cups bigint, commission bigint)
language sql stable security definer set search_path = '' as $$
  with worked as (
    select distinct a.staff_code, a.business_date from public.attendance a
    where a.outlet_id = p_outlet and a.business_date between p_from and p_to
  ),
  heads as (select w.business_date, count(*) as n from worked w group by 1)
  select w.staff_code, w.business_date, coalesce(c.cups, 0),
         case when coalesce((public.commission_rule_at(p_outlet, w.business_date)->>'split')::boolean, false)
              then public.commission_for(p_outlet, w.business_date, coalesce(c.cups, 0)) / h.n
              else public.commission_for(p_outlet, w.business_date, coalesce(c.cups, 0)) end
  from worked w
  join heads h using (business_date)
  left join public.dashboard_day_cups(p_outlet, p_from, p_to) c using (business_date)
$$;

-- ── Owner only ───────────────────────────────────────────────────────────────

create or replace function public.payroll_month(p_outlet text, p_month date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v public.outlets;
  v_month date := date_trunc('month', p_month)::date;
  v_period public.payroll_periods;
  v_lines jsonb;
begin
  perform public.dashboard_require(true);
  v := public.dashboard_outlet(p_outlet);
  select * into v_period from public.payroll_periods where outlet_id = v.id and month = v_month;

  if found then
    -- Locked: the stored amounts, with today's day-by-day detail for reference.
    select coalesce(jsonb_agg(jsonb_build_object(
      'staff_code', l.staff_code, 'staff_name', l.staff_name, 'days_worked', l.days_worked,
      'base_salary', l.base_salary, 'commission', l.commission, 'correction', l.correction, 'total', l.total,
      'days', coalesce((select c->'days' from jsonb_array_elements(public.payroll_compute(v.id, v_month)) c
                        where c->>'staff_code' = l.staff_code), '[]'::jsonb)
    ) order by l.staff_name), '[]'::jsonb) into v_lines
    from public.payroll_lines l where l.outlet_id = v.id and l.month = v_month;
  else
    v_lines := public.payroll_compute(v.id, v_month);
  end if;

  return jsonb_build_object(
    'month', v_month,
    'status', case when v_period.month is not null then 'locked' else 'draft' end,
    'locked_at', v_period.locked_at,
    'can_lock', v_period.month is null and v_month < date_trunc('month', public.outlet_today(v))::date,
    'rule', public.commission_rule_at(v.id, (v_month + interval '1 month - 1 day')::date),
    'outlet_days', (
      select coalesce(jsonb_agg(jsonb_build_object('date', c.business_date, 'cups', c.cups,
                                                   'commission', public.commission_for(v.id, c.business_date, c.cups))
                                order by c.business_date), '[]'::jsonb)
      from public.dashboard_day_cups(v.id, v_month, (v_month + interval '1 month - 1 day')::date) c),
    'lines', v_lines
  );
end $$;

create or replace function public.report_roi(p_outlet text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v public.outlets;
  v_set public.business_settings;
  v_today date;
  v_month date;
begin
  perform public.dashboard_require(true);
  v := public.dashboard_outlet(p_outlet);
  v_set := public.dashboard_settings(v);
  v_today := public.outlet_today(v);
  v_month := date_trunc('month', v_today)::date;

  return (
    with d as (
      select *, costed_sales - cost - commission - base - fixed as net
      from public.dashboard_daily_net(v.id, v_set.opened_on, v_today)
      where v_set.opened_on <= v_today),
    recent as (select * from d where business_date > v_today - 30)
    select jsonb_build_object(
      'today', v_today,
      'opened_on', v_set.opened_on,
      'days_open', greatest(0, v_today - v_set.opened_on + 1),
      'payback_months', v_set.payback_months,
      'staff_per_day', v_set.staff_per_day,
      'capital', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'amount', c.amount)
                                            order by c.sort_order, c.created_at), '[]'::jsonb)
                  from public.capital_items c where c.outlet_id = v.id),
      'net_to_date', (select coalesce(sum(net), 0) from d),
      'months', (select coalesce(jsonb_agg(m order by m.month), '[]'::jsonb) from (
                   select date_trunc('month', business_date)::date as month, sum(net) as net
                   from d group by 1) m),
      'recent', (select jsonb_build_object(
                   'days', count(*), 'sales_days', count(*) filter (where cups > 0), 'cups', coalesce(sum(cups), 0), 'net', coalesce(sum(net), 0),
                   'gross', coalesce(sum(costed_sales - cost), 0),
                   'costed_cups', coalesce(sum(cups - uncosted_cups), 0)) from recent),
      -- Monthly amounts in force now, for break-even and targets.
      'month_base', (select coalesce(sum(b.base_salary), 0) from public.dashboard_base_in(v.id, v_month) b),
      'month_costs', (select coalesce(sum(c.amount), 0) from public.dashboard_costs_in(v.id, v_month) c),
      'rule', public.commission_rule_at(v.id, v_today)
    ));
end $$;

-- Sets the rule from the first of p_from's month. Months already approved can't change.
create function public.commission_rule_save(p_outlet text, p_from date, p_threshold int, p_rate bigint, p_split boolean)
returns void
language plpgsql security definer set search_path = '' as $$
declare v public.outlets; v_month date := date_trunc('month', p_from)::date;
begin
  perform public.dashboard_require(true);
  v := public.dashboard_outlet(p_outlet);
  if p_from is null then raise exception 'Choose the month it applies from'; end if;
  if p_threshold is null or p_threshold < 0 then raise exception 'Choose the cup commission starts after'; end if;
  if p_rate is null or p_rate < 0 then raise exception 'The amount per cup can''t be empty or negative'; end if;
  if exists (select 1 from public.payroll_periods where outlet_id = v.id and month >= v_month) then
    raise exception 'That month is already approved. Choose a later month.';
  end if;
  insert into public.commission_rules (outlet_id, effective_from, threshold_cups, rate_per_cup, split)
  values (v.id, v_month, p_threshold, p_rate, coalesce(p_split, false))
  on conflict (outlet_id, effective_from) do update
    set threshold_cups = excluded.threshold_cups, rate_per_cup = excluded.rate_per_cup, split = excluded.split;
end $$;

revoke execute on function public.commission_rule_at(uuid, date) from public, anon, authenticated;
revoke execute on function public.commission_rule_save(text, date, int, bigint, boolean) from public, anon;
grant execute on function public.commission_rule_save(text, date, int, bigint, boolean) to authenticated;

notify pgrst, 'reload schema';
