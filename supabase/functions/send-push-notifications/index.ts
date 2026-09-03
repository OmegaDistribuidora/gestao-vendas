import { createClient } from 'npm:@supabase/supabase-js@2'

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
const supabaseServiceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const pushSenderSecret = Deno.env.get('PUSH_SENDER_SECRET') ?? ''
const firebaseServiceAccountJson =
  Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON') ?? ''
const firebaseProjectId = Deno.env.get('FIREBASE_PROJECT_ID') ?? ''
const firebaseClientEmail = Deno.env.get('FIREBASE_CLIENT_EMAIL') ?? ''
const firebasePrivateKey = Deno.env.get('FIREBASE_PRIVATE_KEY') ?? ''

type PushEvent = {
  id: string
  recipient_user_id: string
  title: string
  body: string
  data: Record<string, unknown>
  attempts: number
}

type PushToken = {
  id: string
  fcm_token: string
  token_hash: string
}

function json(body: unknown, init?: ResponseInit) {
  return new Response(JSON.stringify(body), {
    headers: { 'Content-Type': 'application/json' },
    ...init,
  })
}

function base64Url(input: string | ArrayBuffer) {
  const bytes =
    typeof input === 'string'
      ? new TextEncoder().encode(input)
      : new Uint8Array(input)
  let binary = ''
  for (const byte of bytes) {
    binary += String.fromCharCode(byte)
  }
  return btoa(binary)
    .replaceAll('+', '-')
    .replaceAll('/', '_')
    .replaceAll('=', '')
}

function pemToArrayBuffer(pem: string) {
  const normalized = pem
    .replace(/\\n/g, '\n')
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s/g, '')
  const binary = atob(normalized)
  const bytes = new Uint8Array(binary.length)
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index)
  }
  return bytes.buffer
}

function firebaseCredentials() {
  if (firebaseServiceAccountJson.trim()) {
    const parsed = JSON.parse(firebaseServiceAccountJson) as Record<
      string,
      string
    >
    return {
      projectId: parsed.project_id,
      clientEmail: parsed.client_email,
      privateKey: parsed.private_key,
    }
  }

  return {
    projectId: firebaseProjectId,
    clientEmail: firebaseClientEmail,
    privateKey: firebasePrivateKey,
  }
}

async function getGoogleAccessToken() {
  const credentials = firebaseCredentials()
  if (
    !credentials.projectId?.trim() ||
    !credentials.clientEmail?.trim() ||
    !credentials.privateKey?.trim()
  ) {
    throw new Error(
      'Credenciais Firebase ausentes. Configure FIREBASE_SERVICE_ACCOUNT_JSON ou FIREBASE_PROJECT_ID/FIREBASE_CLIENT_EMAIL/FIREBASE_PRIVATE_KEY.',
    )
  }

  const now = Math.floor(Date.now() / 1000)
  const header = { alg: 'RS256', typ: 'JWT' }
  const claim = {
    iss: credentials.clientEmail,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }
  const unsignedJwt = `${base64Url(JSON.stringify(header))}.${base64Url(
    JSON.stringify(claim),
  )}`
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(credentials.privateKey),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(unsignedJwt),
  )
  const jwt = `${unsignedJwt}.${base64Url(signature)}`

  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  })

  const payload = (await response.json()) as Record<string, unknown>
  if (!response.ok) {
    throw new Error(
      `Falha ao autenticar no Google OAuth: ${JSON.stringify(payload)}`,
    )
  }

  return {
    accessToken: String(payload.access_token ?? ''),
    projectId: credentials.projectId,
  }
}

function stringData(data: Record<string, unknown>, eventId: string) {
  const result: Record<string, string> = {
    eventId,
    click_action: 'FLUTTER_NOTIFICATION_CLICK',
  }

  for (const [key, value] of Object.entries(data ?? {})) {
    if (value === null || value === undefined) {
      continue
    }
    result[key] =
      typeof value === 'string' ? value : JSON.stringify(value)
  }

  return result
}

function isInvalidTokenError(message: string) {
  const normalized = message.toLowerCase()
  return (
    normalized.includes('unregistered') ||
    normalized.includes('registration-token-not-registered') ||
    normalized.includes('invalid registration token') ||
    normalized.includes('invalid_argument')
  )
}

async function sendFirebaseMessage({
  accessToken,
  projectId,
  event,
  token,
}: {
  accessToken: string
  projectId: string
  event: PushEvent
  token: PushToken
}) {
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token: token.fcm_token,
          notification: {
            title: event.title,
            body: event.body,
          },
          data: stringData(event.data, event.id),
          android: {
            priority: 'high',
            notification: {
              icon: 'ic_stat_sales_notification',
              color: '#006BFF',
            },
          },
        },
      }),
    },
  )

  const payload = (await response.json()) as Record<string, unknown>
  if (!response.ok) {
    throw new Error(JSON.stringify(payload))
  }

  return String(payload.name ?? '')
}

