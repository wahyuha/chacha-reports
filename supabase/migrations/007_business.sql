-- Chacha Reports: monthly operating costs, profit and loss, and return on investment.
--
-- Net profit = gross margin (price - HPP, 005) - staff (base salary + actual commission, 004) - monthly costs.
-- Monthly amounts are spread evenly over the days of their month, so a month still running counts only the
-- days so far. Counting starts on the opening day: costs before it are part of the starting capital.
-- Everything here is owner only.

-- Rent, water, electricity, internet... One row per change; a change applies from the first of its month.
create table public.operating_costs (
  outlet_id      uuid not null references public.outlets (id) on delete cascade,
  cost_code      text not null,
  name           text not null,
  effective_from date not null check (extract(day from effective_from) = 1),
  amount         bigint not null check (amount >= 0),  -- 0 = no longer paid from that month
  updated_by     uuid references auth.users (id) on delete set null,
  updated_at     timestamptz not null default now(),
  primary key (outlet_id, cost_code, effective_from)
);

-- What was put in to open the outlet. One line for now; it can be split into parts later.
create table public.capital_items (
  id          uuid primary key default gen_random_uuid(),
  outlet_id   uuid not null references public.outlets (id) on delete cascade,
  name        text not null,
  amount      bigint not null check (amount >= 0),
  sort_order  int not null default 0,
  created_at  timestamptz not null default now()
);

create table public.business_settings (
  outlet_id      uuid primary key references public.outlets (id) on delete cascade,
  opened_on      date not null,
  payback_months int not null default 12 check (payback_months between 1 and 120),
  staff_per_day  int not null default 1 check (staff_per_day between 0 and 10),  -- for forecasts only
  updated_at     timestamptz not null default now()
);

alter table public.operating_costs   enable row level security;
alter table public.capital_items     enable row level security;
alter table public.business_settings enable row level security;
revoke all on public.operating_costs, public.capital_items, public.business_settings from anon, authenticated;

-- ── Starting values (decided by the owner on 2026-11-10) ─────────────────────

insert into public.operating_costs (outlet_id, cost_code, name, effective_from, amount)
select o.id, c.code, c.name, date '2026-11-01', c.amount
from public.outlets o
cross join (values ('rent', 'Rent', 2000000), ('water', 'Water', 100000),
                   ('electricity', 'Electricity', 200000), ('internet', 'Internet', 200000)) as c (code, name, amount)
on conflict do nothing;

insert into public.capital_items (outlet_id, name, amount)
select o.id, 'Starting capital', 20000000 from public.outlets o;

-- Opening day: the first day with a sale, or today for an outlet without one yet.
insert into public.business_settings (outlet_id, opened_on)
select o.id, coalesce((select min(r.business_date) from public.orders r where r.outlet_id = o.id and r.status <> 'cancelled'),
                      (now() at time zone o.timezone)::date)
from public.outlets o
on conflict do nothing;

-- Only Neli and Ugan are salaried. Meirisa and Laura still earn commission on days they clock in.
insert into public.pay_rates (staff_id, effective_from, base_salary)
select s.id, date '2026-11-01', 0 from public.staff s where s.code in ('meirisa', 'laura')
on conflict (staff_id, effective_from) do update set base_salary = 0;

-- ── Internal helpers: not callable from the browser ──────────────────────────

-- The share of a monthly amount that falls on days first..last of month p_month. Shares are whole rupiah
-- and add up exactly to the monthly amount over a full month.
create function public.dashboard_month_share(p_amount bigint, p_month date, p_first date, p_last date) returns bigint
language sql immutable set search_path = '' as $$
  select case when p_last < p_first then 0::bigint
              else (p_amount * extract(day from p_last)::bigint) / n - (p_amount * (extract(day from p_first)::bigint - 1)) / n end
  from (select extract(day from (date_trunc('month', p_month) + interval '1 month - 1 day'))::bigint as n) d
$$;

-- Monthly costs in force in a month, one row per cost (latest change on or before the month).
create function public.dashboard_costs_in(p_outlet uuid, p_month date)
returns table (cost_code text, name text, amount bigint)
language sql stable security definer set search_path = '' as $$
  select distinct on (c.cost_code) c.cost_code, c.name, c.amount
  from public.operating_costs c
  where c.outlet_id = p_outlet and c.effective_from <= p_month
  order by c.cost_code, c.effective_from desc
$$;

