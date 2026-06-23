from __future__ import annotations

import json
from datetime import date

from customer_opportunities_sync import fetch_registered_oracle_tax_ids
from oracle_financial_sync_common import require_env
from supabase_sync_common import (
    authenticate_supabase,
    begin_sync_run,
    invoke_rpc,
    mark_sync_run_failed,
)


def main() -> None:
    registered_tax_ids = sorted(fetch_registered_oracle_tax_ids())
    if not registered_tax_ids:
        raise RuntimeError("Oracle registered customer list is empty.")

    session = authenticate_supabase(require_env)
    today = date.today().isoformat()
    run_id = begin_sync_run(
        session,
        job_name="customer_opportunities_prune",
        target_name="app_customer_opportunities",
        scope_type="fast",
        window_start=today,
        window_end=today,
    )

    try:
        response = invoke_rpc(
            session,
            "prune_customer_opportunities",
            {
                "p_run_id": run_id,
                "p_registered_tax_ids": registered_tax_ids,
            },
            timeout=300,
        )
    except Exception as error:
        mark_sync_run_failed(session, run_id, str(error))
        raise

    result = response if isinstance(response, dict) else {}
    print(
        json.dumps(
            {
                "oracle_registered_tax_ids": len(registered_tax_ids),
                **result,
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
