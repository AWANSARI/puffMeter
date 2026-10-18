// Server-side Google OAuth session, modeled on Atomic Tracker's Auth.js setup:
//  - Authorization-code flow with the client secret (+ PKCE) and access_type=offline
//  - The refresh token lives in an AES-GCM encrypted, HttpOnly cookie — no database
//  - Access tokens never reach the browser; Drive calls go through our proxy function
//
// Environment (Netlify > Site configuration > Environment variables):
//   AUTH_GOOGLE_ID      Google OAuth "Web application" client ID
//   AUTH_GOOGLE_SECRET  its client secret
//   AUTH_SECRET         random string for cookie encryption (openssl rand -base64 32)

export const GOOGLE_SCOPES = [
  'openid',
  'email',
  'profile',
  'https://www.googleapis.com/auth/drive.file', // least privilege: only files PuffyMeter creates
].join(' ')
export const DRIVE_SCOPE = 'https://www.googleapis.com/auth/drive.file'

export const SESSION_COOKIE = 'pm_session'
export const STATE_COOKIE = 'pm_oauth'
const SESSION_MAX_AGE = 60 * 60 * 24 * 180 // 180 days
const STATE_MAX_AGE = 60 * 10

export interface Session {
  sub: string
  name?: string
  email?: string
  picture?: string
  accessToken: string
  refreshToken?: string
  /** Unix seconds. */
  expiresAt: number
  scope: string
}

export interface OAuthState { state: string; verifier: string; returnTo: string }

type Env = { clientId: string; clientSecret: string; secret: string }

export function env(): Env | undefined {
  const clientId = process.env.AUTH_GOOGLE_ID
  const clientSecret = process.env.AUTH_GOOGLE_SECRET
  const secret = process.env.AUTH_SECRET
  return clientId && clientSecret && secret ? { clientId, clientSecret, secret } : undefined
}

// MARK: Encoding helpers

const enc = new TextEncoder()
const dec = new TextDecoder()

export function b64url(bytes: Uint8Array): string {
  let s = ''
  for (const b of bytes) s += String.fromCharCode(b)
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

export function fromB64url(s: string): Uint8Array {
  const b = atob(s.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((s.length + 3) % 4))
  return Uint8Array.from(b, (c) => c.charCodeAt(0))
}

export function randomToken(bytes = 32): string {
  return b64url(crypto.getRandomValues(new Uint8Array(bytes)))
}

async function key(secret: string): Promise<CryptoKey> {
  const digest = await crypto.subtle.digest('SHA-256', enc.encode(`puffymeter:${secret}`))
  return crypto.subtle.importKey('raw', digest, 'AES-GCM', false, ['encrypt', 'decrypt'])
}

export async function seal(value: unknown, secret: string): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12))
  const data = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, await key(secret), enc.encode(JSON.stringify(value))))
  const out = new Uint8Array(iv.length + data.length)
  out.set(iv)
  out.set(data, iv.length)
  return b64url(out)
}

export async function unseal<T>(sealed: string, secret: string): Promise<T | undefined> {
  try {
    const bytes = fromB64url(sealed)
    const plain = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: bytes.slice(0, 12) }, await key(secret), bytes.slice(12))
    return JSON.parse(dec.decode(plain)) as T
  } catch {
    return undefined
  }
}

export async function pkceChallenge(verifier: string): Promise<string> {
  return b64url(new Uint8Array(await crypto.subtle.digest('SHA-256', enc.encode(verifier))))
}

// MARK: Cookies

export function readCookie(req: Request, name: string): string | undefined {
  const header = req.headers.get('cookie') ?? ''
  for (const part of header.split(';')) {
    const [k, ...v] = part.trim().split('=')
    if (k === name) return v.join('=')
  }
  return undefined
}

export function cookie(req: Request, name: string, value: string, maxAge: number): string {
  const secure = new URL(req.url).protocol === 'https:' ? '; Secure' : ''
  return `${name}=${value}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${maxAge}${secure}`
}

