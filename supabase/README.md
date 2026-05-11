# Supabase Setup

1. Abra o SQL Editor do projeto `ewkexlyywmvufbirmpot`.
2. Execute as migrations da pasta `migrations/` em ordem.
3. Crie a primeira conta administrativa em `Authentication > Users` com:
   - email: `admin@app.omegadistribuidora.com.br`
   - senha inicial: `Omega@123`
   - email confirm: habilitado
4. Depois rode este SQL para promover o primeiro admin:

```sql
update public.app_users
set profile_id = (select id from public.app_profiles where slug = 'admin')
where code = 'admin';
```

5. Em `Edge Functions`, publique a função `functions/admin-users/index.ts`.
6. A função usa os secrets padrão do ambiente hospedado do Supabase:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
   - `SUPABASE_SERVICE_ROLE_KEY`

Sem a migration o app não sobe. Sem a função `admin-users` o login, módulos e relatórios funcionam, mas o cadastro/remoção/troca de senha de outros usuários administrativos não.
