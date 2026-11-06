-- Chacha Reports: attendance, base salary and commission.
--
-- Commission: for each day, the outlet's cups (cancelled orders excluded) above the rule's threshold earn
-- rate_per_cup. Every employee who clocked in that day earns the full amount. No minimum time.
-- Salary: monthly base from pay_rates, no deductions. An approved (locked) month never changes; later
-- differences, from orders that sync or are cancelled after locking, are paid as a correction next month.

create table public.attendance (
  id            uuid primary key,  -- created on the tablet, so a resend can't duplicate
  outlet_id     uuid not null references public.outlets (id),
  device_id     uuid references public.devices (id),
  staff_code    text not null,
  staff_name    text not null,
  business_date date not null,
  clock_in_at   timestamptz not null,
  clock_out_at  timestamptz,
  source        text not null default 'tablet' check (source in ('tablet', 'owner')),
  edited_by     uuid references auth.users (id) on delete set null,
  edited_at     timestamptz,
  received_at   timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint clock_out_after_in check (clock_out_at is null or clock_out_at >= clock_in_at)
);
create index attendance_outlet_date_idx on public.attendance (outlet_id, business_date);

create table public.pay_rates (
  staff_id       uuid not null references public.staff (id) on delete cascade,
  effective_from date not null,
  base_salary    bigint not null check (base_salary >= 0),
  created_at     timestamptz not null default now(),
  primary key (staff_id, effective_from)
);

create table public.commission_rules (
  outlet_id      uuid not null references public.outlets (id) on delete cascade,
  effective_from date not null,
  threshold_cups int not null check (threshold_cups >= 0),
  rate_per_cup   bigint not null check (rate_per_cup >= 0),
  primary key (outlet_id, effective_from)
);

create table public.payroll_periods (
  outlet_id uuid not null references public.outlets (id),
  month     date not null check (extract(day from month) = 1),
  locked_at timestamptz not null default now(),
  locked_by uuid references auth.users (id) on delete set null,
  primary key (outlet_id, month)
);

create table public.payroll_lines (
  outlet_id   uuid not null,
  month       date not null,
  staff_code  text not null,
  staff_name  text not null,
  days_worked int not null,
  base_salary bigint not null,
  commission  bigint not null,
  correction  bigint not null,
  total       bigint not null,
  primary key (outlet_id, month, staff_code),
  foreign key (outlet_id, month) references public.payroll_periods (outlet_id, month) on delete cascade
);

alter table public.attendance       enable row level security;
alter table public.pay_rates        enable row level security;
alter table public.commission_rules enable row level security;
alter table public.payroll_periods  enable row level security;
alter table public.payroll_lines    enable row level security;
revoke all on public.attendance, public.pay_rates, public.commission_rules, public.payroll_periods, public.payroll_lines
  from anon, authenticated;

create trigger touch_updated_at before update on public.attendance
  for each row execute function public.touch_updated_at();

-- Starting values: Rp 1.500.000 base for every staff member, Rp 1.000 per cup from cup 21.
insert into public.pay_rates (staff_id, effective_from, base_salary)
  select s.id, date '2026-01-01', 1500000 from public.staff s
  on conflict do nothing;
insert into public.commission_rules (outlet_id, effective_from, threshold_cups, rate_per_cup)
  select o.id, date '2026-01-01', 20, 1000 from public.outlets o
  on conflict do nothing;

-- ── Called by tablets ──────────────────────────────────────────────────────

-- Saves clock-ins and clock-outs. Safe to resend. A clock-out is only ever added, never changed,
-- and a row the owner has edited keeps the owner's times.
create function public.sync_attendance(p_token text, p_rows jsonb default '[]'::jsonb)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_dev      public.devices;
  v_row      jsonb;
  v_id       uuid;
  v_accepted jsonb := '[]'::jsonb;
  v_rejected jsonb := '[]'::jsonb;
