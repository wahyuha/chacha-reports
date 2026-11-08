-- Chacha Reports: HPP (cost per cup) and gross margin.
--
-- HPP per cup = ingredients + packaging, as in the "Final HPP_Chacha" sheet. Staff, rent and utilities are not
-- part of it. Each change is a new row with an effective_from date, so past days keep the HPP they were sold at.
-- Margin per order line = line_total - qty * HPP, using the price charged at sale time. Lines whose drink has no
-- HPP yet are counted apart, never as pure margin. Only owners can read costs or margins.

create table public.menu_costs (
  outlet_id      uuid not null references public.outlets (id) on delete cascade,
  product_code   text not null,
  effective_from date not null,
  ingredients    bigint not null check (ingredients >= 0),
  packaging      bigint not null check (packaging >= 0),
  updated_by     uuid references auth.users (id) on delete set null,
  updated_at     timestamptz not null default now(),
  primary key (outlet_id, product_code, effective_from)
);

alter table public.menu_costs enable row level security;
revoke all on public.menu_costs from anon, authenticated;

-- Starting values from the sheet's "Ringkasan" tab, rounded to whole rupiah, for every outlet with that drink.
insert into public.menu_costs (outlet_id, product_code, effective_from, ingredients, packaging)
select p.outlet_id, p.code, date '2026-01-01', c.ingredients, c.packaging
from public.products p
join (values
  ('cmt', 5389, 2540), ('cjm', 5825, 2540), ('pom', 6793, 2540), ('rom', 6115, 2540), ('jmt', 5206, 2540),
  ('pml', 5427, 2540), ('mcl', 6263, 1000), ('mcr', 8563, 1000), ('mco', 7629, 1000), ('mub', 9163, 1000),
  ('mca', 6523, 1223), ('mcm', 8163, 1000), ('jst', 4071, 1223), ('pot', 4058, 1223), ('mgt', 3736, 1223)
) as c (code, ingredients, packaging) on c.code = p.code
on conflict do nothing;

-- ── Internal helpers: not callable from the browser ──────────────────────────

-- Sold order lines with the HPP per cup that applied on their business day (null when none was set).
create function public.dashboard_cost_lines(p_outlet uuid, p_from date, p_to date)
returns table (business_date date, product_code text, cups bigint, sales bigint, hpp bigint)
language sql stable security definer set search_path = '' as $$
  select s.business_date, i.product_code, i.qty::bigint, i.line_total, c.hpp
  from public.dashboard_sold(p_outlet, p_from, p_to) s
  join public.order_items i on i.order_id = s.id
  left join lateral (
    select mc.ingredients + mc.packaging as hpp from public.menu_costs mc
    where mc.outlet_id = p_outlet and mc.product_code = i.product_code and mc.effective_from <= s.business_date
    order by mc.effective_from desc limit 1
  ) c on true
$$;

-- ── Owner only ───────────────────────────────────────────────────────────────

