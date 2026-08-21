create table if not exists public.app_commitments (
  profile_slug text not null,
  owner_code text not null,
  financial_target numeric(18, 2) not null default 0,
  positivation_target numeric(18, 2) not null default 0,
  start_date date not null,
  end_date date not null,
  source_inserted_at timestamp without time zone,
  synced_at timestamptz not null default now(),
  primary key (profile_slug, owner_code, start_date, end_date),
  constraint app_commitments_profile_check
    check (profile_slug in ('supervisor', 'coordenador')),
  constraint app_commitments_owner_code_check
    check (btrim(owner_code) <> ''),
  constraint app_commitments_targets_check
    check (financial_target >= 0 and positivation_target >= 0),
  constraint app_commitments_period_check
    check (end_date >= start_date)
);

create index if not exists idx_app_commitments_period
  on public.app_commitments (start_date desc, end_date desc);

create index if not exists idx_app_commitments_owner
  on public.app_commitments (profile_slug, owner_code);

alter table public.app_commitments enable row level security;
revoke all on table public.app_commitments from public, anon, authenticated;
grant select, insert, update, delete on table public.app_commitments
  to service_role;

create table if not exists public.app_commitment_sync_state (
  singleton boolean primary key default true check (singleton),
  source_checksum text not null,
  row_count integer not null default 0,
  synced_at timestamptz not null default now()
);

alter table public.app_commitment_sync_state enable row level security;
revoke all on table public.app_commitment_sync_state
  from public, anon, authenticated;
grant select, insert, update, delete on table public.app_commitment_sync_state
  to service_role;

