create or replace function public.mark_sync_run_failed(
  p_run_id uuid,
  p_error_message text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.etl_stg_sales_daily_snapshots
  where run_id = p_run_id;

  delete from public.etl_stg_financial_snapshots
  where run_id = p_run_id;

  delete from public.etl_stg_return_order_items
  where run_id = p_run_id;

  delete from public.etl_stg_customer_seller_bases
  where run_id = p_run_id;

  delete from public.etl_stg_customers
  where run_id = p_run_id;

  delete from public.etl_stg_sales_order_items
  where run_id = p_run_id;

  delete from public.etl_stg_customer_opportunities
  where run_id = p_run_id;

  update public.etl_sync_runs
     set status = 'failed',
         error_message = nullif(left(coalesce(p_error_message, ''), 4000), ''),
         finished_at = timezone('utc', now())
   where id = p_run_id;
end;
$$;

grant execute on function public.mark_sync_run_failed(uuid, text)
  to authenticated, service_role;

begin;

lock table
  public.etl_stg_sales_daily_snapshots,
  public.etl_stg_financial_snapshots,
  public.etl_stg_return_order_items,
  public.etl_stg_customer_seller_bases,
  public.etl_stg_customers,
  public.etl_stg_sales_order_items,
  public.etl_stg_customer_opportunities
in access exclusive mode;

do $$
begin
  if exists (
    select 1
    from (
      select run_id from public.etl_stg_sales_daily_snapshots
      union all
      select run_id from public.etl_stg_financial_snapshots
      union all
      select run_id from public.etl_stg_return_order_items
      union all
      select run_id from public.etl_stg_customer_seller_bases
      union all
      select run_id from public.etl_stg_customers
      union all
      select run_id from public.etl_stg_sales_order_items
      union all
      select run_id from public.etl_stg_customer_opportunities
    ) staging
    left join public.etl_sync_runs run on run.id = staging.run_id
    where coalesce(run.status, '') not in ('applied', 'failed')
       or run.finished_at is null
  ) then
    raise exception 'ETL staging cleanup aborted: an active run still owns staged rows.';
  end if;
end;
$$;

truncate table
  public.etl_stg_sales_daily_snapshots,
  public.etl_stg_financial_snapshots,
  public.etl_stg_return_order_items,
  public.etl_stg_customer_seller_bases,
  public.etl_stg_customers,
  public.etl_stg_sales_order_items,
  public.etl_stg_customer_opportunities;

commit;
