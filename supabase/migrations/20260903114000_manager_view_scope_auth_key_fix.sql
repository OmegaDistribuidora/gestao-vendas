-- Correcao da chave substituta introduzida na migration anterior.
-- app_users usa auth_user_id como chave primaria e nao possui coluna id.

do $$
declare
  function_definition text;
begin
  select pg_get_functiondef(
    'public.app_view_scope_options(text[])'::regprocedure
  ) into function_definition;

  if position('app_user.id::text' in function_definition) = 0 then
    raise exception 'Definicao inesperada de app_view_scope_options.';
  end if;

  execute replace(
    function_definition,
    'app_user.id::text',
    'app_user.auth_user_id::text'
  );

  select pg_get_functiondef(
    'public.app_resolve_view_scope_auth_user(text,text,text[])'::regprocedure
  ) into function_definition;

  if position('app_user.id::text' in function_definition) = 0 then
    raise exception 'Definicao inesperada de app_resolve_view_scope_auth_user.';
  end if;

  execute replace(
    function_definition,
    'app_user.id::text',
    'app_user.auth_user_id::text'
  );
end;
$$;

comment on function public.app_view_scope_options(text[]) is
  'Lista segura de visoes; Gerencia usa auth_user_id quando nao possui codigo.';
