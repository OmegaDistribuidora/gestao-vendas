create or replace function public.sync_supervisor_coordinator_hierarchy()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(new.supervisor_code, '') = ''
     or coalesce(new.coordinator_code, '') = '' then
    return new;
  end if;

  update public.app_users supervisor
     set coordinator_code = new.coordinator_code,
         coordinator_name = coalesce(
           nullif(btrim(new.coordinator_name), ''),
           supervisor.coordinator_name
         )
   where supervisor.code = new.supervisor_code
     and (
       supervisor.coordinator_code is distinct from new.coordinator_code
       or (
         nullif(btrim(new.coordinator_name), '') is not null
         and supervisor.coordinator_name is distinct from new.coordinator_name
       )
     );

  return new;
end;
$$;

drop trigger if exists sync_supervisor_coordinator_from_seller
  on public.app_users;
create trigger sync_supervisor_coordinator_from_seller
after insert or update of supervisor_code, coordinator_code, coordinator_name
on public.app_users
for each row
execute function public.sync_supervisor_coordinator_hierarchy();

with seller_relations as (
  select
    seller.supervisor_code,
    seller.coordinator_code,
    max(seller.coordinator_name) as coordinator_name,
    count(*) as seller_count,
    row_number() over (
      partition by seller.supervisor_code
      order by count(*) desc, seller.coordinator_code
    ) as relation_rank
  from public.app_users seller
  join public.app_profiles profile on profile.id = seller.profile_id
  where profile.slug = 'vendedor'
    and seller.is_active
    and coalesce(seller.supervisor_code, '') <> ''
    and coalesce(seller.coordinator_code, '') <> ''
  group by seller.supervisor_code, seller.coordinator_code
)
update public.app_users supervisor
   set coordinator_code = relation.coordinator_code,
       coordinator_name = coalesce(
         nullif(btrim(relation.coordinator_name), ''),
         supervisor.coordinator_name
       )
  from seller_relations relation
 where relation.relation_rank = 1
   and supervisor.code = relation.supervisor_code
   and (
     supervisor.coordinator_code is distinct from relation.coordinator_code
     or (
       nullif(btrim(relation.coordinator_name), '') is not null
       and supervisor.coordinator_name is distinct from relation.coordinator_name
     )
   );
