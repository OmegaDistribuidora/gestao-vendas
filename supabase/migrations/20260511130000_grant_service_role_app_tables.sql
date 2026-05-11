grant usage on schema public to service_role;
grant select, insert, update, delete on public.app_profiles to service_role;
grant select, insert, update, delete on public.app_users to service_role;
grant select, insert, update, delete on public.app_modules to service_role;
grant select, insert, update, delete on public.app_user_module_accesses to service_role;
grant select, insert, update, delete on public.app_login_events to service_role;
grant select, insert, update, delete on public.app_module_usage_events to service_role;
