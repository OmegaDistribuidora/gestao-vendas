alter function public.apply_customer_base_sync(uuid)
  set statement_timeout = '300s';

alter function public.apply_sales_order_items_sync(uuid)
  set statement_timeout = '300s';
