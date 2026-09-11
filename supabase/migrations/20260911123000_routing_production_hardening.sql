-- Permite que a DAG use a conta administrativa de ETL ja existente, sem
-- distribuir a chave service_role em um novo arquivo operacional.
create or replace function public.app_apply_daily_routing_snapshot(snapshot jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
    select 1
    from jsonb_array_elements(snapshot->'items') item
    group by item->>'seller_code', item->>'customer_code'
    having count(*) > 1
  ) or exists (
    select 1
    from jsonb_array_elements(snapshot->'sellers') seller
    group by seller->>'seller_code'
    having count(*) > 1
  ) then
    raise exception 'Ocorrencias ou vendedores duplicados.';
  end if;

  insert into public.app_daily_routing_snapshots(
    reference_date,
    snapshot_id,
    source_updated_at,
    payload
  )
  values (
    (snapshot->>'reference_date')::date,
    snapshot->>'snapshot_id',
    (snapshot->>'source_updated_at')::timestamptz,
    snapshot
  )
  on conflict(reference_date) do update
    set snapshot_id = excluded.snapshot_id,
        source_updated_at = excluded.source_updated_at,
        payload = excluded.payload,
        synced_at = now()
  where excluded.source_updated_at >= app_daily_routing_snapshots.source_updated_at;
end;
$$;

revoke all on function public.app_apply_daily_routing_snapshot(jsonb)
  from public, anon, authenticated;
grant execute on function public.app_apply_daily_routing_snapshot(jsonb)
  to authenticated, service_role;
