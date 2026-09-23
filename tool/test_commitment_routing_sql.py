"""Transactional test for Commitment routing enrichment on local PostgreSQL."""
import unittest
from pathlib import Path

from psycopg.types.json import Jsonb

from daily_routing_preview import local_connection


ROOT = Path(__file__).resolve().parents[1]


class CommitmentRoutingSQLTest(unittest.TestCase):
    def setUp(self):
        self.c = local_connection()
        self.addCleanup(self.c.close)
        self.addCleanup(self.c.rollback)

        self.c.execute("""
          create or replace function public.get_commitment_overview_optimized(
            date default null,
            date default null,
            text default null,
            text default null
          ) returns jsonb language sql as $$
            select jsonb_build_object(
              'selected_start_date', date '2003-01-01',
              'selected_end_date', date '2003-01-02',
              'items', jsonb_build_array(
                jsonb_build_object(
                  'profile_slug','supervisor',
                  'owner_code','20',
                  'display_name','Supervisor 20'
                ),
                jsonb_build_object(
                  'profile_slug','supervisor',
                  'owner_code','33',
                  'display_name','Supervisor 33'
                )
              )
            )
          $$
        """)

        migration = (
            ROOT / 'supabase/migrations/'
            '20260923151000_commitment_routing_performance.sql'
        ).read_text(encoding='utf-8')
        self.c.execute(migration)

        snapshot = {
            'reference_date': '2003-01-01',
            'source_updated_at': '2003-01-01T10:00:00Z',
            'snapshot_id': 'commitment-routing-test',
            'sellers': [{
                'seller_code': '1',
                'seller_name': 'Seller',
                'supervisor_code': '20',
                'coordinator_code': '10',
                'eligible': True,
            }],
            'items': [{
                'seller_code': '1',
                'customer_code': '100',
                'customer_name': 'Customer',
                'purchased': True,
                'sale_amount': 125.50,
            }],
        }
        self.c.execute(
            'select app_apply_daily_routing_snapshot(%s)',
            (Jsonb(snapshot),),
        )

    def test_enriches_only_commitment_items_with_routing(self):
        result = self.c.execute(
            "select get_commitment_overview_optimized("
            "date '2003-01-01',date '2003-01-02',null,null)"
        ).fetchone()[0]
        by_code = {item['owner_code']: item for item in result['items']}

        self.assertEqual(by_code['20']['routing_planned'], 1)
        self.assertEqual(by_code['20']['routing_purchased'], 1)
        self.assertEqual(by_code['20']['routing_percent'], 100)
        self.assertNotIn('routing_planned', by_code['33'])


if __name__ == '__main__':
    unittest.main()