export const clearCookie = (req: Request, name: string) => cookie(req, name, '', 0)

export async function readSession(req: Request, secret: string): Promise<Session | undefined> {
  const raw = readCookie(req, SESSION_COOKIE)
  return raw ? unseal<Session>(raw, secret) : undefined
}

export async function sessionCookie(req: Request, s: Session, secret: string): Promise<string> {
  return cookie(req, SESSION_COOKIE, await seal(s, secret), SESSION_MAX_AGE)
}

export async function stateCookie(req: Request, s: OAuthState, secret: string): Promise<string> {
  return cookie(req, STATE_COOKIE, await seal(s, secret), STATE_MAX_AGE)
}

/** Only same-site relative paths, so the OAuth return can't be used as an open redirect. */
export function safeReturnTo(value: string | null | undefined): string {
  if (!value || !value.startsWith('/') || value.startsWith('//') || value.includes('\\')) return '/auth/complete'
  return value
}

export function redirectURI(req: Request): string {
  return `${new URL(req.url).origin}/api/auth/callback/google`
}

// MARK: Google token endpoint

export interface TokenResponse {
  access_token: string
  expires_in: number
  refresh_token?: string
  scope?: string
  id_token?: string
  error?: string
}

export async function exchangeCode(e: Env, code: string, verifier: string, redirect: string): Promise<TokenResponse> {
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: e.clientId, client_secret: e.clientSecret, code, code_verifier: verifier,
      grant_type: 'authorization_code', redirect_uri: redirect,
    }),
  })
  const json = (await res.json()) as TokenResponse
  if (!res.ok || !json.access_token) throw new Error(`token exchange failed: ${res.status} ${json.error ?? ''}`)
  return json
}

export async function refresh(e: Env, refreshToken: string): Promise<TokenResponse> {
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ client_id: e.clientId, client_secret: e.clientSecret, grant_type: 'refresh_token', refresh_token: refreshToken }),
  })
  const json = (await res.json()) as TokenResponse
  if (!res.ok || !json.access_token) throw new Error(`refresh failed: ${res.status} ${json.error ?? ''}`)
  return json
}

/** Returns a session with a valid access token (refreshing with a 60 s buffer), or undefined. */
export async function freshSession(e: Env, s: Session, force = false): Promise<{ session: Session; refreshed: boolean } | undefined> {
  if (!force && Date.now() / 1000 < s.expiresAt - 60) return { session: s, refreshed: false }
  if (!s.refreshToken) return undefined
  try {
    const t = await refresh(e, s.refreshToken)
    return {
      session: {
        ...s, accessToken: t.access_token, expiresAt: Math.floor(Date.now() / 1000) + t.expires_in,
        refreshToken: t.refresh_token ?? s.refreshToken, scope: t.scope ?? s.scope,
      },
      refreshed: true,
    }
  } catch {
    return undefined
  }
}

/** The id_token comes straight from Google's token endpoint over TLS, so its claims can be read directly. */
export function idTokenClaims(idToken?: string): { sub?: string; name?: string; email?: string; picture?: string } {
  if (!idToken) return {}
  try {
    return JSON.parse(dec.decode(fromB64url(idToken.split('.')[1] ?? ''))) as Record<string, string>
  } catch {
    return {}
  }
}

export function json(body: unknown, init: ResponseInit & { cookies?: string[] } = {}): Response {
  const headers = new Headers(init.headers)
  headers.set('Content-Type', 'application/json')
  headers.set('Cache-Control', 'no-store')
  for (const c of init.cookies ?? []) headers.append('Set-Cookie', c)
  return new Response(JSON.stringify(body), { ...init, headers })
}

export function redirect(location: string, cookies: string[] = []): Response {
  const headers = new Headers({ Location: location, 'Cache-Control': 'no-store' })
  for (const c of cookies) headers.append('Set-Cookie', c)
  return new Response(null, { status: 302, headers })
}