begin
  select * into v_dev from public.devices
    where token_hash = encode(sha256(convert_to(coalesce(p_token, ''), 'UTF8')), 'hex') and status = 'active';
  if not found then
    raise exception 'device not active' using errcode = '28000';
  end if;
  if jsonb_array_length(p_rows) > 200 then raise exception 'batch too large'; end if;
  update public.devices set last_seen_at = now() where id = v_dev.id;

  for v_row in select * from jsonb_array_elements(p_rows) loop
    begin
      v_id := (v_row->>'id')::uuid;
      insert into public.attendance (id, outlet_id, device_id, staff_code, staff_name, business_date, clock_in_at, clock_out_at)
      values (v_id, v_dev.outlet_id, v_dev.id, v_row->>'staff_code', v_row->>'staff_name', (v_row->>'business_date')::date,
              (v_row->>'clock_in_at')::timestamptz, (v_row->>'clock_out_at')::timestamptz)
      on conflict (id) do update set
        clock_out_at = coalesce(public.attendance.clock_out_at, excluded.clock_out_at)
      where public.attendance.device_id = v_dev.id and public.attendance.edited_at is null;
      if not exists (select 1 from public.attendance a where a.id = v_id and a.device_id = v_dev.id) then
        raise exception 'attendance belongs to another device';
      end if;
      v_accepted := v_accepted || jsonb_build_object('type', 'attendance', 'id', v_id);
    exception when others then
      v_rejected := v_rejected || jsonb_build_object('type', 'attendance', 'id', v_row->>'id', 'reason', sqlerrm);
    end;
  end loop;

  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end $$;

-- ── Internal helpers ───────────────────────────────────────────────────────

create function public.dashboard_day_cups(p_outlet uuid, p_from date, p_to date)
returns table (business_date date, cups bigint)
language sql stable security definer set search_path = '' as $$
  select s.business_date, sum(s.cups)::bigint from public.dashboard_sold(p_outlet, p_from, p_to) s group by 1
$$;

create function public.commission_for(p_outlet uuid, p_date date, p_cups bigint) returns bigint
language sql stable security definer set search_path = '' as $$
  select coalesce((
    select greatest(0, p_cups - r.threshold_cups) * r.rate_per_cup
    from public.commission_rules r
    where r.outlet_id = p_outlet and r.effective_from <= p_date
    order by r.effective_from desc limit 1), 0)
$$;

-- One row per employee per day they clocked in, with that day's outlet cups and the commission it earns.
create function public.payroll_earned(p_outlet uuid, p_from date, p_to date)
returns table (staff_code text, business_date date, cups bigint, commission bigint)
language sql stable security definer set search_path = '' as $$
  with worked as (
    select distinct a.staff_code, a.business_date from public.attendance a
    where a.outlet_id = p_outlet and a.business_date between p_from and p_to
  )
  select w.staff_code, w.business_date, coalesce(c.cups, 0),
         public.commission_for(p_outlet, w.business_date, coalesce(c.cups, 0))
  from worked w left join public.dashboard_day_cups(p_outlet, p_from, p_to) c using (business_date)
$$;

create function public.payroll_compute(p_outlet uuid, p_month date) returns jsonb
language sql stable security definer set search_path = '' as $$
  with bounds as (select p_month as m_from, (p_month + interval '1 month - 1 day')::date as m_to),
  earned as (select e.* from bounds b, public.payroll_earned(p_outlet, b.m_from, b.m_to) e),
  people as (
    select s.id, s.code, s.name, s.sort_order from public.staff s
    where s.outlet_id = p_outlet
      and (s.active or exists (select 1 from earned e where e.staff_code = s.code))
  ),
  locked_earned as (
    select e.staff_code, sum(e.commission) as earned
    from public.payroll_periods pp,
         public.payroll_earned(p_outlet, pp.month, (pp.month + interval '1 month - 1 day')::date) e
    where pp.outlet_id = p_outlet and pp.month < p_month
    group by 1
  ),
  paid as (
    select l.staff_code, sum(l.commission + l.correction) as paid
    from public.payroll_lines l where l.outlet_id = p_outlet and l.month < p_month group by 1
  ),
  lines as (
    select p.code, p.name, p.sort_order,
      (select count(*) from earned e where e.staff_code = p.code) as days_worked,
      coalesce((select r.base_salary from public.pay_rates r, bounds b
                where r.staff_id = p.id and r.effective_from <= b.m_to
                order by r.effective_from desc limit 1), 0) as base_salary,
      coalesce((select sum(e.commission) from earned e where e.staff_code = p.code), 0) as commission,
      coalesce((select le.earned from locked_earned le where le.staff_code = p.code), 0)
        - coalesce((select pd.paid from paid pd where pd.staff_code = p.code), 0) as correction,
      (select coalesce(jsonb_agg(jsonb_build_object('date', e.business_date, 'cups', e.cups, 'commission', e.commission)
                                 order by e.business_date), '[]'::jsonb)
         from earned e where e.staff_code = p.code) as days
    from people p
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'staff_code', l.code, 'staff_name', l.name, 'days_worked', l.days_worked,
    'base_salary', l.base_salary, 'commission', l.commission, 'correction', l.correction,
    'total', l.base_salary + l.commission + l.correction, 'days', l.days
  ) order by l.sort_order, l.name), '[]'::jsonb)
  from lines l
