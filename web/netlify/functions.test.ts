import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import auth from './functions/auth'
import google from './functions/google'
import { readSession, seal, SESSION_COOKIE, unseal, type Session } from './lib/session'

const ORIGIN = 'https://puffymeter.netlify.app'
const SECRET = 'test-secret-value'

function cookiesFrom(res: Response): Record<string, string> {
  const out: Record<string, string> = {}
  for (const c of res.headers.getSetCookie()) {
    const [pair] = c.split(';')
    const i = pair.indexOf('=')
    out[pair.slice(0, i)] = pair.slice(i + 1)
  }
  return out
}

const jsonResponse = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
const idToken = (claims: object) => `x.${Buffer.from(JSON.stringify(claims)).toString('base64url')}.y`

beforeEach(() => {
  process.env.AUTH_GOOGLE_ID = 'client-id.apps.googleusercontent.com'
  process.env.AUTH_GOOGLE_SECRET = 'client-secret'
  process.env.AUTH_SECRET = SECRET
})
afterEach(() => { vi.unstubAllGlobals() })

describe('auth function', () => {
  it('reports whether Google is configured', async () => {
    expect(await (await auth(new Request(`${ORIGIN}/api/auth/config`))).json()).toEqual({ enabled: true })
    delete process.env.AUTH_GOOGLE_SECRET
    expect(await (await auth(new Request(`${ORIGIN}/api/auth/config`))).json()).toEqual({ enabled: false })
  })

  it('full sign-in round trip: redirect → callback → session (no tokens exposed)', async () => {
    const start = await auth(new Request(`${ORIGIN}/api/auth/signin?returnTo=/auth/complete?next=/drive`))
    expect(start.status).toBe(302)
    const google = new URL(start.headers.get('Location')!)
    expect(google.host).toBe('accounts.google.com')
    expect(google.searchParams.get('access_type')).toBe('offline')
    expect(google.searchParams.get('scope')).toContain('drive.file')
    expect(google.searchParams.get('redirect_uri')).toBe(`${ORIGIN}/api/auth/callback/google`)
    expect(google.searchParams.get('code_challenge_method')).toBe('S256')
    const stateCookie = cookiesFrom(start).pm_oauth

    const fetchMock = vi.fn(async () => jsonResponse({
      access_token: 'ya29.access', expires_in: 3599, refresh_token: '1//refresh',
      scope: 'openid email profile https://www.googleapis.com/auth/drive.file',
      id_token: idToken({ sub: '123', name: 'Alex Morgan', email: 'alex@example.com' }),
    }))
    vi.stubGlobal('fetch', fetchMock)
    const cb = await auth(new Request(`${ORIGIN}/api/auth/callback/google?code=abc&state=${google.searchParams.get('state')}`,
      { headers: { cookie: `pm_oauth=${stateCookie}` } }))
    expect(cb.status).toBe(302)
    expect(cb.headers.get('Location')).toBe('/auth/complete?next=/drive')
    const body = String(fetchMock.mock.calls[0]?.[1 as never] && (fetchMock.mock.calls[0] as unknown as [string, RequestInit])[1].body)
    expect(body).toContain('client_secret=client-secret')
    expect(body).toContain('code_verifier=')
    const sessionValue = cookiesFrom(cb)[SESSION_COOKIE]
    const setCookie = cb.headers.getSetCookie().find((c) => c.startsWith(SESSION_COOKIE))!
    expect(setCookie).toMatch(/HttpOnly/)
    expect(setCookie).toMatch(/Secure/)

    const s = await auth(new Request(`${ORIGIN}/api/auth/session`, { headers: { cookie: `${SESSION_COOKIE}=${sessionValue}` } }))
    const sessionJSON = await s.json()
    expect(sessionJSON).toEqual({ user: { name: 'Alex Morgan', email: 'alex@example.com' }, drive: true, canRefresh: true })
    expect(JSON.stringify(sessionJSON)).not.toContain('ya29')
  })

  it('rejects a state mismatch and open redirects', async () => {
    const start = await auth(new Request(`${ORIGIN}/api/auth/signin?returnTo=//evil.com`))
    const state = cookiesFrom(start).pm_oauth
    const saved = await unseal<{ returnTo: string }>(state, SECRET)
    expect(saved?.returnTo).toBe('/auth/complete')
    const cb = await auth(new Request(`${ORIGIN}/api/auth/callback/google?code=abc&state=wrong`, { headers: { cookie: `pm_oauth=${state}` } }))
    expect(cb.headers.get('Location')).toBe('/auth/complete?error=state_mismatch')
  })

  it('maps a declined consent to "cancelled"', async () => {
    const start = await auth(new Request(`${ORIGIN}/api/auth/signin`))
    const cb = await auth(new Request(`${ORIGIN}/api/auth/callback/google?error=access_denied`, { headers: { cookie: `pm_oauth=${cookiesFrom(start).pm_oauth}` } }))
    expect(cb.headers.get('Location')).toBe('/auth/complete?error=cancelled')
  })
})

