create or replace function public.exclude_hidden_customer_opportunity_activity()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if btrim(coalesce(new.activity_code, '')) = '42' then
    return null;
  end if;

  return new;
end;
$$;

revoke all on function public.exclude_hidden_customer_opportunity_activity()
  from public;

drop trigger if exists exclude_hidden_customer_opportunity_activity
  on public.app_customer_opportunities;
create trigger exclude_hidden_customer_opportunity_activity
before insert or update of activity_code
on public.app_customer_opportunities
for each row
execute function public.exclude_hidden_customer_opportunity_activity();

delete from public.app_customer_opportunities
where btrim(coalesce(activity_code, '')) = '42';