async function processQueuedEvents(limit: number) {
  const supabase = createClient(supabaseUrl, supabaseServiceRoleKey)
  const { accessToken, projectId } = await getGoogleAccessToken()

  const { data: events, error: eventsError } = await supabase
    .from('app_push_notification_events')
    .select('id, recipient_user_id, title, body, data, attempts')
    .eq('status', 'queued')
    .order('created_at', { ascending: true })
    .limit(limit)

  if (eventsError) {
    throw new Error(eventsError.message)
  }

  let sent = 0
  let failed = 0
  let skipped = 0

  for (const rawEvent of events ?? []) {
    const event = rawEvent as PushEvent
    await supabase
      .from('app_push_notification_events')
      .update({
        status: 'sending',
        attempts: Number(event.attempts ?? 0) + 1,
        last_error: null,
      })
      .eq('id', event.id)
      .eq('status', 'queued')

    const { data: tokens, error: tokensError } = await supabase
      .from('app_push_tokens')
      .select('id, fcm_token, token_hash')
      .eq('user_id', event.recipient_user_id)
      .eq('enabled', true)
      .is('revoked_at', null)

    if (tokensError) {
      failed += 1
      await supabase
        .from('app_push_notification_events')
        .update({ status: 'failed', last_error: tokensError.message })
        .eq('id', event.id)
      continue
    }

    if (!tokens || tokens.length === 0) {
      skipped += 1
      await supabase
        .from('app_push_notification_events')
        .update({
          status: 'skipped',
          last_error: 'Nenhum token ativo para o destinatario.',
        })
        .eq('id', event.id)
      continue
    }

    let eventSent = 0
    const eventErrors: string[] = []

    for (const rawToken of tokens) {
      const token = rawToken as PushToken
      try {
        const messageId = await sendFirebaseMessage({
          accessToken,
          projectId,
          event,
          token,
        })
        eventSent += 1
        await supabase.from('app_push_notification_deliveries').insert({
          event_id: event.id,
          token_id: token.id,
          token_hash: token.token_hash,
          status: 'sent',
          firebase_message_id: messageId,
        })
      } catch (error) {
        const message =
          error instanceof Error ? error.message : 'Falha desconhecida.'
        eventErrors.push(message)
        await supabase.from('app_push_notification_deliveries').insert({
          event_id: event.id,
          token_id: token.id,
          token_hash: token.token_hash,
          status: 'failed',
          error_message: message,
        })

        if (isInvalidTokenError(message)) {
          await supabase
            .from('app_push_tokens')
            .update({
              enabled: false,
              revoked_at: new Date().toISOString(),
            })
            .eq('id', token.id)
        }
      }
    }

    if (eventSent > 0) {
      sent += 1
      await supabase
        .from('app_push_notification_events')
        .update({
          status: 'sent',
          sent_at: new Date().toISOString(),
          last_error: eventErrors[0] ?? null,
        })
        .eq('id', event.id)
    } else {
      failed += 1
      await supabase
        .from('app_push_notification_events')
        .update({
          status: 'failed',
          last_error: eventErrors.join('\n').slice(0, 4000),
        })
        .eq('id', event.id)
    }
  }

  return {
    processed: events?.length ?? 0,
    sent,
    failed,
    skipped,
  }
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed.' }, { status: 405 })
  }

  try {
    if (!pushSenderSecret) {
      throw new Error('PUSH_SENDER_SECRET nao configurado.')
    }

    const authorization = req.headers.get('Authorization') ?? ''
    if (authorization !== `Bearer ${pushSenderSecret}`) {
      return json({ error: 'Acesso negado.' }, { status: 401 })
    }

    const payload = (await req.json().catch(() => ({}))) as Record<
      string,
      unknown
    >
    if (payload.evaluate === true) {
      const supabase = createClient(supabaseUrl, supabaseServiceRoleKey)
      const { error } = await supabase.rpc('evaluate_push_notifications', {
        target_reference_date: payload.referenceDate ?? null,
        target_changed_since: payload.changedSince ?? null,
        force_initial_notifications:
          payload.forceInitialNotifications === true,
      })

      if (error) {
        throw new Error(error.message)
      }
    }

    if (payload.evaluateReturnsAllProfiles === true) {
      const supabase = createClient(supabaseUrl, supabaseServiceRoleKey)
      const { error } = await supabase.rpc(
        'evaluate_push_return_notifications_all_profiles',
        {
          target_reference_date: payload.referenceDate ?? null,
          target_changed_since: payload.changedSince ?? null,
        },
      )

      if (error) {
        throw new Error(error.message)
      }
    }

    const limit = Math.max(1, Math.min(Number(payload.limit ?? 50), 200))
    return json(await processQueuedEvents(limit))
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Erro interno.'
    return json({ error: message }, { status: 400 })
  }
})