-- Base salaries in a month, as the Salary screen counts them.
create function public.dashboard_base_in(p_outlet uuid, p_month date)
returns table (staff_code text, name text, base_salary bigint)
language sql stable security definer set search_path = '' as $$
  select s.code, s.name,
         coalesce((select r.base_salary from public.pay_rates r
                   where r.staff_id = s.id and r.effective_from <= (p_month + interval '1 month - 1 day')::date
                   order by r.effective_from desc limit 1), 0)
  from public.staff s where s.outlet_id = p_outlet and s.active
$$;

-- One row per day: sales, HPP, actual commission and the day's share of base salaries and monthly costs.
create function public.dashboard_daily_net(p_outlet uuid, p_from date, p_to date)
returns table (business_date date, cups bigint, sales bigint, cost bigint, costed_sales bigint, uncosted_cups bigint,
               commission bigint, base bigint, fixed bigint)
language sql stable security definer set search_path = '' as $$
  with days as (select d::date as business_date from generate_series(p_from, p_to, interval '1 day') d),
  lines as (
    select l.business_date, sum(l.cups) as cups, sum(l.sales) as sales, coalesce(sum(l.cups * l.hpp), 0) as cost,
           coalesce(sum(l.sales) filter (where l.hpp is not null), 0) as costed_sales,
           coalesce(sum(l.cups) filter (where l.hpp is null), 0) as uncosted_cups
    from public.dashboard_cost_lines(p_outlet, p_from, p_to) l group by 1),
  comm as (select e.business_date, sum(e.commission) as commission from public.payroll_earned(p_outlet, p_from, p_to) e group by 1),
  months as (
    select m::date as month,
           (select coalesce(sum(b.base_salary), 0) from public.dashboard_base_in(p_outlet, m::date) b) as base,
           (select coalesce(sum(c.amount), 0) from public.dashboard_costs_in(p_outlet, m::date) c) as fixed
    from generate_series(date_trunc('month', p_from), date_trunc('month', p_to), interval '1 month') m)
  select d.business_date, coalesce(l.cups, 0)::bigint, coalesce(l.sales, 0)::bigint, coalesce(l.cost, 0)::bigint,
         coalesce(l.costed_sales, 0)::bigint, coalesce(l.uncosted_cups, 0)::bigint, coalesce(c.commission, 0)::bigint,
         public.dashboard_month_share(m.base::bigint, m.month, d.business_date, d.business_date),
         public.dashboard_month_share(m.fixed::bigint, m.month, d.business_date, d.business_date)
  from days d
  left join lines l using (business_date)
  left join comm c using (business_date)
  join months m on m.month = date_trunc('month', d.business_date)::date
$$;

create function public.dashboard_settings(p_outlet public.outlets) returns public.business_settings
language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select s from public.business_settings s where s.outlet_id = p_outlet.id),
    row(p_outlet.id, public.outlet_today(p_outlet), 12, 1, now())::public.business_settings)
$$;

-- ── Owner only: reports ──────────────────────────────────────────────────────