create or replace function public.apply_commitments_sync(
  p_rows jsonb,
  p_source_checksum text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  caller_profile_slug text;
  normalized_checksum text;
  staged_count integer;
  changed_count integer;
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
    raise exception 'Usuario sem permissao para sincronizar compromissos.';
  end if;

  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'Carga de compromissos invalida.';
  end if;

  normalized_checksum := nullif(btrim(coalesce(p_source_checksum, '')), '');
  if normalized_checksum is null then
    raise exception 'Checksum da carga de compromissos ausente.';
  end if;

  create temporary table commitment_sync_rows (
    profile_slug text not null,
    owner_code text not null,
    financial_target numeric(18, 2) not null,
    positivation_target numeric(18, 2) not null,
    start_date date not null,
    end_date date not null,
    source_inserted_at timestamp without time zone,
    primary key (profile_slug, owner_code, start_date, end_date)
  ) on commit drop;

  insert into commitment_sync_rows (
    profile_slug,
    owner_code,
    financial_target,
    positivation_target,
    start_date,
    end_date,
    source_inserted_at
  )
  select
    case lower(btrim(source_row.tipo))
      when 'supervisor' then 'supervisor'
      when 'coordenador' then 'coordenador'
      else lower(btrim(source_row.tipo))
    end,
    btrim(source_row.codigo),
    coalesce(source_row.meta_financeira, 0),
    coalesce(source_row.meta_positivacao, 0),
    source_row.data_inicio,
    source_row.data_fim,
    source_row.data_insercao
  from jsonb_to_recordset(p_rows) as source_row(
    tipo text,
    codigo text,
    meta_financeira numeric,
    meta_positivacao numeric,
    data_inicio date,
    data_fim date,
    data_insercao timestamp without time zone
  );

  if exists (
    select 1
    from commitment_sync_rows
    where profile_slug not in ('supervisor', 'coordenador')
       or owner_code = ''
       or financial_target < 0
       or positivation_target < 0
       or end_date < start_date
  ) then
    raise exception 'A carga contem um compromisso invalido.';
  end if;

  select count(*) into staged_count from commitment_sync_rows;

  with upserted as (
    insert into public.app_commitments as target (
      profile_slug,
      owner_code,
      financial_target,
      positivation_target,
      start_date,
      end_date,
      source_inserted_at,
      synced_at
    )
    select
      profile_slug,
      owner_code,
      financial_target,
      positivation_target,
      start_date,
      end_date,
      source_inserted_at,
      now()
    from commitment_sync_rows
    on conflict (profile_slug, owner_code, start_date, end_date)
    do update set
      financial_target = excluded.financial_target,
      positivation_target = excluded.positivation_target,
      source_inserted_at = excluded.source_inserted_at,
      synced_at = excluded.synced_at
    where target.financial_target is distinct from excluded.financial_target
       or target.positivation_target is distinct from excluded.positivation_target
       or target.source_inserted_at is distinct from excluded.source_inserted_at
    returning 1
  ), deleted as (
    delete from public.app_commitments existing
    where not exists (
      select 1
      from commitment_sync_rows staged
      where staged.profile_slug = existing.profile_slug
        and staged.owner_code = existing.owner_code
        and staged.start_date = existing.start_date
        and staged.end_date = existing.end_date
    )
    returning 1
  )
  select
    (select count(*) from upserted) + (select count(*) from deleted)
  into changed_count;

  insert into public.app_commitment_sync_state (
    singleton,
    source_checksum,
    row_count,
    synced_at
  ) values (
    true,
    normalized_checksum,
    staged_count,
    now()
  )
  on conflict (singleton) do update set
    source_checksum = excluded.source_checksum,
    row_count = excluded.row_count,
    synced_at = excluded.synced_at;

  return jsonb_build_object(
    'source_checksum', normalized_checksum,
    'rows', staged_count,
    'changed_rows', changed_count,
    'synced_at', now()
  );
end;
$$;

revoke all on function public.apply_commitments_sync(jsonb, text)
  from public, anon;
grant execute on function public.apply_commitments_sync(jsonb, text)
  to authenticated, service_role;

create or replace function public.get_commitment_actual(
  target_profile_slug text,
  target_owner_code text,
  target_start_date date,
  target_end_date date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  target_auth_user_id uuid;
  original_auth_user_id text;
  payload jsonb;
  overall_payload jsonb;
begin
  select app_user.auth_user_id
    into target_auth_user_id
  from public.app_users app_user
  join public.app_profiles profile on profile.id = app_user.profile_id
  where app_user.is_active
    and app_user.auth_user_id is not null
    and profile.slug = target_profile_slug
    and app_user.code = target_owner_code
  limit 1;

  if target_auth_user_id is null then
    return jsonb_build_object(
      'financial_actual', 0,
      'positivation_actual', 0,
      'last_updated_at', null
    );
  end if;

  original_auth_user_id := current_setting('request.jwt.claim.sub', true);
  begin
    perform set_config('request.jwt.claim.sub', target_auth_user_id::text, true);
    payload := public.get_supplier_analysis(
      make_timestamptz(
        extract(year from target_start_date)::integer,
        extract(month from target_start_date)::integer,
        extract(day from target_start_date)::integer,
        0, 0, 0,
        'America/Sao_Paulo'
      ),
      make_timestamptz(
        extract(year from target_end_date)::integer,
        extract(month from target_end_date)::integer,
        extract(day from target_end_date)::integer,
        23, 59, 59,
        'America/Sao_Paulo'
      ),
      'venda'
    );
  exception when others then
    perform set_config(
      'request.jwt.claim.sub',
      coalesce(original_auth_user_id, ''),
      true
    );
    raise;
  end;
  perform set_config(
    'request.jwt.claim.sub',
    coalesce(original_auth_user_id, ''),
    true
  );

  overall_payload := payload -> 'overall';
  return jsonb_build_object(
    'financial_actual',
      coalesce((overall_payload ->> 'gross_amount')::numeric, 0)
      + coalesce((overall_payload ->> 'return_amount')::numeric, 0),
    'positivation_actual',
      coalesce((overall_payload ->> 'net_positivation')::integer, 0),
    'last_updated_at', payload -> 'last_updated_at'
  );
end;
$$;

revoke all on function public.get_commitment_actual(text, text, date, date)
  from public, anon, authenticated;

create or replace function public.get_commitment_overview(
  target_start_date date default null,
  target_end_date date default null,
  target_scope_profile_slug text default null,
  target_scope_owner_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  viewer_profile_slug text;
  viewer_user_code text;
  requested_profile_slug text;
  requested_owner_code text;
  selected_start_date date;
  selected_end_date date;
  available_periods jsonb := '[]'::jsonb;
  available_scopes jsonb := '[]'::jsonb;
  items jsonb := '[]'::jsonb;
  target_record record;
  actual_payload jsonb;
  newest_data_at timestamptz;
begin
  select profile.slug, app_user.code
    into viewer_profile_slug, viewer_user_code
  from public.app_users app_user
  join public.app_profiles profile on profile.id = app_user.profile_id
  where app_user.auth_user_id = auth.uid()
    and app_user.is_active
  limit 1;

  if viewer_profile_slug not in (
    'supervisor', 'coordenador', 'diretoria', 'outros'
  ) then
    raise exception 'Perfil sem acesso ao modulo de compromissos.';
  end if;

  requested_profile_slug := nullif(
    lower(btrim(coalesce(target_scope_profile_slug, ''))),
    ''
  );
  requested_owner_code := nullif(
    btrim(coalesce(target_scope_owner_code, '')),
    ''
  );

  if (target_start_date is null) <> (target_end_date is null) then
    raise exception 'Periodo do compromisso incompleto.';
  end if;
  if target_start_date is not null and target_end_date < target_start_date then
    raise exception 'Periodo do compromisso invalido.';
  end if;
  if (requested_profile_slug is null) <> (requested_owner_code is null) then
    raise exception 'Filtro de usuario incompleto.';
  end if;
  if requested_profile_slug is not null
     and viewer_profile_slug not in ('diretoria', 'outros') then
    raise exception 'Filtro de usuario indisponivel para este perfil.';
  end if;
  if requested_profile_slug is not null
     and requested_profile_slug not in ('supervisor', 'coordenador') then
    raise exception 'Perfil de compromisso invalido.';
  end if;

  with visible_periods as (
    select distinct commitment.start_date, commitment.end_date
    from public.app_commitments commitment
    where case
      when viewer_profile_slug = 'supervisor' then
        commitment.profile_slug = 'supervisor'
        and commitment.owner_code = viewer_user_code
      when viewer_profile_slug = 'coordenador' then
        (
          commitment.profile_slug = 'coordenador'
          and commitment.owner_code = viewer_user_code
        ) or (
          commitment.profile_slug = 'supervisor'
          and exists (
            select 1
            from public.app_users subordinate
            join public.app_profiles subordinate_profile
              on subordinate_profile.id = subordinate.profile_id
            where subordinate.is_active
              and subordinate_profile.slug = 'supervisor'
              and subordinate.code = commitment.owner_code
              and coalesce(subordinate.coordinator_code, '') = viewer_user_code
          )
        )
      else true
    end
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'start_date', start_date,
        'end_date', end_date
      ) order by start_date desc, end_date desc
    ),
    '[]'::jsonb
  )
  into available_periods
  from visible_periods;

  if target_start_date is not null then
    if not exists (
      select 1
      from jsonb_array_elements(available_periods) period
      where (period ->> 'start_date')::date = target_start_date
        and (period ->> 'end_date')::date = target_end_date
    ) then
      raise exception 'Periodo de compromisso indisponivel.';
    end if;
    selected_start_date := target_start_date;
    selected_end_date := target_end_date;
  else
    select
      (period ->> 'start_date')::date,
      (period ->> 'end_date')::date
    into selected_start_date, selected_end_date
    from jsonb_array_elements(available_periods) period
    order by
      case
        when current_date between
          (period ->> 'start_date')::date
          and (period ->> 'end_date')::date then 0
        else 1
      end,
      (period ->> 'start_date')::date desc,
      (period ->> 'end_date')::date desc
    limit 1;
  end if;

  if selected_start_date is null then
    return jsonb_build_object(
      'viewer_profile_slug', viewer_profile_slug,
      'selected_start_date', null,
      'selected_end_date', null,
      'selected_scope_profile_slug', requested_profile_slug,
      'selected_scope_owner_code', requested_owner_code,
      'available_periods', available_periods,
      'available_scopes', '[]'::jsonb,
      'items', '[]'::jsonb,
      'last_updated_at', null
    );
  end if;

  with supervisor_scopes as (
    select distinct
      'supervisor'::text as profile_slug,
      commitment.owner_code,
      coalesce(nullif(btrim(app_user.display_name), ''), commitment.owner_code)
        as display_name
    from public.app_commitments commitment
    left join public.app_profiles profile on profile.slug = 'supervisor'
    left join public.app_users app_user
      on app_user.profile_id = profile.id
     and app_user.code = commitment.owner_code
     and app_user.is_active
    where commitment.profile_slug = 'supervisor'
      and commitment.start_date = selected_start_date
      and commitment.end_date = selected_end_date
  ), coordinator_scopes as (
    select distinct
      'coordenador'::text as profile_slug,
      coordinator.code as owner_code,
      coalesce(nullif(btrim(coordinator.display_name), ''), coordinator.code)
        as display_name
    from public.app_users coordinator
    join public.app_profiles coordinator_profile
      on coordinator_profile.id = coordinator.profile_id
    where coordinator.is_active
      and coordinator_profile.slug = 'coordenador'
      and (
        exists (
          select 1
          from public.app_users supervisor
          join public.app_profiles supervisor_profile
            on supervisor_profile.id = supervisor.profile_id
          join public.app_commitments commitment
            on commitment.profile_slug = 'supervisor'
           and commitment.owner_code = supervisor.code
           and commitment.start_date = selected_start_date
           and commitment.end_date = selected_end_date
          where supervisor.is_active
            and supervisor_profile.slug = 'supervisor'
            and coalesce(supervisor.coordinator_code, '') = coordinator.code
        )
        or exists (
          select 1
          from public.app_commitments direct_commitment
          where direct_commitment.profile_slug = 'coordenador'
            and direct_commitment.owner_code = coordinator.code
            and direct_commitment.start_date = selected_start_date
            and direct_commitment.end_date = selected_end_date
        )
      )
  ), all_scopes as (
    select * from supervisor_scopes
    union all
    select * from coordinator_scopes
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'profile_slug', profile_slug,
        'owner_code', owner_code,
        'display_name', display_name,
        'label', case profile_slug
          when 'coordenador' then 'Coordenador'
          else 'Supervisor'
        end || ' - ' || owner_code || ' - ' || display_name
      ) order by
        case profile_slug when 'coordenador' then 1 else 2 end,
        display_name,
        owner_code
    ),
    '[]'::jsonb
  )
  into available_scopes
  from all_scopes;

  if requested_profile_slug is not null and not exists (
    select 1
    from jsonb_array_elements(available_scopes) scope
    where scope ->> 'profile_slug' = requested_profile_slug
      and scope ->> 'owner_code' = requested_owner_code
  ) then
    raise exception 'Usuario indisponivel para o compromisso selecionado.';
  end if;

  for target_record in
    with supervisor_targets as (
      select
        'supervisor'::text as profile_slug,
        commitment.owner_code,
        coalesce(nullif(btrim(app_user.display_name), ''), commitment.owner_code)
          as display_name,
        commitment.financial_target,
        commitment.positivation_target
      from public.app_commitments commitment
      left join public.app_profiles profile on profile.slug = 'supervisor'
      left join public.app_users app_user
        on app_user.profile_id = profile.id
       and app_user.code = commitment.owner_code
       and app_user.is_active
      where commitment.profile_slug = 'supervisor'
        and commitment.start_date = selected_start_date
        and commitment.end_date = selected_end_date
    ), coordinator_targets as (
      select
        'coordenador'::text as profile_slug,
        coordinator.code as owner_code,
        coalesce(nullif(btrim(coordinator.display_name), ''), coordinator.code)
          as display_name,
        case when count(supervisor_commitment.owner_code) > 0
          then coalesce(sum(supervisor_commitment.financial_target), 0)
          else coalesce(max(direct_commitment.financial_target), 0)
        end as financial_target,
        case when count(supervisor_commitment.owner_code) > 0
          then coalesce(sum(supervisor_commitment.positivation_target), 0)
          else coalesce(max(direct_commitment.positivation_target), 0)
        end as positivation_target
      from public.app_users coordinator
      join public.app_profiles coordinator_profile
        on coordinator_profile.id = coordinator.profile_id
      left join public.app_users supervisor
        on supervisor.coordinator_code = coordinator.code
       and supervisor.is_active
      left join public.app_profiles supervisor_profile
        on supervisor_profile.id = supervisor.profile_id
       and supervisor_profile.slug = 'supervisor'
      left join public.app_commitments supervisor_commitment
        on supervisor_commitment.profile_slug = 'supervisor'
       and supervisor_profile.slug = 'supervisor'
       and supervisor_commitment.owner_code = supervisor.code
       and supervisor_commitment.start_date = selected_start_date
       and supervisor_commitment.end_date = selected_end_date
      left join public.app_commitments direct_commitment
        on direct_commitment.profile_slug = 'coordenador'
       and direct_commitment.owner_code = coordinator.code
       and direct_commitment.start_date = selected_start_date
       and direct_commitment.end_date = selected_end_date
      where coordinator.is_active
        and coordinator_profile.slug = 'coordenador'
      group by coordinator.code, coordinator.display_name
      having count(supervisor_commitment.owner_code) > 0
          or count(direct_commitment.owner_code) > 0
    ), candidate_targets as (
      select * from supervisor_targets
      union all
      select * from coordinator_targets
    )
    select *
    from candidate_targets candidate
    where case
      when viewer_profile_slug = 'supervisor' then
        candidate.profile_slug = 'supervisor'
        and candidate.owner_code = viewer_user_code
      when viewer_profile_slug = 'coordenador' then
        candidate.profile_slug = 'coordenador'
        and candidate.owner_code = viewer_user_code
      else
        requested_profile_slug is null
        or (
          candidate.profile_slug = requested_profile_slug
          and candidate.owner_code = requested_owner_code
        )
    end
    order by
      case candidate.profile_slug when 'coordenador' then 1 else 2 end,
      candidate.display_name,
      candidate.owner_code
  loop
    actual_payload := public.get_commitment_actual(
      target_record.profile_slug,
      target_record.owner_code,
      selected_start_date,
      selected_end_date
    );

    if actual_payload ->> 'last_updated_at' is not null then
      newest_data_at := greatest(
        coalesce(newest_data_at, '-infinity'::timestamptz),
        (actual_payload ->> 'last_updated_at')::timestamptz
      );
    end if;

    items := items || jsonb_build_array(jsonb_build_object(
      'profile_slug', target_record.profile_slug,
      'owner_code', target_record.owner_code,
      'display_name', target_record.display_name,
      'financial_target', target_record.financial_target,
      'positivation_target', target_record.positivation_target,
      'financial_actual', actual_payload -> 'financial_actual',
      'positivation_actual', actual_payload -> 'positivation_actual',
      'last_updated_at', actual_payload -> 'last_updated_at'
    ));
  end loop;

  return jsonb_build_object(
    'viewer_profile_slug', viewer_profile_slug,
    'selected_start_date', selected_start_date,
    'selected_end_date', selected_end_date,
    'selected_scope_profile_slug', requested_profile_slug,
    'selected_scope_owner_code', requested_owner_code,
    'available_periods', available_periods,
    'available_scopes', case
      when viewer_profile_slug in ('diretoria', 'outros')
        then available_scopes
      else '[]'::jsonb
    end,
    'items', items,
    'last_updated_at', newest_data_at
  );
end;
$$;

revoke all on function public.get_commitment_overview(date, date, text, text)
  from public, anon;
grant execute on function public.get_commitment_overview(date, date, text, text)
  to authenticated;

comment on table public.app_commitments is
  'Compromissos comerciais sincronizados de filial.tauxcompromisso.';

comment on function public.get_commitment_overview(date, date, text, text) is
  'Metas de compromisso e realizado liquido do periodo, calculado pela mesma base da Analise por Fornecedor.';
