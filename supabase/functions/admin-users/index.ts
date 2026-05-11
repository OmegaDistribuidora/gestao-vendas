import { createClient } from 'npm:@supabase/supabase-js@2'

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
const supabaseServiceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const technicalDomain = 'app.omegadistribuidora.com.br'
const sellerOrigin = 'oracle_sellers'

type SellerPayload = {
  code: string
  displayName: string
  cpf: string
  supervisorCode?: string
  supervisorName?: string
  coordinatorCode?: string
  coordinatorName?: string
}

function technicalEmailFromCode(code: string) {
  return `${code.trim().toLowerCase()}@${technicalDomain}`
}

function sanitizeDigits(value: string) {
  return value.replace(/\D/g, '')
}

function sellerInitialPassword(cpf: string) {
  const digits = sanitizeDigits(cpf)
  if (digits.length < 3) {
    throw new Error('CPF inválido para geração da senha inicial do vendedor.')
  }
  return digits.slice(0, 3)
}

async function requireProfileSlug(
  adminClient: ReturnType<typeof createClient>,
  profileId: string,
) {
  const { data: profile, error } = await adminClient
    .from('app_profiles')
    .select('slug')
    .eq('id', profileId)
    .single()

  if (error || !profile) {
    throw new Error('Perfil inválido.')
  }

  return String(profile.slug ?? '').trim().toLowerCase()
}

async function requireSellerProfileId(
  adminClient: ReturnType<typeof createClient>,
) {
  const { data: profile, error } = await adminClient
    .from('app_profiles')
    .select('id')
    .eq('slug', 'vendedor')
    .single()

  if (error || !profile) {
    throw new Error('Perfil vendedor não encontrado.')
  }

  return String(profile.id)
}

function json(body: unknown, init?: ResponseInit) {
  return new Response(JSON.stringify(body), {
    headers: { 'Content-Type': 'application/json' },
    ...init,
  })
}

async function requireAdmin(req: Request) {
  const authorization = req.headers.get('Authorization') ?? ''

  if (!authorization) {
    throw new Error('Authorization ausente.')
  }

  const userClient = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authorization } },
  })

  const {
    data: { user },
    error: authError,
  } = await userClient.auth.getUser()

  if (authError || !user) {
    throw new Error('Sessão inválida.')
  }

  const { data: profile, error: profileError } = await userClient
    .from('app_users')
    .select('is_active, profile:app_profiles!app_users_profile_id_fkey(slug)')
    .eq('auth_user_id', user.id)
    .single()

  if (profileError || !profile) {
    throw new Error('Usuário administrativo não encontrado.')
  }

  const slug = profile.profile?.slug
  if (profile.is_active !== true || slug !== 'admin') {
    throw new Error('Acesso negado.')
  }
}

async function createUser(payload: Record<string, unknown>) {
  const adminClient = createClient(supabaseUrl, supabaseServiceRoleKey)
  const code = String(payload.code ?? '').trim()
  const password = String(payload.password ?? '').trim()
  const displayName = String(payload.displayName ?? '').trim()
  const profileId = String(payload.profileId ?? '').trim()
  const isActive = Boolean(payload.isActive ?? true)

  if (!code || !password || !profileId) {
    throw new Error('Código, senha e perfil são obrigatórios.')
  }

  const profileSlug = await requireProfileSlug(adminClient, profileId)
  if (profileSlug === 'vendedor') {
    throw new Error(
      'Vendedores devem ser sincronizados pelo script automático do Oracle.',
    )
  }
  if (!displayName) {
    throw new Error(
      'Nome de exibição é obrigatório para perfis que não sejam vendedor.',
    )
  }

  const technicalEmail = technicalEmailFromCode(code)

  const { data, error } = await adminClient.auth.admin.createUser({
    email: technicalEmail,
    password,
    email_confirm: true,
    user_metadata: { display_name: displayName },
  })

  if (error || !data.user) {
    throw new Error(error?.message ?? 'Falha ao criar usuário.')
  }

  const { data: updatedUser, error: updateError } = await adminClient
    .from('app_users')
    .update({
      code,
      technical_email: technicalEmail,
      display_name: displayName,
      profile_id: profileId,
      is_active: isActive,
      origin: 'manual',
    })
    .eq('auth_user_id', data.user.id)
    .select()
    .single()

  if (updateError) {
    throw new Error(updateError.message)
  }

  return { success: true, userId: data.user.id, user: updatedUser }
}

