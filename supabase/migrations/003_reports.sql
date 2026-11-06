-- Chacha Reports: dashboard users and read-only report functions.
-- The browser calls these functions with a signed-in user's token. No table is readable directly.

create table public.dashboard_users (
  user_id              uuid primary key references auth.users (id) on delete cascade,
  email                text not null,
  role                 text not null check (role in ('owner', 'viewer')),
  must_change_password boolean not null default true,
  invited_by           uuid references auth.users (id) on delete set null,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

-- Emails that become owners when their auth user is created. Filled in directly, never in this repository.
create table public.dashboard_bootstrap (
  email text primary key check (email = lower(email))
);

alter table public.dashboard_users enable row level security;
alter table public.dashboard_bootstrap enable row level security;
revoke all on public.dashboard_users, public.dashboard_bootstrap from anon, authenticated;

create trigger touch_updated_at before update on public.dashboard_users
  for each row execute function public.touch_updated_at();

create function public.dashboard_bootstrap_owner() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from public.dashboard_bootstrap b where b.email = lower(new.email)) then
    insert into public.dashboard_users (user_id, email, role)
    values (new.id, lower(new.email), 'owner')
    on conflict (user_id) do nothing;
  end if;
  return new;
end $$;

create trigger dashboard_bootstrap_owner after insert on auth.users
  for each row execute function public.dashboard_bootstrap_owner();

-- ── Internal helpers: not callable from the browser ──────────────────────────

create function public.dashboard_require(p_owner boolean default false) returns void
language plpgsql stable security definer set search_path = '' as $$
declare v_role text;
begin
  select role into v_role from public.dashboard_users where user_id = auth.uid();
  if v_role is null or (p_owner and v_role <> 'owner') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
end $$;

-- Real outlets only: the TEST outlet never appears in reports.
create function public.dashboard_outlet(p_outlet text) returns public.outlets
language plpgsql stable security definer set search_path = '' as $$
declare v public.outlets;
begin
  select * into v from public.outlets where code = p_outlet and code <> 'TEST';
  if not found then raise exception 'no outlet %', p_outlet; end if;
  return v;
end $$;

-- Sold orders in a date range with their cups. Cancelled orders don't count, the same as the POS Today screen.
create function public.dashboard_sold(p_outlet uuid, p_from date, p_to date)
returns table (id uuid, business_date date, total bigint, payment_method text, cashier_name text,
               paid_at timestamptz, done_at timestamptz, cups bigint)
language sql stable security definer set search_path = '' as $$
  select o.id, o.business_date, o.total, o.payment_method, o.cashier_name, o.paid_at, o.done_at,
         (select coalesce(sum(i.qty), 0) from public.order_items i where i.order_id = o.id)
  from public.orders o
  where o.outlet_id = p_outlet and o.business_date between p_from and p_to and o.status <> 'cancelled'
$$;

create function public.dashboard_totals(p_outlet uuid, p_from date, p_to date) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'sales', coalesce(sum(s.total), 0),
    'orders', count(*),
    'cups', coalesce(sum(s.cups), 0),
    'avg_order', coalesce(round(avg(s.total)), 0)
  ) from public.dashboard_sold(p_outlet, p_from, p_to) s
$$;

-- ── Called by the signed-in user ─────────────────────────────────────────────

create function public.my_access() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('email', u.email, 'role', u.role, 'must_change_password', u.must_change_password)
  from public.dashboard_users u where u.user_id = auth.uid()
$$;

create function public.password_changed() returns void
language sql security definer set search_path = '' as $$
  update public.dashboard_users set must_change_password = false where user_id = auth.uid()
$$;

create function public.report_outlets() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.dashboard_require();
  return (select coalesce(jsonb_agg(jsonb_build_object('code', o.code, 'name', o.name) order by o.created_at), '[]'::jsonb)
          from public.outlets o where o.code <> 'TEST');
end $$;

