import { createClient } from 'npm:@supabase/supabase-js@2'

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
const supabaseServiceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const technicalDomain = 'app.omegadistribuidora.com.br'

const sellerOrigin = 'oracle_sellers'
const supervisorOrigin = 'oracle_supervisors'
const coordinatorOrigin = 'oracle_coordinators'

type SellerPayload = {
  code: string
  displayName: string
  cpf: string
  supervisorCode?: string
  supervisorName?: string
  coordinatorCode?: string
  coordinatorName?: string
}

type NamedRolePayload = {
  code: string
  displayName: string
}

function technicalEmailFromCode(code: string) {
  return `${code.trim().toLowerCase()}@${technicalDomain}`
}

function technicalEmailFromLogin(login: string) {
  return `${login.trim().toLowerCase()}@${technicalDomain}`
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

function placeholderPassword() {
  return `Tmp-${crypto.randomUUID()}-A1!`
}

function normalizeText(value: string) {
  return value.trim()
}

function normalizeCompare(value: string) {
  return normalizeText(value).toLowerCase()
}

function extractFirstLoginToken(displayName: string) {
  const beforeSlash = normalizeText(displayName).split('/')[0] ?? ''
  return normalizeText(beforeSlash).split(/\s+/)[0] ?? ''
}

function isAutoManagedProfileSlug(profileSlug: string) {
  return (
    profileSlug === 'vendedor' ||
    profileSlug === 'supervisor' ||
    profileSlug === 'coordenador'
  )
}

function isCodeBasedProfileSlug(profileSlug: string) {
  return (
    profileSlug === 'vendedor' ||
    profileSlug === 'supervisor' ||
    profileSlug === 'coordenador'
  )
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

async function requireProfileIdBySlug(
  adminClient: ReturnType<typeof createClient>,
  slug: string,
) {
  const { data: profile, error } = await adminClient
    .from('app_profiles')
    .select('id')
    .eq('slug', slug)
    .single()

  if (error || !profile) {
    throw new Error(`Perfil ${slug} não encontrado.`)
  }

  return String(profile.id)
}

async function ensureLoginAliasAvailable(
  adminClient: ReturnType<typeof createClient>,
  {
    loginAlias,
    currentUserId,
  }: {
    loginAlias: string
    currentUserId?: string
  },
) {
  const normalizedAlias = normalizeCompare(loginAlias)
  if (!normalizedAlias) {
    return
  }

  const { data: users, error } = await adminClient
    .from('app_users')
    .select(
      'auth_user_id, code, display_name, login_alias, profile:app_profiles!app_users_profile_id_fkey(slug)',
    )

  if (error) {
    throw new Error(error.message)
  }

  for (const row of users ?? []) {
    const user = row as Record<string, unknown>
    const userId = String(user.auth_user_id ?? '')
    if (currentUserId && userId === currentUserId) {
      continue
    }

    const code = String(user.code ?? '').trim()
    const displayName = String(user.display_name ?? '').trim()
    const existingAlias = String(user.login_alias ?? '').trim()
    const profileSlug = String(
      (user.profile as Record<string, unknown> | null)?.slug ?? '',
    ).trim()

    if (
      (profileSlug === 'vendedor' || profileSlug === 'admin') &&
      normalizeCompare(code) === normalizedAlias
    ) {
      throw new Error(
        `O login personalizado entra em conflito com o código de login do usuário ${code}.`,
      )
    }

    if (existingAlias && normalizeCompare(existingAlias) === normalizedAlias) {
      throw new Error(
        `O login personalizado entra em conflito com o login já configurado para ${code}${displayName ? ` - ${displayName}` : ''}.`,
      )
    }

    if (
      profileSlug !== 'vendedor' &&
      displayName &&
      normalizeCompare(displayName) === normalizedAlias
    ) {
      throw new Error(
        `O login personalizado entra em conflito com o nome de exibição de ${code} - ${displayName}.`,
      )
    }

    if (
      (profileSlug === 'supervisor' || profileSlug === 'coordenador') &&
      !existingAlias
    ) {
      const firstToken = extractFirstLoginToken(displayName)
      if (firstToken && normalizeCompare(firstToken) === normalizedAlias) {
        throw new Error(
          `O login personalizado entra em conflito com o primeiro nome usado no login de ${code} - ${displayName}.`,
        )
      }
    }
  }
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
  const loginAlias = String(payload.loginAlias ?? '').trim()
  const profileId = String(payload.profileId ?? '').trim()
  const isActive = Boolean(payload.isActive ?? true)

  if (!password || !profileId) {
    throw new Error('Código, senha e perfil são obrigatórios.')
  }

  const profileSlug = await requireProfileSlug(adminClient, profileId)
  if (isAutoManagedProfileSlug(profileSlug)) {
    throw new Error(
      'Usuários de vendedor, supervisor e coordenador devem ser sincronizados pelo script automático do Oracle.',
    )
  }
  if (!displayName) {
    throw new Error(
      'Nome de exibição é obrigatório para perfis que não sejam vendedor.',
    )
  }

  if (isCodeBasedProfileSlug(profileSlug) && !code) {
    throw new Error('Codigo obrigatorio para este perfil.')
  }

  const effectiveLoginAlias = profileSlug === 'admin' ? 'admin' : loginAlias
  if (!isCodeBasedProfileSlug(profileSlug) && !effectiveLoginAlias) {
    throw new Error('Login obrigatorio para este perfil.')
  }

  if (profileSlug !== 'vendedor' && effectiveLoginAlias) {
    await ensureLoginAliasAvailable(adminClient, {
      loginAlias: effectiveLoginAlias,
    })
  }

  const technicalEmail = isCodeBasedProfileSlug(profileSlug)
    ? technicalEmailFromCode(code)
    : technicalEmailFromLogin(effectiveLoginAlias)

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
      code: isCodeBasedProfileSlug(profileSlug)
        ? code
        : profileSlug === 'admin'
        ? 'admin'
        : null,
      technical_email: technicalEmail,
      display_name: displayName,
      login_alias:
        profileSlug === 'vendedor' ? null : effectiveLoginAlias || null,
      profile_id: profileId,
      is_active: isActive,
      origin: 'manual',
      requires_admin_password_definition: false,
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
  const loginAlias = String(payload.loginAlias ?? '').trim()
  const profileId = String(payload.profileId ?? '').trim()
  const isActive = Boolean(payload.isActive ?? true)
  const newPassword = String(payload.newPassword ?? '').trim()

  if (!userId || !profileId) {
    throw new Error('Usuário, código e perfil são obrigatórios.')
  }

  const profileSlug = await requireProfileSlug(adminClient, profileId)
  if (profileSlug !== 'vendedor' && !displayName) {
    throw new Error(
      'Nome de exibição é obrigatório para perfis que não sejam vendedor.',
    )
  }

  if (isCodeBasedProfileSlug(profileSlug) && !code) {
    throw new Error('Codigo obrigatorio para este perfil.')
  }

  const effectiveLoginAlias = profileSlug === 'admin' ? 'admin' : loginAlias
  if (!isCodeBasedProfileSlug(profileSlug) && !effectiveLoginAlias) {
    throw new Error('Login obrigatorio para este perfil.')
  }

  if (profileSlug !== 'vendedor' && effectiveLoginAlias) {
    await ensureLoginAliasAvailable(adminClient, {
      loginAlias: effectiveLoginAlias,
      currentUserId: userId,
    })
  }

  const technicalEmail = isCodeBasedProfileSlug(profileSlug)
    ? technicalEmailFromCode(code)
    : technicalEmailFromLogin(effectiveLoginAlias)
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

  const updatePayload: Record<string, unknown> = {
    code: isCodeBasedProfileSlug(profileSlug)
      ? code
      : profileSlug === 'admin'
      ? 'admin'
      : null,
    technical_email: technicalEmail,
    display_name: displayName,
    login_alias:
      profileSlug === 'vendedor' ? null : effectiveLoginAlias || null,
    profile_id: profileId,
    is_active: isActive,
  }

  if (newPassword) {
    updatePayload.requires_admin_password_definition = false
  }

  const { data: updatedUser, error: updateError } = await adminClient
    .from('app_users')
    .update(updatePayload)
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

async function syncSellerUsers(
  adminClient: ReturnType<typeof createClient>,
  sellers: SellerPayload[],
) {
  const sellerProfileId = await requireProfileIdBySlug(adminClient, 'vendedor')
  const codes = [...new Set(sellers.map((item) => item.code))]
  const activeCodeSet = new Set(codes)
  const existingUsersByCode = new Map<string, Record<string, unknown>>()

  if (codes.length > 0) {
    const { data: existingUsers, error } = await adminClient
      .from('app_users')
      .select(
        'auth_user_id, code, display_name, profile_id, origin, requires_admin_password_definition',
      )
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
  let nameResets = 0

  for (const seller of sellers) {
    const technicalEmail = technicalEmailFromCode(seller.code)
    const existing = existingUsersByCode.get(seller.code)

    if (existing) {
      const userId = String(existing.auth_user_id)
      const currentDisplayName = String(existing.display_name ?? '')
      const nameChanged =
        currentDisplayName.trim() !== '' &&
        normalizeCompare(currentDisplayName) !==
          normalizeCompare(seller.displayName)

      const authPayload: Record<string, unknown> = {
        email: technicalEmail,
        user_metadata: { display_name: seller.displayName },
      }
      if (nameChanged) {
        authPayload.password = sellerInitialPassword(seller.cpf)
      }

      const { error: authError } = await adminClient.auth.admin.updateUserById(
        userId,
        authPayload,
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
          requires_admin_password_definition: false,
        })
        .eq('auth_user_id', userId)

      if (updateError) {
        throw new Error(updateError.message)
      }

      updated += 1
      if (nameChanged) {
        nameResets += 1
      }
      continue
    }

    const initialPassword = sellerInitialPassword(seller.cpf)
    const { data, error: createError } = await adminClient.auth.admin.createUser(
      {
        email: technicalEmail,
        password: initialPassword,
        email_confirm: true,
        user_metadata: { display_name: seller.displayName },
      },
    )

    if (createError || !data.user) {
      if (
        createError?.message?.toLowerCase().includes('already been registered')
      ) {
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
        requires_admin_password_definition: false,
      })
      .eq('auth_user_id', data.user.id)

    if (updateError) {
      throw new Error(updateError.message)
    }

    created += 1
  }

  let deactivated = 0
  const { data: syncedUsers, error } = await adminClient
    .from('app_users')
    .select('auth_user_id, code')
    .eq('profile_id', sellerProfileId)
    .eq('origin', sellerOrigin)

  if (error) {
    throw new Error(error.message)
  }

  for (const row of syncedUsers ?? []) {
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

  return { created, updated, skipped, deactivated, nameResets }
}

async function syncNamedRoleUsers({
  adminClient,
  rawUsers,
  profileSlug,
  origin,
}: {
  adminClient: ReturnType<typeof createClient>
  rawUsers: NamedRolePayload[]
  profileSlug: 'supervisor' | 'coordenador'
  origin: string
}) {
  const profileId = await requireProfileIdBySlug(adminClient, profileSlug)
  const dedupedByCode = new Map<string, NamedRolePayload>()

  for (const rawUser of rawUsers) {
    const code = normalizeText(rawUser.code)
    const displayName = normalizeText(rawUser.displayName)
    if (!code || !displayName) {
      continue
    }
    dedupedByCode.set(code, { code, displayName })
  }

  const users = [...dedupedByCode.values()]
  const codes = users.map((item) => item.code)
  const activeCodeSet = new Set(codes)
  const existingUsersByCode = new Map<string, Record<string, unknown>>()

  if (codes.length > 0) {
    const { data: existingUsers, error } = await adminClient
      .from('app_users')
      .select(
        'auth_user_id, code, display_name, requires_admin_password_definition',
      )
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
  let nameResets = 0
  let skipped = 0

  for (const user of users) {
    const technicalEmail = technicalEmailFromCode(user.code)
    const existing = existingUsersByCode.get(user.code)

    if (existing) {
      const userId = String(existing.auth_user_id)
      const currentDisplayName = String(existing.display_name ?? '')
      const nameChanged =
        currentDisplayName.trim() !== '' &&
        normalizeCompare(currentDisplayName) !== normalizeCompare(user.displayName)

      const { error: authError } = await adminClient.auth.admin.updateUserById(
        userId,
        {
          email: technicalEmail,
          user_metadata: { display_name: user.displayName },
        },
      )

      if (authError) {
        throw new Error(authError.message)
      }

      const { error: updateError } = await adminClient
        .from('app_users')
        .update({
          code: user.code,
          technical_email: technicalEmail,
          display_name: user.displayName,
          profile_id: profileId,
          is_active: true,
          origin,
          requires_admin_password_definition: nameChanged
            ? true
            : Boolean(existing.requires_admin_password_definition ?? false),
        })
        .eq('auth_user_id', userId)

      if (updateError) {
        throw new Error(updateError.message)
      }

      updated += 1
      if (nameChanged) {
        nameResets += 1
      }
      continue
    }

    const { data, error: createError } = await adminClient.auth.admin.createUser(
      {
        email: technicalEmail,
        password: placeholderPassword(),
        email_confirm: true,
        user_metadata: { display_name: user.displayName },
      },
    )

    if (createError || !data.user) {
      if (
        createError?.message?.toLowerCase().includes('already been registered')
      ) {
        skipped += 1
        continue
      }
      throw new Error(
        createError?.message ??
          `Falha ao criar usuário de ${profileSlug}.`,
      )
    }

    const { error: updateError } = await adminClient
      .from('app_users')
      .update({
        code: user.code,
        technical_email: technicalEmail,
        display_name: user.displayName,
        profile_id: profileId,
        is_active: true,
        origin,
        requires_admin_password_definition: true,
      })
      .eq('auth_user_id', data.user.id)

    if (updateError) {
      throw new Error(updateError.message)
    }

    created += 1
  }

  let deactivated = 0
  const { data: syncedUsers, error } = await adminClient
    .from('app_users')
    .select('auth_user_id, code')
    .eq('profile_id', profileId)
    .eq('origin', origin)

  if (error) {
    throw new Error(error.message)
  }

  for (const row of syncedUsers ?? []) {
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

  return { created, updated, skipped, deactivated, nameResets }
}

async function syncSellers(payload: Record<string, unknown>) {
  const adminClient = createClient(supabaseUrl, supabaseServiceRoleKey)
  const rawSellers = Array.isArray(payload.sellers) ? payload.sellers : []

  const sellers = rawSellers
    .filter(
      (item): item is Record<string, unknown> =>
        item !== null && typeof item === 'object',
    )
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

  const rawSupervisors = Array.isArray(payload.supervisors)
    ? payload.supervisors
    : sellers.map((item) => ({
        code: item.supervisorCode,
        displayName: item.supervisorName,
      }))

  const rawCoordinators = Array.isArray(payload.coordinators)
    ? payload.coordinators
    : sellers.map((item) => ({
        code: item.coordinatorCode,
        displayName: item.coordinatorName,
      }))

  const supervisors = rawSupervisors
    .filter(
      (item): item is Record<string, unknown> =>
        item !== null && typeof item === 'object',
    )
    .map((item) => ({
      code: String(item.code ?? '').trim(),
      displayName: String(item.displayName ?? '').trim(),
    }))

  const coordinators = rawCoordinators
    .filter(
      (item): item is Record<string, unknown> =>
        item !== null && typeof item === 'object',
    )
    .map((item) => ({
      code: String(item.code ?? '').trim(),
      displayName: String(item.displayName ?? '').trim(),
    }))

  const sellerStats = await syncSellerUsers(adminClient, sellers)
  const supervisorStats = await syncNamedRoleUsers({
    adminClient,
    rawUsers: supervisors,
    profileSlug: 'supervisor',
    origin: supervisorOrigin,
  })
  const coordinatorStats = await syncNamedRoleUsers({
    adminClient,
    rawUsers: coordinators,
    profileSlug: 'coordenador',
    origin: coordinatorOrigin,
  })

  return {
    success: true,
    received: rawSellers.length,
    processed: sellers.length,
    sellers: sellerStats,
    supervisors: supervisorStats,
    coordinators: coordinatorStats,
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
