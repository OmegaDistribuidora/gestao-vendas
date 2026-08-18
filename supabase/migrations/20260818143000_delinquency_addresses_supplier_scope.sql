create or replace function public.get_delinquency_overview_v2(
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
  enriched_clients jsonb;
  enriched_groups jsonb;
begin
  payload := public.get_delinquency_overview(
    target_scope_profile_slug,
    target_scope_owner_code
  );

  select coalesce(
    jsonb_agg(
      client_row || jsonb_build_object(
        'address', trim(both ' - ' from concat_ws(
          ' - ',
          nullif(btrim(customer.end_compl), ''),
          nullif(btrim(customer.bairro), ''),
          nullif(btrim(customer.cidade), '')
        ))
      )
      order by client_ordinality
    ),
    '[]'::jsonb
  )
  into enriched_clients
  from jsonb_array_elements(coalesce(payload -> 'clients', '[]'::jsonb))
    with ordinality as client_data(client_row, client_ordinality)
  left join public.app_customers customer
    on customer.codcli = client_row ->> 'codcli';

  select coalesce(
    jsonb_agg(
      group_row || jsonb_build_object(
        'clients', coalesce((
          select jsonb_agg(
            nested_client || jsonb_build_object(
              'address', trim(both ' - ' from concat_ws(
                ' - ',
                nullif(btrim(nested_customer.end_compl), ''),
                nullif(btrim(nested_customer.bairro), ''),
                nullif(btrim(nested_customer.cidade), '')
              ))
            )
            order by nested_ordinality
          )
          from jsonb_array_elements(coalesce(group_row -> 'clients', '[]'::jsonb))
            with ordinality as nested_data(nested_client, nested_ordinality)
          left join public.app_customers nested_customer
            on nested_customer.codcli = nested_client ->> 'codcli'
        ), '[]'::jsonb)
      )
      order by group_ordinality
    ),
    '[]'::jsonb
  )
  into enriched_groups
  from jsonb_array_elements(coalesce(payload -> 'groups', '[]'::jsonb))
    with ordinality as group_data(group_row, group_ordinality);

  return jsonb_set(
    jsonb_set(payload, '{clients}', enriched_clients, true),
    '{groups}',
    enriched_groups,
    true
  );
end;
$$;

revoke all on function public.get_delinquency_overview_v2(text, text)
  from public, anon;
grant execute on function public.get_delinquency_overview_v2(text, text)
  to authenticated;

create or replace function public.get_supplier_analysis_v2(
  window_start timestamptz,
  window_end timestamptz,
  metric_source text default 'venda',
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
  target_auth_user_id uuid;
  original_auth_user_id text;
  available_scopes jsonb;
  payload jsonb;
begin
  select p.slug, u.code
    into viewer_profile_slug, viewer_user_code
  from public.app_users u
  join public.app_profiles p on p.id = u.profile_id
  where u.auth_user_id = auth.uid()
    and u.is_active
  limit 1;

  if viewer_profile_slug is null then
    raise exception 'Usuario nao encontrado.';
  end if;

  requested_profile_slug := nullif(
    lower(trim(coalesce(target_scope_profile_slug, ''))),
    ''
  );
  requested_owner_code := nullif(
    trim(coalesce(target_scope_owner_code, '')),
    ''
  );

  if (requested_profile_slug is null) <> (requested_owner_code is null) then
    raise exception 'Escopo da analise por fornecedor incompleto.';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'profile_slug', scope.profile_slug,
        'owner_code', scope.owner_code,
        'display_name', scope.display_name,
        'label', scope.profile_name || ' • ' || scope.owner_code || ' - ' || scope.display_name
      )
      order by
        case scope.profile_slug when 'supervisor' then 1 else 2 end,
        scope.display_name,
        scope.owner_code
    ),
    '[]'::jsonb
  )
  into available_scopes
  from (
    select
      profile.slug as profile_slug,
      case profile.slug
        when 'supervisor' then 'Supervisor'
        else 'Vendedor'
      end as profile_name,
      candidate.code as owner_code,
      coalesce(nullif(btrim(candidate.display_name), ''), candidate.code) as display_name
    from public.app_users candidate
    join public.app_profiles profile on profile.id = candidate.profile_id
    where candidate.is_active
      and candidate.auth_user_id is not null
      and profile.slug in ('supervisor', 'vendedor')
      and case
        when viewer_profile_slug = 'supervisor' then
          profile.slug = 'vendedor'
          and coalesce(candidate.supervisor_code, '') = viewer_user_code
        when viewer_profile_slug = 'coordenador' then
          coalesce(candidate.coordinator_code, '') = viewer_user_code
        when viewer_profile_slug in ('admin', 'diretoria', 'outros') then true
        else false
      end
  ) scope;

  if requested_profile_slug is not null then
    select candidate.auth_user_id
      into target_auth_user_id
    from public.app_users candidate
    join public.app_profiles profile on profile.id = candidate.profile_id
    where candidate.is_active
      and candidate.auth_user_id is not null
      and profile.slug = requested_profile_slug
      and candidate.code = requested_owner_code
      and requested_profile_slug in ('supervisor', 'vendedor')
      and case
        when viewer_profile_slug = 'supervisor' then
          requested_profile_slug = 'vendedor'
          and coalesce(candidate.supervisor_code, '') = viewer_user_code
        when viewer_profile_slug = 'coordenador' then
          coalesce(candidate.coordinator_code, '') = viewer_user_code
        when viewer_profile_slug in ('admin', 'diretoria', 'outros') then true
        else false
      end
    limit 1;

    if target_auth_user_id is null then
      raise exception 'Escopo da analise por fornecedor invalido.';
    end if;
  end if;

  if target_auth_user_id is null then
    payload := public.get_supplier_analysis(
      window_start,
      window_end,
      metric_source
    );
  else
    original_auth_user_id := current_setting('request.jwt.claim.sub', true);
    begin
      perform set_config(
        'request.jwt.claim.sub',
        target_auth_user_id::text,
        true
      );
      payload := public.get_supplier_analysis(
        window_start,
        window_end,
        metric_source
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
  end if;

  return payload || jsonb_build_object(
    'viewer_profile_slug', viewer_profile_slug,
    'selected_scope_profile_slug', requested_profile_slug,
    'selected_scope_owner_code', requested_owner_code,
    'available_scopes', available_scopes
  );
end;
$$;

revoke all on function public.get_supplier_analysis_v2(
  timestamptz,
  timestamptz,
  text,
  text,
  text
) from public, anon;
grant execute on function public.get_supplier_analysis_v2(
  timestamptz,
  timestamptz,
  text,
  text,
  text
) to authenticated;