create function public.report_daily(p_outlet text, p_date date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v public.outlets;
begin
  perform public.dashboard_require();
  v := public.dashboard_outlet(p_outlet);
  return jsonb_build_object(
    'totals', public.dashboard_totals(v.id, p_date, p_date),
    'compare', public.dashboard_totals(v.id, p_date - 7, p_date - 7),
    'prep_median_min', (
      select round((percentile_cont(0.5) within group (order by extract(epoch from s.done_at - s.paid_at) / 60))::numeric, 0)
      from public.dashboard_sold(v.id, p_date, p_date) s
      where s.done_at is not null and s.done_at - s.paid_at < interval '2 hours'),
    'hours', (
      select coalesce(jsonb_agg(h order by h.hour), '[]'::jsonb) from (
        select extract(hour from s.paid_at at time zone v.timezone)::int as hour,
               count(*) as orders, sum(s.cups) as cups, sum(s.total) as sales
        from public.dashboard_sold(v.id, p_date, p_date) s group by 1) h),
    'top', (
      select coalesce(jsonb_agg(t order by t.cups desc, t.sales desc), '[]'::jsonb) from (
        select max(i.product_name) as name, sum(i.qty) as cups, sum(i.line_total) as sales
        from public.dashboard_sold(v.id, p_date, p_date) s
        join public.order_items i on i.order_id = s.id
        group by i.product_code order by 2 desc, 3 desc limit 5) t),
    'payments', (
      select jsonb_build_object(
        'cash', coalesce(sum(s.total) filter (where s.payment_method = 'cash'), 0),
        'qris', coalesce(sum(s.total) filter (where s.payment_method = 'qris'), 0))
      from public.dashboard_sold(v.id, p_date, p_date) s),
    'cashiers', (
      select coalesce(jsonb_agg(c order by c.cups desc), '[]'::jsonb) from (
        select s.cashier_name as name, sum(s.cups) as cups, sum(s.total) as sales
        from public.dashboard_sold(v.id, p_date, p_date) s group by 1) c),
    'sugar', (
      select coalesce(jsonb_object_agg(x.level, x.cups), '{}'::jsonb) from (
        select i.sugar_level as level, sum(i.qty) as cups
        from public.dashboard_sold(v.id, p_date, p_date) s
        join public.order_items i on i.order_id = s.id group by 1) x),
    'ice', (
      select coalesce(jsonb_object_agg(x.level, x.cups), '{}'::jsonb) from (
        select i.ice_level as level, sum(i.qty) as cups
        from public.dashboard_sold(v.id, p_date, p_date) s
        join public.order_items i on i.order_id = s.id group by 1) x),
    'cancelled', (
      select jsonb_build_object(
        'orders', count(*),
        'amount', coalesce(sum(o.total), 0),
        'top_reason', mode() within group (order by o.cancel_reason))
      from public.orders o
      where o.outlet_id = v.id and o.business_date = p_date and o.status = 'cancelled'),
    'freshness', jsonb_build_object(
      'last_received_at', (select max(o.received_at) from public.orders o where o.outlet_id = v.id),
      'device_seen_at', (select max(d.last_seen_at) from public.devices d where d.outlet_id = v.id and d.status = 'active'))
  );
end $$;

create function public.report_sales(p_outlet text, p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v public.outlets;
  v_len int := p_to - p_from + 1;
begin
  perform public.dashboard_require();
  v := public.dashboard_outlet(p_outlet);
  return jsonb_build_object(
    'totals', public.dashboard_totals(v.id, p_from, p_to),
    'previous', public.dashboard_totals(v.id, p_from - v_len, p_from - 1),
    'days', (
      select coalesce(jsonb_agg(d order by d.date), '[]'::jsonb) from (
        select s.business_date as date, count(*) as orders, sum(s.cups) as cups, sum(s.total) as sales,
               coalesce(sum(s.total) filter (where s.payment_method = 'cash'), 0) as cash,
               coalesce(sum(s.total) filter (where s.payment_method = 'qris'), 0) as qris
        from public.dashboard_sold(v.id, p_from, p_to) s group by 1) d),
    'weekdays', (
      select coalesce(jsonb_agg(w order by w.dow), '[]'::jsonb) from (
        select extract(isodow from x.date)::int as dow, round(avg(x.sales)) as avg_sales, round(avg(x.cups)) as avg_cups
        from (select s.business_date as date, sum(s.total) as sales, sum(s.cups) as cups
              from public.dashboard_sold(v.id, p_from, p_to) s group by 1) x
        group by 1) w)
  );
end $$;

create function public.report_products(p_outlet text, p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v public.outlets;
begin
  perform public.dashboard_require();
  v := public.dashboard_outlet(p_outlet);
  return (
    select coalesce(jsonb_agg(r order by r.cups desc, r.sales desc), '[]'::jsonb) from (
      select i.product_code as code, max(i.product_name) as name, coalesce(max(c.name), 'Other') as category,
             sum(i.qty) as cups, sum(i.line_total) as sales
      from public.dashboard_sold(v.id, p_from, p_to) s
      join public.order_items i on i.order_id = s.id
      left join public.products p on p.outlet_id = v.id and p.code = i.product_code
      left join public.categories c on c.id = p.category_id
      group by i.product_code) r);
end $$;

create function public.report_time(p_outlet text, p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v public.outlets;
begin
  perform public.dashboard_require();
  v := public.dashboard_outlet(p_outlet);
  return (
    with sold as (
      select s.*, s.paid_at at time zone v.timezone as local_at,
             extract(hour from s.paid_at at time zone v.timezone)::int as hour,
             extract(isodow from s.business_date)::int as dow,
             extract(epoch from s.done_at - s.paid_at) / 60 as prep_min
      from public.dashboard_sold(v.id, p_from, p_to) s
    ),
    open_days as (select dow, count(distinct business_date) as days from sold group by 1),
    prep as (select * from sold where prep_min is not null and prep_min < 120),
    peak as (select hour from sold group by 1 order by sum(cups) desc, hour limit 1),
    parts as (
      select case when s.hour < 11 then 1 when s.hour < 15 then 2 when s.hour < 18 then 3 else 4 end as part,
             max(i.product_name) as name, sum(i.qty) as cups
      from sold s join public.order_items i on i.order_id = s.id
      group by 1, i.product_code
    )
    select jsonb_build_object(
      'grid', (
        select coalesce(jsonb_agg(g), '[]'::jsonb) from (
          select s.dow, s.hour, sum(s.cups) as cups,
                 round(sum(s.cups)::numeric / max(d.days), 1) as avg_cups
          from sold s join open_days d using (dow) group by 1, 2) g),
      'weekday_cups', (
        select coalesce(jsonb_agg(w order by w.avg_cups desc), '[]'::jsonb) from (
          select s.dow, round(sum(s.cups)::numeric / max(d.days), 1) as avg_cups
          from sold s join open_days d using (dow) group by 1) w),
      'peak_hour', (select hour from peak),
      'prep', jsonb_build_object(
        'median', (select round((percentile_cont(0.5) within group (order by prep_min))::numeric, 0) from prep),
        'peak_median', (select round((percentile_cont(0.5) within group (order by prep_min))::numeric, 0)
                        from prep where hour = (select hour from peak)),
        'over_10_pct', (select round(100.0 * count(*) filter (where prep_min > 10) / nullif(count(*), 0)) from prep)),
      'dayparts', (
        select coalesce(jsonb_agg(t order by t.part), '[]'::jsonb) from (
          select distinct on (part) part, name, cups from parts order by part, cups desc) t)
    )
  );
end $$;

-- ── Owner only: people with access ───────────────────────────────────────────

create function public.list_dashboard_users() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.dashboard_require(true);
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'user_id', d.user_id, 'email', d.email, 'role', d.role,
      'invited', a.last_sign_in_at is null,
      'last_sign_in_at', a.last_sign_in_at,
      'is_me', d.user_id = auth.uid()
    ) order by d.created_at), '[]'::jsonb)
    from public.dashboard_users d join auth.users a on a.id = d.user_id);