create function public.report_pnl(p_outlet text, p_month date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v public.outlets;
  v_set public.business_settings;
  v_month date := date_trunc('month', p_month)::date;
  v_end date := (date_trunc('month', p_month) + interval '1 month - 1 day')::date;
  v_today date;
  v_from date;
  v_to date;
begin
  perform public.dashboard_require(true);
  v := public.dashboard_outlet(p_outlet);
  v_set := public.dashboard_settings(v);
  v_today := public.outlet_today(v);
  v_from := greatest(v_month, v_set.opened_on);
  v_to := least(v_end, v_today);

  if v_to < v_from then
    return jsonb_build_object('month', v_month, 'opened_on', v_set.opened_on, 'from', null, 'to', null,
                              'days_in_month', extract(day from v_end), 'days_counted', 0);
  end if;

  return (
    with d as (select * from public.dashboard_daily_net(v.id, v_from, v_to))
    select jsonb_build_object(
      'month', v_month,
      'opened_on', v_set.opened_on,
      'from', v_from,
      'to', v_to,
      'days_in_month', extract(day from v_end),
      'days_counted', v_to - v_from + 1,
      'complete', v_to = v_end,
      'totals', (select jsonb_build_object(
          'cups', sum(cups), 'sales', sum(sales), 'cost', sum(cost), 'costed_sales', sum(costed_sales),
          'uncosted_cups', sum(uncosted_cups), 'commission', sum(commission)) from d),
      'staff', (select coalesce(jsonb_agg(jsonb_build_object(
                  'name', b.name, 'month_amount', b.base_salary,
                  'amount', public.dashboard_month_share(b.base_salary, v_month, v_from, v_to)) order by b.name), '[]'::jsonb)
                from public.dashboard_base_in(v.id, v_month) b where b.base_salary > 0),
      'costs', (select coalesce(jsonb_agg(jsonb_build_object(
                  'code', c.cost_code, 'name', c.name, 'month_amount', c.amount,
                  'amount', public.dashboard_month_share(c.amount, v_month, v_from, v_to)) order by c.amount desc, c.name), '[]'::jsonb)
                from public.dashboard_costs_in(v.id, v_month) c where c.amount > 0),
      'days', (select coalesce(jsonb_agg(jsonb_build_object(
                  'date', business_date, 'cups', cups, 'gross', costed_sales - cost,
                  'net', costed_sales - cost - commission - base - fixed) order by business_date), '[]'::jsonb) from d)
    ));
end $$;

create function public.report_roi(p_outlet text) returns jsonb
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
      'rule', (select jsonb_build_object('threshold_cups', r.threshold_cups, 'rate_per_cup', r.rate_per_cup)
               from public.commission_rules r where r.outlet_id = v.id and r.effective_from <= v_today
               order by r.effective_from desc limit 1)
    ));
end $$;

-- ── Owner only: editing ──────────────────────────────────────────────────────