describe('google proxy', () => {
  const session = (expiresIn: number): Session => ({
    sub: '1', accessToken: 'old-token', refreshToken: '1//refresh', expiresAt: Math.floor(Date.now() / 1000) + expiresIn,
    scope: 'openid https://www.googleapis.com/auth/drive.file',
  })

  it('injects the token and forwards Drive calls', async () => {
    const fetchMock = vi.fn(async (_url: string, _init?: RequestInit) => jsonResponse({ files: [] }))
    vi.stubGlobal('fetch', fetchMock)
    const cookie = `${SESSION_COOKIE}=${await seal(session(3600), SECRET)}`
    const res = await google(new Request(`${ORIGIN}/api/google/drive/v3/files?q=x`, { headers: { cookie } }))
    expect(res.status).toBe(200)
    expect(fetchMock.mock.calls[0]?.[0]).toBe('https://www.googleapis.com/drive/v3/files?q=x')
    expect(new Headers(fetchMock.mock.calls[0]?.[1]?.headers).get('Authorization')).toBe('Bearer old-token')
    expect(res.headers.getSetCookie()).toHaveLength(0)
  })

  it('refreshes an expired token and updates the cookie', async () => {
    const fetchMock = vi.fn(async (url: string) => url.includes('oauth2.googleapis.com/token')
      ? jsonResponse({ access_token: 'new-token', expires_in: 3599 })
      : jsonResponse({ id: 'file1' }))
    vi.stubGlobal('fetch', fetchMock)
    const req = new Request(`${ORIGIN}/api/google/upload/drive/v3/files?uploadType=multipart`, {
      method: 'POST', body: 'payload', headers: { cookie: `${SESSION_COOKIE}=${await seal(session(-10), SECRET)}`, 'content-type': 'multipart/form-data; boundary=x' },
    })
    const res = await google(req)
    expect(res.status).toBe(200)
    const driveCall = fetchMock.mock.calls.find((c) => String(c[0]).includes('upload/drive'))!
    expect(new Headers((driveCall as unknown as [string, RequestInit])[1].headers).get('Authorization')).toBe('Bearer new-token')
    const updated = await readSession(new Request(ORIGIN, { headers: { cookie: res.headers.getSetCookie()[0]!.split(';')[0]! } }), SECRET)
    expect(updated?.accessToken).toBe('new-token')
    expect(updated?.refreshToken).toBe('1//refresh')
  })

  it('blocks non-Drive paths and unauthenticated calls', async () => {
    const cookie = `${SESSION_COOKIE}=${await seal(session(3600), SECRET)}`
    expect((await google(new Request(`${ORIGIN}/api/google/gmail/v1/users/me/messages`, { headers: { cookie } }))).status).toBe(403)
    expect((await google(new Request(`${ORIGIN}/api/google/drive/v3/about`, { headers: { cookie } }))).status).toBe(403)
    expect((await google(new Request(`${ORIGIN}/api/google/drive/v3/files`))).status).toBe(401)
  })

  it('asks the user to sign in again when the refresh token is revoked', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => jsonResponse({ error: 'invalid_grant' }, 400)))
    const res = await google(new Request(`${ORIGIN}/api/google/drive/v3/files`, { headers: { cookie: `${SESSION_COOKIE}=${await seal(session(-10), SECRET)}` } }))
    expect(res.status).toBe(401)
    expect(await res.json()).toEqual({ error: 'reauth' })
  })
})
