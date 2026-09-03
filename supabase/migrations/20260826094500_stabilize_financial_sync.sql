-- Keep the rolling financial window visible to the planner. The default
-- analyze threshold (10% of the table) allowed the date histogram to lag by
-- almost two weeks, which made the fast sync choose an expensive nested-loop
-- plan and hit the authenticated role's 8 second statement timeout.
alter table public.app_financial_snapshots
  set (
    autovacuum_analyze_threshold = 50,
    autovacuum_analyze_scale_factor = 0.005
  );

-- The ETL is a trusted security-definer operation. Give this specific RPC
-- enough time to finish during short bursts of database load without raising
-- the timeout for the rest of the authenticated API.
alter function public.apply_financial_sync(uuid)
  set statement_timeout = '60s';

-- Repair the stale snapshot_date histogram immediately on deployment.
analyze public.app_financial_snapshots;