async function updateUser(payload: Record<string, unknown>) {
  const adminClient = createClient(supabaseUrl, supabaseServiceRoleKey)
  const userId = String(payload.userId ?? '').trim()
  const code = String(payload.code ?? '').trim()
  const displayName = String(payload.displayName ?? '').trim()
  const profileId = String(payload.profileId ?? '').trim()
  const isActive = Boolean(payload.isActive ?? true)
  const newPassword = String(payload.newPassword ?? '').trim()

  if (!userId || !code || !profileId) {
    throw new Error('Usuário, código e perfil são obrigatórios.')
  }

  const profileSlug = await requireProfileSlug(adminClient, profileId)
  if (profileSlug !== 'vendedor' && !displayName) {
    throw new Error(
      'Nome de exibição é obrigatório para perfis que não sejam vendedor.',
    )
  }

  const technicalEmail = technicalEmailFromCode(code)
  const updateAuthPayload: Record<string, unknown> = {
    email: technicalEmail,
    user_metadata: { display_name: displayName },
  }

  if (newPassword) {
    updateAuthPayload.password = newPassword
  }

  const { error: authError } = await adminClient.auth.admin.updateUserById(
    userId,
    updateAuthPayload,
  )

  if (authError) {
    throw new Error(authError.message)
  }

  const { data: updatedUser, error: updateError } = await adminClient
    .from('app_users')
    .update({
      code,
      technical_email: technicalEmail,
      display_name: displayName,
      profile_id: profileId,
      is_active: isActive,
    })
    .eq('auth_user_id', userId)
    .select()
    .single()

  if (updateError) {
    throw new Error(updateError.message)
  }

  return { success: true, user: updatedUser }
}

async function deleteUser(payload: Record<string, unknown>) {
  const adminClient = createClient(supabaseUrl, supabaseServiceRoleKey)
  const userId = String(payload.userId ?? '').trim()

  if (!userId) {
    throw new Error('Usuário inválido.')
  }

  const { error } = await adminClient.auth.admin.deleteUser(userId)
  if (error) {
    throw new Error(error.message)
  }

  return { success: true }
}