end $$;

create function public.set_dashboard_role(p_user uuid, p_role text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public.dashboard_require(true);
  if p_user = auth.uid() then raise exception 'You can''t change your own role'; end if;
  update public.dashboard_users set role = p_role where user_id = p_user;
end $$;

-- ── Grants ───────────────────────────────────────────────────────────────────

revoke execute on function public.dashboard_bootstrap_owner() from public, anon, authenticated;
revoke execute on function public.dashboard_require(boolean) from public, anon, authenticated;
revoke execute on function public.dashboard_outlet(text) from public, anon, authenticated;
revoke execute on function public.dashboard_sold(uuid, date, date) from public, anon, authenticated;
revoke execute on function public.dashboard_totals(uuid, date, date) from public, anon, authenticated;

revoke execute on function public.my_access() from public, anon;
revoke execute on function public.password_changed() from public, anon;
revoke execute on function public.report_outlets() from public, anon;
revoke execute on function public.report_daily(text, date) from public, anon;
revoke execute on function public.report_sales(text, date, date) from public, anon;
revoke execute on function public.report_products(text, date, date) from public, anon;
revoke execute on function public.report_time(text, date, date) from public, anon;
revoke execute on function public.list_dashboard_users() from public, anon;
revoke execute on function public.set_dashboard_role(uuid, text) from public, anon;

grant execute on function public.my_access() to authenticated;
grant execute on function public.password_changed() to authenticated;
grant execute on function public.report_outlets() to authenticated;
grant execute on function public.report_daily(text, date) to authenticated;
grant execute on function public.report_sales(text, date, date) to authenticated;
grant execute on function public.report_products(text, date, date) to authenticated;
grant execute on function public.report_time(text, date, date) to authenticated;
grant execute on function public.list_dashboard_users() to authenticated;
grant execute on function public.set_dashboard_role(uuid, text) to authenticated;

notify pgrst, 'reload schema';
