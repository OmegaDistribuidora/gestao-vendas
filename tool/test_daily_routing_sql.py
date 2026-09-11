"""Integration tests against ONLY the disposable local preview PostgreSQL.
All fixtures are rolled back, never modify the source or production Supabase.
"""
import unittest
import uuid

from psycopg.types.json import Jsonb
from daily_routing_preview import local_connection


class DailyRoutingSQLTest(unittest.TestCase):
    def setUp(self):
        self.c = local_connection()
        self.addCleanup(self.c.close)
        self.addCleanup(self.c.rollback)
        self.users = {}
        for profile, code in [('vendedor','1'),('vendedor','2'),('supervisor','20'),
                              ('supervisor','33'),('supervisor','35'),('coordenador','10'),
                              ('gerencia',''),('diretoria',''),('outros','')]:
            pid, uid = str(uuid.uuid4()),str(uuid.uuid4())
            self.c.execute(
                'insert into app_profiles(id,slug,name) values(%s,%s,%s)',
                (pid,profile,profile)
            )
            self.c.execute(
                'insert into app_users(auth_user_id,profile_id,code,is_active,display_name) '
                'values(%s,%s,%s,true,%s)',(uid,pid,code,profile)
            )
            self.users[profile+code] = uid
        self.snapshot = {'reference_date':'2001-01-01','source_updated_at':'2001-01-01T10:00:00Z',
                         'snapshot_id':'unit-test','sellers':[
            {'seller_code':'1','seller_name':'A','supervisor_code':'20','coordinator_code':'10','eligible':True},
            {'seller_code':'2','seller_name':'Redes','supervisor_code':'33','coordinator_code':'12','eligible':False},
            {'seller_code':'3','seller_name':'B','supervisor_code':'6','coordinator_code':'7','eligible':True},
            {'seller_code':'4','seller_name':'C','supervisor_code':'23','coordinator_code':'10','eligible':True},
        ],'items':[
            {'seller_code':'1','customer_code':'100','customer_name':'A','purchased':True},
            {'seller_code':'1','customer_code':'101','customer_name':'B','purchased':False},
            {'seller_code':'3','customer_code':'100','customer_name':'A','purchased':True},
            {'seller_code':'4','customer_code':'100','customer_name':'A','purchased':False},
        ]}
        self.c.execute('select app_apply_daily_routing_snapshot(%s)',(Jsonb(self.snapshot),))

    def read(self, key, **kw):
        self.c.execute("select set_config('request.jwt.claim.sub',%s,true)",(self.users[key],))
        return self.c.execute('select get_home_daily_routing(%s,null,null,true,%s,%s,%s,%s)',
            ('2001-01-01',kw.get('filter','all'),kw.get('offset',0),kw.get('size',100),kw.get('snapshot'))).fetchone()[0]

    def read_analysis(self, key):
        self.c.execute("select set_config('request.jwt.claim.sub',%s,true)",(self.users[key],))
        return self.c.execute(
            "select get_routing_analysis(date '2001-01-01',null,null)"
        ).fetchone()[0]

    def test_scopes_and_weighted_totals(self):
        self.assertEqual(self.read('vendedor1')['percent'],50)
        self.assertEqual(self.read('supervisor20')['planned'],2)
        self.assertEqual(self.read('coordenador10')['planned'],3)
        self.assertEqual(self.read('coordenador10')['percent'],33.33)
        self.assertEqual(self.read('gerencia')['planned'],3)
        for key in ['diretoria','outros']:
            self.assertEqual(self.read(key)['planned'],4)
            self.assertEqual(self.read(key)['percent'],50)

    def test_network_hidden(self):
        for key in ['vendedor2','supervisor33','supervisor35']:
            result = self.read(key)
            self.assertFalse(result['applicable'])
            self.assertEqual(result['items'],[])

    def test_details_filter_pagination(self):
        result = self.read('diretoria',filter='pending',size=1)
        self.assertEqual((result['planned'],result['purchased'],result['filtered_count']),(4,2,2))
        self.assertEqual(len(result['items']),1)
        page2 = self.read('diretoria',filter='pending',size=1,offset=1,snapshot='unit-test')
        self.assertNotEqual(result['items'],page2['items'])

    def test_snapshot_changed_rejected(self):
        with self.assertRaisesRegex(Exception,'ROUTING_SNAPSHOT_CHANGED'):
            self.read('diretoria',snapshot='old')

    def test_duplicates_rejected(self):
        self.snapshot['items'].append(self.snapshot['items'][0])
        with self.assertRaisesRegex(Exception,'duplicados'):
            self.c.execute('select app_apply_daily_routing_snapshot(%s)',(Jsonb(self.snapshot),))

    def test_unauthenticated_denied(self):
        self.c.execute("select set_config('request.jwt.claim.sub','',true)")
        with self.assertRaisesRegex(Exception,'Usuario nao encontrado'):
            self.c.execute("select get_home_daily_routing('2001-01-01')")

    def test_no_route(self):
        self.c.execute('update app_users set code=%s where auth_user_id=%s',('999',self.users['supervisor20']))
        result = self.read('supervisor20')
        self.assertTrue(result['applicable'])
        self.assertEqual(result['planned'],0)
        self.assertIsNone(result['percent'])

    def test_analysis_exposes_details_only_for_a_seller(self):
        seller = self.read_analysis('vendedor1')
        self.assertEqual((seller['planned'],seller['purchased']),(2,1))
        self.assertEqual(len(seller['items']),2)
        self.assertTrue(seller['map_available'])

        supervisor = self.read_analysis('supervisor20')
        self.assertEqual(supervisor['planned'],2)
        self.assertEqual(len(supervisor['seller_summaries']),1)
        self.assertEqual(supervisor['items'],[])
        self.assertFalse(supervisor['map_available'])

    def test_analysis_preserves_management_and_broad_scopes(self):
        self.assertEqual(self.read_analysis('gerencia')['planned'],3)
        self.assertEqual(self.read_analysis('diretoria')['planned'],4)
        self.assertEqual(self.read_analysis('outros')['planned'],4)


if __name__ == '__main__':
    unittest.main()