$$;

-- The outlet's local date today.
create function public.outlet_today(p_outlet public.outlets) returns date
language sql stable set search_path = '' as $$
  select (now() at time zone p_outlet.timezone)::date
$$;

-- ── Owner only ─────────────────────────────────────────────────────────────

create function public.payroll_month(p_outlet text, p_month date) returns jsonb
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
    'rule', (select jsonb_build_object('threshold_cups', r.threshold_cups, 'rate_per_cup', r.rate_per_cup)
             from public.commission_rules r
             where r.outlet_id = v.id and r.effective_from <= (v_month + interval '1 month - 1 day')::date
             order by r.effective_from desc limit 1),
    'outlet_days', (
      select coalesce(jsonb_agg(jsonb_build_object('date', c.business_date, 'cups', c.cups,
                                                   'commission', public.commission_for(v.id, c.business_date, c.cups))
                                order by c.business_date), '[]'::jsonb)
      from public.dashboard_day_cups(v.id, v_month, (v_month + interval '1 month - 1 day')::date) c),
    'lines', v_lines
  );
end $$;

create function public.payroll_lock(p_outlet text, p_month date) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v public.outlets;
  v_month date := date_trunc('month', p_month)::date;
begin
  perform public.dashboard_require(true);
  v := public.dashboard_outlet(p_outlet);
  if v_month >= date_trunc('month', public.outlet_today(v))::date then
    raise exception 'A month can be approved once it has ended';
  end if;
  insert into public.payroll_periods (outlet_id, month, locked_by) values (v.id, v_month, auth.uid());
  insert into public.payroll_lines (outlet_id, month, staff_code, staff_name, days_worked, base_salary, commission, correction, total)
  select v.id, v_month, l->>'staff_code', l->>'staff_name', (l->>'days_worked')::int, (l->>'base_salary')::bigint,
         (l->>'commission')::bigint, (l->>'correction')::bigint, (l->>'total')::bigint
  from jsonb_array_elements(public.payroll_compute(v.id, v_month)) l;
end $$;

create function public.set_base_salary(p_outlet text, p_staff_code text, p_amount bigint, p_from date) returns void
language plpgsql security definer set search_path = '' as $$
declare v public.outlets; v_staff uuid;
begin
  perform public.dashboard_require(true);
  v := public.dashboard_outlet(p_outlet);
  select id into v_staff from public.staff where outlet_id = v.id and code = p_staff_code;
  if v_staff is null then raise exception 'no such staff'; end if;
  if p_amount < 0 then raise exception 'Salary can''t be negative'; end if;
  if exists (select 1 from public.payroll_periods where outlet_id = v.id and month >= date_trunc('month', p_from)) then
    raise exception 'That month is already approved. Choose a later start month.';
  end if;
  insert into public.pay_rates (staff_id, effective_from, base_salary)
  values (v_staff, date_trunc('month', p_from)::date, p_amount)
  on conflict (staff_id, effective_from) do update set base_salary = excluded.base_salary;
end $$;

create function public.attendance_month(p_outlet text, p_month date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v public.outlets;
  v_month date := date_trunc('month', p_month)::date;
begin
  perform public.dashboard_require(true);
  v := public.dashboard_outlet(p_outlet);
  return jsonb_build_object(
    'month', v_month,
    'today', public.outlet_today(v),
    'staff', (select coalesce(jsonb_agg(jsonb_build_object('code', s.code, 'name', s.name) order by s.sort_order, s.name), '[]'::jsonb)
              from public.staff s where s.outlet_id = v.id and s.active),
    'rows', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', a.id, 'staff_code', a.staff_code, 'staff_name', a.staff_name, 'date', a.business_date,
        'clock_in_at', a.clock_in_at, 'clock_out_at', a.clock_out_at, 'source', a.source,
        'edited', a.edited_at is not null
      ) order by a.business_date, a.clock_in_at), '[]'::jsonb)
      from public.attendance a
      where a.outlet_id = v.id and a.business_date between v_month and (v_month + interval '1 month - 1 day')::date),
    -- Past days with no clock-out, in any month, so nothing slips through.
    'missing_clock_out', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', a.id, 'staff_code', a.staff_code, 'staff_name', a.staff_name, 'date', a.business_date,
        'clock_in_at', a.clock_in_at
      ) order by a.business_date desc), '[]'::jsonb)
      from public.attendance a
      where a.outlet_id = v.id and a.clock_out_at is null and a.business_date < public.outlet_today(v))
  );