async function syncSellers(payload: Record<string, unknown>) {
  const adminClient = createClient(supabaseUrl, supabaseServiceRoleKey)
  const rawSellers = Array.isArray(payload.sellers) ? payload.sellers : []
  const deactivateMissing = Boolean(payload.deactivateMissing ?? true)
  const sellerProfileId = await requireSellerProfileId(adminClient)

  const sellers = rawSellers
    .filter((item): item is Record<string, unknown> => item !== null && typeof item === 'object')
    .map((item) => ({
      code: String(item.code ?? '').trim(),
      displayName: String(item.displayName ?? '').trim(),
      cpf: sanitizeDigits(String(item.cpf ?? '')),
      supervisorCode: String(item.supervisorCode ?? '').trim(),
      supervisorName: String(item.supervisorName ?? '').trim(),
      coordinatorCode: String(item.coordinatorCode ?? '').trim(),
      coordinatorName: String(item.coordinatorName ?? '').trim(),
    }))
    .filter((item) => item.code && item.displayName && item.cpf.length >= 3)

  const codes = [...new Set(sellers.map((item) => item.code))]
  const activeCodeSet = new Set(codes)
  const existingUsersByCode = new Map<string, Record<string, unknown>>()

  if (codes.length > 0) {
    const { data: existingUsers, error } = await adminClient
      .from('app_users')
      .select('auth_user_id, code, profile_id, origin')
      .in('code', codes)

    if (error) {
      throw new Error(error.message)
    }

    for (const row of existingUsers ?? []) {
      existingUsersByCode.set(String(row.code), row as Record<string, unknown>)
    }
  }

  let created = 0
  let updated = 0
  let skipped = 0

  for (const seller of sellers) {
    const technicalEmail = technicalEmailFromCode(seller.code)
    const existing = existingUsersByCode.get(seller.code)

    if (existing) {
      const userId = String(existing.auth_user_id)
      const { error: authError } = await adminClient.auth.admin.updateUserById(
        userId,
        {
          email: technicalEmail,
          user_metadata: { display_name: seller.displayName },
        },
      )

      if (authError) {
        throw new Error(authError.message)
      }

      const { error: updateError } = await adminClient
        .from('app_users')
        .update({
          code: seller.code,
          technical_email: technicalEmail,
          display_name: seller.displayName,
          profile_id: sellerProfileId,
          is_active: true,
          cpf: seller.cpf,
          supervisor_code: seller.supervisorCode || null,
          supervisor_name: seller.supervisorName || null,
          coordinator_code: seller.coordinatorCode || null,
          coordinator_name: seller.coordinatorName || null,
          origin: sellerOrigin,
        })
        .eq('auth_user_id', userId)

      if (updateError) {
        throw new Error(updateError.message)
      }

      updated += 1
      continue
    }

    const initialPassword = sellerInitialPassword(seller.cpf)
    const { data, error: createError } = await adminClient.auth.admin.createUser({
      email: technicalEmail,
      password: initialPassword,
      email_confirm: true,
      user_metadata: { display_name: seller.displayName },
    })

    if (createError || !data.user) {
      if (createError?.message?.toLowerCase().includes('already been registered')) {
        skipped += 1
        continue
      }
      throw new Error(createError?.message ?? 'Falha ao criar vendedor.')
    }

    const { error: updateError } = await adminClient
      .from('app_users')
      .update({
        code: seller.code,
        technical_email: technicalEmail,
        display_name: seller.displayName,
        profile_id: sellerProfileId,
        is_active: true,
        cpf: seller.cpf,
        supervisor_code: seller.supervisorCode || null,
        supervisor_name: seller.supervisorName || null,
        coordinator_code: seller.coordinatorCode || null,
        coordinator_name: seller.coordinatorName || null,
        origin: sellerOrigin,
      })
      .eq('auth_user_id', data.user.id)

    if (updateError) {
      throw new Error(updateError.message)
    }

    created += 1
  }

  let deactivated = 0
  if (deactivateMissing) {
    const { data: syncedSellers, error } = await adminClient
      .from('app_users')
      .select('auth_user_id, code')
      .eq('profile_id', sellerProfileId)
      .eq('origin', sellerOrigin)

    if (error) {
      throw new Error(error.message)
    }

    for (const row of syncedSellers ?? []) {
      const code = String(row.code ?? '').trim()
      if (!code || activeCodeSet.has(code)) {
        continue
      }

      const { error: updateError } = await adminClient
        .from('app_users')
        .update({ is_active: false })
        .eq('auth_user_id', String(row.auth_user_id))

      if (updateError) {
        throw new Error(updateError.message)
      }

      deactivated += 1
    }
  }

  return {
    success: true,
    received: rawSellers.length,
    processed: sellers.length,
    created,
    updated,
    skipped,
    deactivated,
  }
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed.' }, { status: 405 })
  }

  try {
    await requireAdmin(req)
    const payload = (await req.json()) as Record<string, unknown>
    const action = String(payload.action ?? '').trim()

    if (action === 'create') {
      return json(await createUser(payload))
    }
    if (action === 'update') {
      return json(await updateUser(payload))
    }
    if (action === 'delete') {
      return json(await deleteUser(payload))
    }
    if (action === 'sync_sellers') {
      return json(await syncSellers(payload))
    }

    return json({ error: 'Ação inválida.' }, { status: 400 })
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Erro interno.'
    return json({ error: message }, { status: 400 })
  }
})
