create table if not exists public.app_sales_daily_snapshots (
  id uuid primary key default gen_random_uuid(),
  sales_date date not null,
  numped text not null,
  codcli text not null,
  codusur text not null,
  venda numeric not null default 0,
  volume numeric not null default 0,
  imported_at timestamptz not null default timezone('utc', now()),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (sales_date, numped, codcli, codusur)
);

create index if not exists idx_app_sales_daily_snapshots_date_user
  on public.app_sales_daily_snapshots (sales_date, codusur);

drop trigger if exists set_app_sales_daily_snapshots_updated_at on public.app_sales_daily_snapshots;
create trigger set_app_sales_daily_snapshots_updated_at
before update on public.app_sales_daily_snapshots
for each row
execute function public.set_updated_at();

grant select, insert, update, delete on public.app_sales_daily_snapshots to authenticated, service_role;

alter table public.app_sales_daily_snapshots enable row level security;

drop policy if exists "sales_daily_snapshots_admin_manage" on public.app_sales_daily_snapshots;
create policy "sales_daily_snapshots_admin_manage"
on public.app_sales_daily_snapshots
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

create or replace function public.get_seller_home_kpis(target_user_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_code text;
  current_profile_slug text;
  current_user_code text;
  payload jsonb;
begin
  normalized_code := trim(coalesce(target_user_code, ''));

  if normalized_code = '' then
    return jsonb_build_object(
      'venda_hoje', 0,
      'volume_hoje', 0,
      'pedidos_hoje', 0,
      'positivacao_hoje', 0
    );
  end if;

  select p.slug, u.code
    into current_profile_slug, current_user_code
  from public.app_users u
  left join public.app_profiles p on p.id = u.profile_id
  where u.auth_user_id = auth.uid()
  limit 1;

  if current_profile_slug is null then
    raise exception 'Usuário não encontrado.';
  end if;

  if current_profile_slug <> 'admin' and current_user_code <> normalized_code then
    raise exception 'Acesso negado.';
  end if;

  select jsonb_build_object(
    'venda_hoje', coalesce(round(sum(s.venda), 2), 0),
    'volume_hoje', coalesce(round(sum(s.volume), 2), 0),
    'pedidos_hoje', coalesce(count(distinct s.numped), 0),
    'positivacao_hoje', coalesce(count(distinct s.codcli), 0)
  )
    into payload
  from public.app_sales_daily_snapshots s
  where s.sales_date = current_date
    and s.codusur = normalized_code;

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

grant execute on function public.get_seller_home_kpis(text) to authenticated;