end $$;

-- Adds a missed clock-in (p_id null) or corrects one. Times are full timestamps.
create function public.attendance_save(p_outlet text, p_id uuid, p_staff_code text, p_date date,
                                       p_clock_in timestamptz, p_clock_out timestamptz)
returns void
language plpgsql security definer set search_path = '' as $$
declare v public.outlets; v_name text;
begin
  perform public.dashboard_require(true);
  v := public.dashboard_outlet(p_outlet);
  select name into v_name from public.staff where outlet_id = v.id and code = p_staff_code;
  if v_name is null then raise exception 'no such staff'; end if;
  if p_clock_out is not null and p_clock_out < p_clock_in then
    raise exception 'Clock-out must be after clock-in';
  end if;
  if exists (select 1 from public.payroll_periods where outlet_id = v.id and month = date_trunc('month', p_date)) then
    raise exception 'That month is already approved';
  end if;
  if p_id is null then
    insert into public.attendance (id, outlet_id, staff_code, staff_name, business_date, clock_in_at, clock_out_at,
                                   source, edited_by, edited_at)
    values (gen_random_uuid(), v.id, p_staff_code, v_name, p_date, p_clock_in, p_clock_out, 'owner', auth.uid(), now());
  else
    update public.attendance set staff_code = p_staff_code, staff_name = v_name, business_date = p_date,
      clock_in_at = p_clock_in, clock_out_at = p_clock_out, edited_by = auth.uid(), edited_at = now()
    where id = p_id and outlet_id = v.id;
    if not found then raise exception 'no such attendance'; end if;
  end if;
end $$;

create function public.attendance_delete(p_outlet text, p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v public.outlets; v_date date;
begin
  perform public.dashboard_require(true);
  v := public.dashboard_outlet(p_outlet);
  select business_date into v_date from public.attendance where id = p_id and outlet_id = v.id;
  if v_date is null then raise exception 'no such attendance'; end if;
  if exists (select 1 from public.payroll_periods where outlet_id = v.id and month = date_trunc('month', v_date)) then
    raise exception 'That month is already approved';
  end if;
  delete from public.attendance where id = p_id;
end $$;

-- ── Grants ───────────────────────────────────────────────────────────────────

revoke execute on function public.sync_attendance(text, jsonb) from public, anon, authenticated;
grant execute on function public.sync_attendance(text, jsonb) to anon;

revoke execute on function public.dashboard_day_cups(uuid, date, date) from public, anon, authenticated;
revoke execute on function public.commission_for(uuid, date, bigint) from public, anon, authenticated;
revoke execute on function public.payroll_earned(uuid, date, date) from public, anon, authenticated;
revoke execute on function public.payroll_compute(uuid, date) from public, anon, authenticated;
revoke execute on function public.outlet_today(public.outlets) from public, anon, authenticated;

revoke execute on function public.payroll_month(text, date) from public, anon;
revoke execute on function public.payroll_lock(text, date) from public, anon;
revoke execute on function public.set_base_salary(text, text, bigint, date) from public, anon;
revoke execute on function public.attendance_month(text, date) from public, anon;
revoke execute on function public.attendance_save(text, uuid, text, date, timestamptz, timestamptz) from public, anon;
revoke execute on function public.attendance_delete(text, uuid) from public, anon;

grant execute on function public.payroll_month(text, date) to authenticated;
grant execute on function public.payroll_lock(text, date) to authenticated;
grant execute on function public.set_base_salary(text, text, bigint, date) to authenticated;
grant execute on function public.attendance_month(text, date) to authenticated;
grant execute on function public.attendance_save(text, uuid, text, date, timestamptz, timestamptz) to authenticated;
grant execute on function public.attendance_delete(text, uuid) to authenticated;

notify pgrst, 'reload schema';
