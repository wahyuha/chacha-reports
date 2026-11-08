-- Chacha Reports: drinks ordered with less sugar, zero sugar or less ice.
-- Normal sugar and ice are left out on purpose. Counts are cups; cancelled orders don't count.

create function public.report_custom(p_outlet text, p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v public.outlets;
begin
  perform public.dashboard_require();
  v := public.dashboard_outlet(p_outlet);
  return (
    select coalesce(jsonb_agg(d order by d.less_sugar + d.zero_sugar desc, d.less_ice desc, d.cups desc), '[]'::jsonb)
    from (
      select i.product_code as code, max(i.product_name) as name, coalesce(max(c.name), 'Other') as category,
             sum(i.qty) as cups,
             coalesce(sum(i.qty) filter (where i.sugar_level = 'less'), 0) as less_sugar,
             coalesce(sum(i.qty) filter (where i.sugar_level = 'zero'), 0) as zero_sugar,
             coalesce(sum(i.qty) filter (where i.ice_level = 'less'), 0) as less_ice
      from public.dashboard_sold(v.id, p_from, p_to) s
      join public.order_items i on i.order_id = s.id
      left join public.products p on p.outlet_id = v.id and p.code = i.product_code
      left join public.categories c on c.id = p.category_id
      group by i.product_code
    ) d
    where d.less_sugar + d.zero_sugar + d.less_ice > 0);
end $$;

revoke execute on function public.report_custom(text, date, date) from public, anon;
grant execute on function public.report_custom(text, date, date) to authenticated;

notify pgrst, 'reload schema';
