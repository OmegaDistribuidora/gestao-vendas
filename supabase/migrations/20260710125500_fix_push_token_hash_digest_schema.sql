create or replace function public.register_push_token(
  target_fcm_token text,
  target_device_id text,
  target_platform text default 'android',
  target_app_version text default null,
  target_remember_login_enabled boolean default false,
  target_notifications_enabled boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_row record;
  normalized_token text;
  normalized_device_id text;
  normalized_platform text;
  computed_token_hash text;
  token_row_id uuid;
  should_enable boolean;
begin
  if auth.uid() is null then
    raise exception 'Sessao autenticada obrigatoria.';
  end if;

  normalized_token := btrim(coalesce(target_fcm_token, ''));
  normalized_device_id := btrim(coalesce(target_device_id, ''));
  normalized_platform := lower(btrim(coalesce(target_platform, 'android')));

  if normalized_token = '' then
    raise exception 'Token FCM obrigatorio.';
  end if;

  if normalized_device_id = '' then
    normalized_device_id := 'unknown:' || auth.uid()::text;
  end if;

  select
    u.auth_user_id,
    u.code,
    coalesce(p.slug, 'sem_perfil') as profile_slug,
    u.is_active
    into current_user_row
  from public.app_users u
  left join public.app_profiles p on p.id = u.profile_id
  where u.auth_user_id = auth.uid()
  limit 1;

  if current_user_row.auth_user_id is null then
    raise exception 'Usuario nao encontrado.';
  end if;

  computed_token_hash := encode(
    extensions.digest(convert_to(normalized_token, 'UTF8'), 'sha256'::text),
    'hex'
  );
  should_enable :=
    current_user_row.is_active
    and current_user_row.profile_slug in ('vendedor', 'supervisor', 'coordenador')
    and coalesce(target_remember_login_enabled, false)
    and coalesce(target_notifications_enabled, false);

  if not should_enable then
    update public.app_push_tokens
       set enabled = false,
           notifications_enabled = coalesce(target_notifications_enabled, false),
           remember_login_enabled = coalesce(target_remember_login_enabled, false),
           revoked_at = timezone('utc', now()),
           last_seen_at = timezone('utc', now())
     where token_hash = computed_token_hash
        or (user_id = current_user_row.auth_user_id and device_id = normalized_device_id);

    return jsonb_build_object(
      'registered', false,
      'enabled', false,
      'profile_slug', current_user_row.profile_slug
    );
  end if;

  update public.app_push_tokens
     set enabled = false,
         revoked_at = timezone('utc', now()),
         last_seen_at = timezone('utc', now())
   where enabled = true
     and device_id = normalized_device_id
     and user_id <> current_user_row.auth_user_id;

  insert into public.app_push_tokens (
    user_id,
    profile_slug,
    user_code,
    fcm_token,
    token_hash,
    device_id,
    platform,
    app_version,
    remember_login_enabled,
    notifications_enabled,
    enabled,
    revoked_at,
    last_seen_at
  )
  values (
    current_user_row.auth_user_id,
    current_user_row.profile_slug,
    current_user_row.code,
    normalized_token,
    computed_token_hash,
    normalized_device_id,
    normalized_platform,
    nullif(btrim(coalesce(target_app_version, '')), ''),
    true,
    true,
    true,
    null,
    timezone('utc', now())
  )
  on conflict (token_hash) do update
     set user_id = excluded.user_id,
         profile_slug = excluded.profile_slug,
         user_code = excluded.user_code,
         fcm_token = excluded.fcm_token,
         device_id = excluded.device_id,
         platform = excluded.platform,
         app_version = excluded.app_version,
         remember_login_enabled = true,
         notifications_enabled = true,
         enabled = true,
         revoked_at = null,
         last_seen_at = timezone('utc', now())
  returning id into token_row_id;

  return jsonb_build_object(
    'registered', true,
    'enabled', true,
    'token_id', token_row_id,
    'profile_slug', current_user_row.profile_slug
  );
end;
$$;

create or replace function public.revoke_push_token(
  target_fcm_token text default null,
  target_device_id text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_token text;
  normalized_device_id text;
  computed_token_hash text;
begin
  if auth.uid() is null then
    return;
  end if;

  normalized_token := btrim(coalesce(target_fcm_token, ''));
  normalized_device_id := btrim(coalesce(target_device_id, ''));

  if normalized_token <> '' then
    computed_token_hash := encode(
      extensions.digest(convert_to(normalized_token, 'UTF8'), 'sha256'::text),
      'hex'
    );
  end if;

  update public.app_push_tokens
     set enabled = false,
         remember_login_enabled = false,
         revoked_at = timezone('utc', now()),
         last_seen_at = timezone('utc', now())
   where user_id = auth.uid()
     and (
       (computed_token_hash is not null and token_hash = computed_token_hash)
       or (normalized_device_id <> '' and device_id = normalized_device_id)
       or (computed_token_hash is null and normalized_device_id = '')
     );
end;
$$;
