drop function if exists public.get_home_kpis();

create or replace function public.get_home_kpis(
  window_start timestamptz,
  window_end timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile_slug text;
  current_user_code text;
  start_date date;
  end_date date;
  payload jsonb;
begin
  select p.slug, u.code
    into current_profile_slug, current_user_code
  from public.app_users u
  left join public.app_profiles p on p.id = u.profile_id
  where u.auth_user_id = auth.uid()
  limit 1;

  if current_profile_slug is null then
    raise exception 'Usuario nao encontrado.';
  end if;

  start_date := date(window_start at time zone 'America/Sao_Paulo');
  end_date := date(window_end at time zone 'America/Sao_Paulo');

  if start_date is null or end_date is null then
    raise exception 'Periodo invalido.';
  end if;

  if end_date < start_date then
    raise exception 'Periodo invalido.';
  end if;

  select jsonb_build_object(
    'total_venda', coalesce(round(sum(s.venda), 2), 0),
    'total_volume', coalesce(round(sum(s.volume), 2), 0),
    'total_pedidos', coalesce(count(distinct s.numped), 0),
    'total_positivacao', coalesce(count(distinct s.codcli), 0)
  )
    into payload
  from public.app_sales_daily_snapshots s
  where s.sales_date between start_date and end_date
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
      'total_venda', 0,
      'total_volume', 0,
      'total_pedidos', 0,
      'total_positivacao', 0
    )
  );
end;
$$;

grant execute on function public.get_home_kpis(timestamptz, timestamptz) to authenticated;

create or replace function public.resolve_login_context(login_identifier text)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  normalized_input text;
  matched_email text;
  matched_requires_admin_password_definition boolean;
  exact_display_count integer;
  alias_count integer;
begin
  normalized_input := lower(trim(coalesce(login_identifier, '')));

  if normalized_input = '' then
    return null;
  end if;

  select
    u.technical_email,
    coalesce(u.requires_admin_password_definition, false)
  into
    matched_email,
    matched_requires_admin_password_definition
  from public.app_users u
  left join public.app_profiles p
    on p.id = u.profile_id
  where lower(u.code) = normalized_input
    and coalesce(p.slug, '') in ('vendedor', 'admin')
  limit 1;

  if matched_email is not null then
    return jsonb_build_object(
      'technical_email', matched_email,
      'requires_admin_password_definition', matched_requires_admin_password_definition
    );
  end if;

  select count(*)
    into exact_display_count
  from public.app_users u
  left join public.app_profiles p
    on p.id = u.profile_id
  where lower(trim(coalesce(u.display_name, ''))) = normalized_input
    and coalesce(p.slug, '') <> 'vendedor';

  if exact_display_count > 1 then
    raise exception 'Nome de exibicao duplicado.';
  end if;

  select
    u.technical_email,
    coalesce(u.requires_admin_password_definition, false)
  into
    matched_email,
    matched_requires_admin_password_definition
  from public.app_users u
  left join public.app_profiles p
    on p.id = u.profile_id
  where lower(trim(coalesce(u.display_name, ''))) = normalized_input
    and coalesce(p.slug, '') <> 'vendedor'
  limit 1;

  if matched_email is not null then
    return jsonb_build_object(
      'technical_email', matched_email,
      'requires_admin_password_definition', matched_requires_admin_password_definition
    );
  end if;

  select count(*)
    into alias_count
  from public.app_users u
  left join public.app_profiles p
    on p.id = u.profile_id
  where lower(
      split_part(
        trim(split_part(coalesce(u.display_name, ''), '/', 1)),
        ' ',
        1
      )
    ) = normalized_input
    and coalesce(p.slug, '') in ('supervisor', 'coordenador');

  if alias_count > 1 then
    raise exception 'Primeiro nome duplicado.';
  end if;

  select
    u.technical_email,
    coalesce(u.requires_admin_password_definition, false)
  into
    matched_email,
    matched_requires_admin_password_definition
  from public.app_users u
  left join public.app_profiles p
    on p.id = u.profile_id
  where lower(
      split_part(
        trim(split_part(coalesce(u.display_name, ''), '/', 1)),
        ' ',
        1
      )
    ) = normalized_input
    and coalesce(p.slug, '') in ('supervisor', 'coordenador')
  limit 1;

  if matched_email is null then
    return null;
  end if;

  return jsonb_build_object(
    'technical_email', matched_email,
    'requires_admin_password_definition', matched_requires_admin_password_definition
  );
end;
$$;

grant execute on function public.resolve_login_context(text) to anon, authenticated;