-- cost and costed_sales cover only lines with an HPP; margin = costed_sales - cost.
create function public.report_margin(p_outlet text, p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v public.outlets;
begin
  perform public.dashboard_require(true);
  v := public.dashboard_outlet(p_outlet);
  return (
    with l as (select * from public.dashboard_cost_lines(v.id, p_from, p_to))
    select jsonb_build_object(
      'totals', (
        select jsonb_build_object(
          'cups', coalesce(sum(cups), 0),
          'sales', coalesce(sum(sales), 0),
          'cost', coalesce(sum(cups * hpp), 0),
          'costed_sales', coalesce(sum(sales) filter (where hpp is not null), 0),
          'uncosted_cups', coalesce(sum(cups) filter (where hpp is null), 0))
        from l),
      'products', (
        select coalesce(jsonb_agg(p order by p.code), '[]'::jsonb) from (
          select product_code as code, sum(cups) as cups, sum(sales) as sales,
                 coalesce(sum(cups * hpp), 0) as cost,
                 coalesce(sum(sales) filter (where hpp is not null), 0) as costed_sales,
                 coalesce(sum(cups) filter (where hpp is null), 0) as uncosted_cups
          from l group by product_code) p),
      'days', (
        select coalesce(jsonb_agg(d order by d.date), '[]'::jsonb) from (
          select business_date as date, sum(cups) as cups, sum(sales) as sales,
                 coalesce(sum(cups * hpp), 0) as cost,
                 coalesce(sum(sales) filter (where hpp is not null), 0) as costed_sales,
                 coalesce(sum(cups) filter (where hpp is null), 0) as uncosted_cups
          from l group by business_date) d)
    ));
end $$;

-- Every drink on the menu (and any with a cost) with its HPP today and its full history, newest first.
create function public.menu_costs_list(p_outlet text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v public.outlets; v_today date;
begin
  perform public.dashboard_require(true);
  v := public.dashboard_outlet(p_outlet);
  v_today := public.outlet_today(v);
  return (
    select coalesce(jsonb_agg(r order by r.sort_cat, r.sort_order, r.name), '[]'::jsonb) from (
      select p.code, p.name, coalesce(c.name, 'Other') as category, p.price, p.active,
             coalesce(c.sort_order, 999) as sort_cat, p.sort_order,
             (select jsonb_build_object('from', mc.effective_from, 'ingredients', mc.ingredients, 'packaging', mc.packaging)
              from public.menu_costs mc
              where mc.outlet_id = v.id and mc.product_code = p.code and mc.effective_from <= v_today
              order by mc.effective_from desc limit 1) as current,
             (select coalesce(jsonb_agg(jsonb_build_object('from', mc.effective_from, 'ingredients', mc.ingredients,
                                                           'packaging', mc.packaging, 'updated_at', mc.updated_at)
                                        order by mc.effective_from desc), '[]'::jsonb)
              from public.menu_costs mc where mc.outlet_id = v.id and mc.product_code = p.code) as history
      from public.products p
      left join public.categories c on c.id = p.category_id
      where p.outlet_id = v.id
        and (p.active or exists (select 1 from public.menu_costs mc where mc.outlet_id = v.id and mc.product_code = p.code))
    ) r);
end $$;

create function public.menu_cost_save(p_outlet text, p_code text, p_from date, p_ingredients bigint, p_packaging bigint)
returns void
language plpgsql security definer set search_path = '' as $$
declare v public.outlets;
begin
  perform public.dashboard_require(true);
  v := public.dashboard_outlet(p_outlet);
  if not exists (select 1 from public.products where outlet_id = v.id and code = p_code) then
    raise exception 'no such drink';
  end if;
  if p_from is null then raise exception 'Choose the date it applies from'; end if;
  if p_ingredients is null or p_packaging is null or p_ingredients < 0 or p_packaging < 0 then
    raise exception 'Costs can''t be empty or negative';
  end if;
  insert into public.menu_costs (outlet_id, product_code, effective_from, ingredients, packaging, updated_by)
  values (v.id, p_code, p_from, p_ingredients, p_packaging, auth.uid())
  on conflict (outlet_id, product_code, effective_from) do update
    set ingredients = excluded.ingredients, packaging = excluded.packaging,
        updated_by = excluded.updated_by, updated_at = now();
end $$;

create function public.menu_cost_delete(p_outlet text, p_code text, p_from date) returns void
language plpgsql security definer set search_path = '' as $$
declare v public.outlets;
begin
  perform public.dashboard_require(true);
  v := public.dashboard_outlet(p_outlet);
  delete from public.menu_costs where outlet_id = v.id and product_code = p_code and effective_from = p_from;
  if not found then raise exception 'no such cost'; end if;
end $$;

-- ── Grants ───────────────────────────────────────────────────────────────────

revoke execute on function public.dashboard_cost_lines(uuid, date, date) from public, anon, authenticated;

revoke execute on function public.report_margin(text, date, date) from public, anon;
revoke execute on function public.menu_costs_list(text) from public, anon;
revoke execute on function public.menu_cost_save(text, text, date, bigint, bigint) from public, anon;
revoke execute on function public.menu_cost_delete(text, text, date) from public, anon;

grant execute on function public.report_margin(text, date, date) to authenticated;
grant execute on function public.menu_costs_list(text) to authenticated;
grant execute on function public.menu_cost_save(text, text, date, bigint, bigint) to authenticated;
grant execute on function public.menu_cost_delete(text, text, date) to authenticated;

notify pgrst, 'reload schema';
