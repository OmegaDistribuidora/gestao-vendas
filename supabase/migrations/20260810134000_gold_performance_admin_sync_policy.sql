grant select, insert, update, delete on table public.app_gold_performance to authenticated;

create policy "gold_performance_admin_sync"
on public.app_gold_performance
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());
