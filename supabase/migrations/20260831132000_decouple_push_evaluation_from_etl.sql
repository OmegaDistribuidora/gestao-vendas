-- Push evaluation can execute expensive monthly aggregations. It must never run
-- inside the transaction that publishes an Oracle -> Supabase synchronization,
-- otherwise a notification timeout rolls back fresh commercial data.
drop trigger if exists evaluate_push_notifications_after_sync
  on public.etl_sync_runs;

comment on function public.handle_push_relevant_sync_applied() is
  'Legacy trigger handler retained for compatibility. Push evaluation is invoked after ETL commit by the sync workers and is best-effort.';
