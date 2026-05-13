alter table public.app_sales_daily_snapshots
  add column if not exists codsupervisor text not null default '',
  add column if not exists codgerente text not null default '',
  add column if not exists codfornec text not null default '';

alter table public.app_sales_daily_snapshots
  drop constraint if exists app_sales_daily_snapshots_sales_date_numped_codcli_codusur_key;

truncate table public.app_sales_daily_snapshots;

alter table public.app_sales_daily_snapshots
  drop constraint if exists app_sales_daily_snapshots_unique_snapshot;

alter table public.app_sales_daily_snapshots
  add constraint app_sales_daily_snapshots_unique_snapshot
  unique (sales_date, numped, codcli, codusur, codfornec);

drop index if exists idx_app_sales_daily_snapshots_date_user;

create index if not exists idx_app_sales_daily_snapshots_date_user
  on public.app_sales_daily_snapshots (sales_date, codusur);

create index if not exists idx_app_sales_daily_snapshots_date_supervisor
  on public.app_sales_daily_snapshots (sales_date, codsupervisor);

create index if not exists idx_app_sales_daily_snapshots_date_manager
  on public.app_sales_daily_snapshots (sales_date, codgerente);

create index if not exists idx_app_sales_daily_snapshots_date_supplier
  on public.app_sales_daily_snapshots (sales_date, codfornec);

create or replace function public.get_home_kpis()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile_slug text;
  current_user_code text;
  payload jsonb;
begin
  select p.slug, u.code
    into current_profile_slug, current_user_code
  from public.app_users u
  left join public.app_profiles p on p.id = u.profile_id
  where u.auth_user_id = auth.uid()
  limit 1;

  if current_profile_slug is null then
    raise exception 'Usuário não encontrado.';
  end if;

  select jsonb_build_object(
    'venda_hoje', coalesce(round(sum(s.venda), 2), 0),
    'volume_hoje', coalesce(round(sum(s.volume), 2), 2),
    'pedidos_hoje', coalesce(count(distinct s.numped), 0),
    'positivacao_hoje', coalesce(count(distinct s.codcli), 0)
  )
    into payload
  from public.app_sales_daily_snapshots s
  where s.sales_date = current_date
    and (
      case
        when current_profile_slug = 'vendedor' then s.codusur = current_user_code
        when current_profile_slug = 'supervisor' then s.codsupervisor = current_user_code
        when current_profile_slug = 'coordenador' then s.codgerente = current_user_code
        else true
      end
    );

  return coalesce(
    payload,
    jsonb_build_object(
      'venda_hoje', 0,
      'volume_hoje', 0,
      'pedidos_hoje', 0,
      'positivacao_hoje', 0
    )
  );
end;
$$;

grant execute on function public.get_home_kpis() to authenticated;
