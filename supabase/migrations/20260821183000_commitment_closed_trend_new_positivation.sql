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

  if date_trunc('month', target_start_date)
     <> date_trunc('month', target_end_date) then
    raise exception 'O periodo do compromisso deve estar dentro do mesmo mes.';
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
      coalesce((overall_payload ->> 'new_positivation')::integer, 0),
    'last_updated_at', payload -> 'last_updated_at'
  );
end;
$$;

revoke all on function public.get_commitment_actual(text, text, date, date)
  from public, anon, authenticated;

create or replace function public.get_commitment_closed_actual(
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
  closed_end_date date := least(
    target_end_date,
    timezone('America/Sao_Paulo', now())::date - 1
  );
  payload jsonb;
  overall_payload jsonb;
begin
  if closed_end_date < target_start_date then
    return jsonb_build_object(
      'financial_closed_actual', 0,
      'positivation_closed_actual', 0
    );
  end if;

  if date_trunc('month', target_start_date)
     <> date_trunc('month', target_end_date) then
    raise exception 'O periodo do compromisso deve estar dentro do mesmo mes.';
  end if;

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
      'financial_closed_actual', 0,
      'positivation_closed_actual', 0
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
        extract(year from closed_end_date)::integer,
        extract(month from closed_end_date)::integer,
        extract(day from closed_end_date)::integer,
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
    'financial_closed_actual',
      coalesce((overall_payload ->> 'gross_amount')::numeric, 0)
      + coalesce((overall_payload ->> 'return_amount')::numeric, 0),
    'positivation_closed_actual',
      coalesce((overall_payload ->> 'new_positivation')::integer, 0)
  );
end;
$$;

revoke all on function public.get_commitment_closed_actual(text, text, date, date)
  from public, anon, authenticated;

alter function public.get_commitment_overview(date, date, text, text)
  rename to get_commitment_overview_base;

revoke all on function public.get_commitment_overview_base(date, date, text, text)
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
  payload jsonb;
  enriched_items jsonb := '[]'::jsonb;
  item_record record;
  closed_actual jsonb;
  selected_start_date date;
  selected_end_date date;
begin
  payload := public.get_commitment_overview_base(
    target_start_date,
    target_end_date,
    target_scope_profile_slug,
    target_scope_owner_code
  );

  selected_start_date := (payload ->> 'selected_start_date')::date;
  selected_end_date := (payload ->> 'selected_end_date')::date;

  if selected_start_date is null or selected_end_date is null then
    return payload;
  end if;

  if date_trunc('month', selected_start_date)
     <> date_trunc('month', selected_end_date) then
    raise exception 'O periodo do compromisso deve estar dentro do mesmo mes.';
  end if;

  for item_record in
    select item.value
    from jsonb_array_elements(coalesce(payload -> 'items', '[]'::jsonb)) item
  loop
    closed_actual := public.get_commitment_closed_actual(
      item_record.value ->> 'profile_slug',
      item_record.value ->> 'owner_code',
      selected_start_date,
      selected_end_date
    );
    enriched_items := enriched_items || jsonb_build_array(
      item_record.value || closed_actual
    );
  end loop;

  return payload || jsonb_build_object('items', enriched_items);
end;
$$;

revoke all on function public.get_commitment_overview(date, date, text, text)
  from public, anon;
grant execute on function public.get_commitment_overview(date, date, text, text)
  to authenticated;

comment on function public.get_commitment_actual(text, text, date, date) is
  'Realizado ao vivo do compromisso com positivacao de clientes novos no mes.';

comment on function public.get_commitment_closed_actual(text, text, date, date) is
  'Bases do compromisso encerradas ate ontem para media e tendencia.';

comment on function public.get_commitment_overview(date, date, text, text) is
  'Metas, realizado ao vivo e bases encerradas para tendencia do compromisso.';
