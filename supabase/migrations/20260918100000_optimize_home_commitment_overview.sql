-- A Home de Diretoria/Outros/Gerencia utiliza somente os itens dos
-- coordenadores para compor o compromisso geral. A consulta completa tambem
-- calculava todos os supervisores e depois o app descartava esses itens.
-- Esta funcao reutiliza o calculo oficial, mas somente para os coordenadores
-- visiveis e participantes do periodo selecionado.
create or replace function public.get_home_commitment_overview()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  viewer_profile_slug text;
  coordinator_scope record;
  partial_payload jsonb;
  base_payload jsonb;
  coordinator_items jsonb := '[]'::jsonb;
  newest_data_at timestamptz;
begin
  select profile.slug
    into viewer_profile_slug
  from public.app_users app_user
  join public.app_profiles profile on profile.id = app_user.profile_id
  where app_user.auth_user_id = auth.uid()
    and app_user.is_active
  limit 1;

  if viewer_profile_slug is null then
    raise exception 'Usuario nao encontrado.';
  end if;

  if viewer_profile_slug not in ('diretoria', 'outros', 'gerencia') then
    return public.get_commitment_overview(null, null, null, null);
  end if;

  for coordinator_scope in
    select option.value ->> 'owner_code' as owner_code
    from jsonb_array_elements(
      public.app_view_scope_options(array['coordenador']::text[])
    ) option(value)
    order by option.value ->> 'owner_code'
  loop
    begin
      partial_payload := public.get_commitment_overview(
        null,
        null,
        'coordenador',
        coordinator_scope.owner_code
      );
    exception when raise_exception then
      -- Coordenadores sem compromisso no periodo selecionado nao fazem parte
      -- do total da empresa e ja eram ignorados pela apresentacao da Home.
      if sqlerrm in (
        'Usuario indisponivel para o compromisso selecionado.',
        'Periodo de compromisso indisponivel.'
      ) then
        continue;
      end if;
      raise;
    end;

    if base_payload is null then
      base_payload := partial_payload;
    end if;

    coordinator_items := coordinator_items || coalesce((
      select jsonb_agg(item.value order by item.ordinality)
      from jsonb_array_elements(
        coalesce(partial_payload -> 'items', '[]'::jsonb)
      ) with ordinality as item(value, ordinality)
      where item.value ->> 'profile_slug' = 'coordenador'
    ), '[]'::jsonb);

    if partial_payload ->> 'last_updated_at' is not null then
      newest_data_at := greatest(
        coalesce(newest_data_at, '-infinity'::timestamptz),
        (partial_payload ->> 'last_updated_at')::timestamptz
      );
    end if;
  end loop;

  -- Sem coordenador participante, a consulta completa e pequena e preserva
  -- exatamente o retorno vazio/sem periodo da regra oficial.
  if base_payload is null then
    return public.get_commitment_overview(null, null, null, null);
  end if;

  return base_payload || jsonb_build_object(
    'viewer_profile_slug', viewer_profile_slug,
    'selected_scope_profile_slug', null,
    'selected_scope_owner_code', null,
    'available_scopes', '[]'::jsonb,
    'items', coordinator_items,
    'last_updated_at', newest_data_at
  );
end;
$$;

revoke all on function public.get_home_commitment_overview()
  from public, anon;
grant execute on function public.get_home_commitment_overview()
  to authenticated;

comment on function public.get_home_commitment_overview() is
  'Compromisso enxuto da Home: perfis gerais calculam somente coordenadores visiveis.';

-- Mantem toda a Home atual e troca somente a origem do bloco de compromisso.
do $$
declare
  original_definition text;
  optimized_definition text;
begin
  original_definition := pg_get_functiondef(
    'public.get_home_dashboard_v3(timestamptz,timestamptz,text,text)'::regprocedure
  );

  optimized_definition := regexp_replace(
    original_definition,
    'commitment_overview[[:space:]]*:=[[:space:]]*public\.get_commitment_overview\([[:space:]]*null,[[:space:]]*null,[[:space:]]*null,[[:space:]]*null[[:space:]]*\);',
    'commitment_overview := public.get_home_commitment_overview();',
    'i'
  );

  if optimized_definition = original_definition
     or position(
       'commitment_overview := public.get_home_commitment_overview();'
       in optimized_definition
     ) = 0 then
    raise exception 'Nao foi possivel otimizar o compromisso da Home.';
  end if;

  execute optimized_definition;
end;
$$;