create function public.operating_costs_list(p_outlet text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v public.outlets; v_month date;
begin
  perform public.dashboard_require(true);
  v := public.dashboard_outlet(p_outlet);
  v_month := date_trunc('month', public.outlet_today(v))::date;
  return (
    select coalesce(jsonb_agg(x order by (x->'current'->>'amount')::bigint desc nulls last, x->>'name'), '[]'::jsonb) from (
      select jsonb_build_object(
        'code', c.cost_code,
        'name', (select o.name from public.operating_costs o where o.outlet_id = v.id and o.cost_code = c.cost_code
                 order by o.effective_from desc limit 1),
        'current', (select jsonb_build_object('from', o.effective_from, 'amount', o.amount) from public.operating_costs o
                    where o.outlet_id = v.id and o.cost_code = c.cost_code and o.effective_from <= v_month
                    order by o.effective_from desc limit 1),
        'history', (select jsonb_agg(jsonb_build_object('from', o.effective_from, 'amount', o.amount, 'name', o.name,
                                                        'updated_at', o.updated_at) order by o.effective_from desc)
                    from public.operating_costs o where o.outlet_id = v.id and o.cost_code = c.cost_code)) as x
      from (select distinct cost_code from public.operating_costs where outlet_id = v.id) c) t);
end $$;

-- p_code null adds a new cost named p_name.
create function public.operating_cost_save(p_outlet text, p_code text, p_name text, p_from date, p_amount bigint)
returns void
language plpgsql security definer set search_path = '' as $$
declare v public.outlets; v_code text := p_code;
begin
  perform public.dashboard_require(true);
  v := public.dashboard_outlet(p_outlet);
  if coalesce(btrim(p_name), '') = '' then raise exception 'Give the cost a name'; end if;
  if p_from is null then raise exception 'Choose the month it applies from'; end if;
  if p_amount is null or p_amount < 0 then raise exception 'The amount can''t be empty or negative'; end if;
  if v_code is null then
    v_code := nullif(regexp_replace(lower(btrim(p_name)), '[^a-z0-9]+', '_', 'g'), '_');
    if v_code is null then v_code := 'cost_' || substr(gen_random_uuid()::text, 1, 8); end if;
    if exists (select 1 from public.operating_costs where outlet_id = v.id and cost_code = v_code) then
      raise exception 'A cost with that name already exists. Edit it instead.';
    end if;
  end if;
  insert into public.operating_costs (outlet_id, cost_code, name, effective_from, amount, updated_by)
  values (v.id, v_code, btrim(p_name), date_trunc('month', p_from)::date, p_amount, auth.uid())
  on conflict (outlet_id, cost_code, effective_from) do update
    set name = excluded.name, amount = excluded.amount, updated_by = excluded.updated_by, updated_at = now();
end $$;

create function public.operating_cost_delete(p_outlet text, p_code text, p_from date) returns void
language plpgsql security definer set search_path = '' as $$
declare v public.outlets;
begin
  perform public.dashboard_require(true);
  v := public.dashboard_outlet(p_outlet);
  delete from public.operating_costs where outlet_id = v.id and cost_code = p_code and effective_from = p_from;
  if not found then raise exception 'no such cost'; end if;
end $$;

create function public.capital_item_save(p_outlet text, p_id uuid, p_name text, p_amount bigint) returns void
language plpgsql security definer set search_path = '' as $$
declare v public.outlets;
begin
  perform public.dashboard_require(true);
  v := public.dashboard_outlet(p_outlet);
  if coalesce(btrim(p_name), '') = '' then raise exception 'Give it a name'; end if;
  if p_amount is null or p_amount < 0 then raise exception 'The amount can''t be empty or negative'; end if;
  if p_id is null then
    insert into public.capital_items (outlet_id, name, amount, sort_order)
    values (v.id, btrim(p_name), p_amount,
            coalesce((select max(sort_order) + 1 from public.capital_items where outlet_id = v.id), 0));
  else
    update public.capital_items set name = btrim(p_name), amount = p_amount where id = p_id and outlet_id = v.id;
    if not found then raise exception 'no such item'; end if;
  end if;
end $$;

create function public.capital_item_delete(p_outlet text, p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v public.outlets;
begin
  perform public.dashboard_require(true);
  v := public.dashboard_outlet(p_outlet);
  delete from public.capital_items where id = p_id and outlet_id = v.id;
  if not found then raise exception 'no such item'; end if;
end $$;

create function public.business_settings_save(p_outlet text, p_opened_on date, p_payback_months int, p_staff_per_day int)
returns void
language plpgsql security definer set search_path = '' as $$
declare v public.outlets;
begin
  perform public.dashboard_require(true);
  v := public.dashboard_outlet(p_outlet);
  if p_opened_on is null or p_opened_on > public.outlet_today(v) then raise exception 'Choose an opening day that has passed'; end if;
  if p_payback_months is null or p_payback_months not between 1 and 120 then raise exception 'Payback must be 1 to 120 months'; end if;
  if p_staff_per_day is null or p_staff_per_day not between 0 and 10 then raise exception 'Staff per day must be 0 to 10'; end if;
  insert into public.business_settings (outlet_id, opened_on, payback_months, staff_per_day)
  values (v.id, p_opened_on, p_payback_months, p_staff_per_day)
  on conflict (outlet_id) do update set opened_on = excluded.opened_on, payback_months = excluded.payback_months,
    staff_per_day = excluded.staff_per_day, updated_at = now();
end $$;

-- ── Grants ───────────────────────────────────────────────────────────────────

revoke execute on function public.dashboard_month_share(bigint, date, date, date) from public, anon, authenticated;
revoke execute on function public.dashboard_costs_in(uuid, date) from public, anon, authenticated;
revoke execute on function public.dashboard_base_in(uuid, date) from public, anon, authenticated;
revoke execute on function public.dashboard_daily_net(uuid, date, date) from public, anon, authenticated;
revoke execute on function public.dashboard_settings(public.outlets) from public, anon, authenticated;

revoke execute on function public.report_pnl(text, date) from public, anon;
revoke execute on function public.report_roi(text) from public, anon;
revoke execute on function public.operating_costs_list(text) from public, anon;
revoke execute on function public.operating_cost_save(text, text, text, date, bigint) from public, anon;
revoke execute on function public.operating_cost_delete(text, text, date) from public, anon;
revoke execute on function public.capital_item_save(text, uuid, text, bigint) from public, anon;
revoke execute on function public.capital_item_delete(text, uuid) from public, anon;
revoke execute on function public.business_settings_save(text, date, int, int) from public, anon;

grant execute on function public.report_pnl(text, date) to authenticated;
grant execute on function public.report_roi(text) to authenticated;
grant execute on function public.operating_costs_list(text) to authenticated;
grant execute on function public.operating_cost_save(text, text, text, date, bigint) to authenticated;
grant execute on function public.operating_cost_delete(text, text, date) to authenticated;
grant execute on function public.capital_item_save(text, uuid, text, bigint) to authenticated;
grant execute on function public.capital_item_delete(text, uuid) to authenticated;
grant execute on function public.business_settings_save(text, date, int, int) to authenticated;

notify pgrst, 'reload schema';
