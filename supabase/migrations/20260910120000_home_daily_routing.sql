-- Additive API, unused by released clients. Publish only after emulator review.
create table public.app_daily_routing_snapshots (
  reference_date date primary key,
  snapshot_id text not null,
  source_updated_at timestamptz not null,
  payload jsonb not null,
  synced_at timestamptz not null default now()
);
alter table public.app_daily_routing_snapshots enable row level security;
revoke all on public.app_daily_routing_snapshots from public, anon, authenticated;
grant all on public.app_daily_routing_snapshots to service_role;

create function public.app_apply_daily_routing_snapshot(snapshot jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare
  caller_profile_slug text;
begin
  select profile.slug
    into caller_profile_slug
  from public.app_users app_user
  join public.app_profiles profile on profile.id = app_user.profile_id
  where app_user.auth_user_id = auth.uid()
    and app_user.is_active
  limit 1;

  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role'
     and caller_profile_slug <> 'admin' then
    raise exception 'Usuario sem permissao para sincronizar o roteiro.';
  end if;

  if jsonb_typeof(snapshot->'items') is distinct from 'array'
     or jsonb_typeof(snapshot->'sellers') is distinct from 'array'
     or coalesce(jsonb_array_length(snapshot->'sellers'),0)=0
     or nullif(snapshot->>'snapshot_id','') is null
     or nullif(snapshot->>'source_updated_at','') is null then
    raise exception 'Snapshot de roteiro incompleto.';
  end if;
  if exists (
    select 1 from jsonb_array_elements(snapshot->'items') i
    group by i->>'seller_code',i->>'customer_code' having count(*)>1
  ) or exists (
    select 1 from jsonb_array_elements(snapshot->'sellers') s
    group by s->>'seller_code' having count(*)>1
  ) then raise exception 'Ocorrencias ou vendedores duplicados.'; end if;
  insert into public.app_daily_routing_snapshots(reference_date,snapshot_id,source_updated_at,payload)
  values ((snapshot->>'reference_date')::date,snapshot->>'snapshot_id',
          (snapshot->>'source_updated_at')::timestamptz,snapshot)
  on conflict(reference_date) do update set
    snapshot_id=excluded.snapshot_id, source_updated_at=excluded.source_updated_at,
    payload=excluded.payload,synced_at=now()
  where excluded.source_updated_at >= app_daily_routing_snapshots.source_updated_at;
end $$;
revoke all on function public.app_apply_daily_routing_snapshot(jsonb) from public,anon,authenticated;
grant execute on function public.app_apply_daily_routing_snapshot(jsonb)
  to authenticated,service_role;

create function public.get_home_daily_routing(
  target_date date,
  target_scope_profile_slug text default null,
  target_scope_owner_code text default null,
  include_details boolean default false,
  item_filter text default 'all',
  page_offset integer default 0,
  page_size integer default 100,
  expected_snapshot_id text default null
)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  effective_id uuid := auth.uid();
  profile_slug text;
  owner_code text;
  snapshot jsonb;
  applicable boolean := true;
  result jsonb;
begin
  if not exists(select 1 from public.app_users where auth_user_id=effective_id and is_active) then
    raise exception 'Usuario nao encontrado.';
  end if;
  if (nullif(trim(target_scope_profile_slug),'') is null) <>
     (nullif(trim(target_scope_owner_code),'') is null) then
    raise exception 'Filtro incompleto.';
  end if;
  if nullif(trim(target_scope_profile_slug),'') is not null then
    effective_id := public.app_resolve_view_scope_auth_user(target_scope_profile_slug,target_scope_owner_code);
    if effective_id is null then raise exception 'Visao nao autorizada.'; end if;
  end if;
  select p.slug,u.code into profile_slug,owner_code
  from public.app_users u join public.app_profiles p on p.id=u.profile_id
  where u.auth_user_id=effective_id and u.is_active;
  if profile_slug is null then raise exception 'Usuario indisponivel.'; end if;
  if item_filter not in ('all','purchased','pending') then raise exception 'Filtro invalido.'; end if;
  select payload into snapshot from public.app_daily_routing_snapshots where reference_date=target_date;
  if snapshot is null then
    return jsonb_build_object('available',false,'reference_date',target_date,'items','[]'::jsonb);
  end if;
  if expected_snapshot_id is not null and expected_snapshot_id <> snapshot->>'snapshot_id' then
    raise exception 'ROUTING_SNAPSHOT_CHANGED';
  end if;
  applicable := case
    when profile_slug='supervisor' then owner_code not in ('33','35')
    when profile_slug='vendedor' then exists (
      select 1 from jsonb_array_elements(snapshot->'sellers') s
      where s->>'seller_code'=owner_code and (s->>'eligible')::boolean
    )
    else profile_slug in ('coordenador','gerencia','diretoria','outros','admin') end;
  with sellers as (
    select s from jsonb_array_elements(snapshot->'sellers') s
    where applicable and (s->>'eligible')::boolean
      and public.app_scope_matches(profile_slug,owner_code,s->>'seller_code',
                                   s->>'supervisor_code',s->>'coordinator_code')
  ), occurrences as (
    select i || jsonb_build_object('seller_name',s->>'seller_name') as item
    from jsonb_array_elements(snapshot->'items') i
    join sellers on s->>'seller_code'=i->>'seller_code'
  ), totals as (
    select count(*) as planned, count(*) filter(where (item->>'purchased')::boolean) as purchased
    from occurrences
  ), filtered as (
    select item from occurrences where item_filter='all'
       or (item->>'purchased')::boolean=(item_filter='purchased')
  ), page as (
    select item from filtered where include_details
    order by lower(item->>'customer_name'),item->>'customer_code',item->>'seller_code'
    limit least(greatest(page_size,1),200) offset greatest(page_offset,0)
  )
  select jsonb_build_object(
    'available',true,'applicable',applicable,'reference_date',target_date,
    'effective_profile_slug',profile_slug,'snapshot_id',snapshot->>'snapshot_id',
    'source_updated_at',snapshot->>'source_updated_at',
    'planned',t.planned,'purchased',t.purchased,'pending',t.planned-t.purchased,
    'percent',case when t.planned>0 then round(t.purchased::numeric*100/t.planned,2) else null end,
    'filtered_count',(select count(*) from filtered),
    'items',coalesce((select jsonb_agg(item) from page),'[]'::jsonb)
  ) into result from totals t;
  return result;
end $$;
revoke all on function public.get_home_daily_routing(date,text,text,boolean,text,integer,integer,text) from public,anon;
grant execute on function public.get_home_daily_routing(date,text,text,boolean,text,integer,integer,text) to authenticated,service_role;
