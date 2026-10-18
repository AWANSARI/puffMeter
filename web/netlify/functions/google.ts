// /api/google/* — authenticated proxy to the Google Drive REST API.
//
// The browser calls e.g. /api/google/drive/v3/files?q=… ; this function adds the user's access
// token from the encrypted session cookie (refreshing it when needed) and forwards the request.
// Only Drive file endpoints are allowed, and the token itself never reaches the browser.

import { clearCookie, env, freshSession, json, readSession, sessionCookie, SESSION_COOKIE } from '../lib/session'

export const config = { path: '/api/google/*' }

const ALLOWED = [/^drive\/v3\/files(\/[A-Za-z0-9_-]+)?$/, /^upload\/drive\/v3\/files$/]
const METHODS = new Set(['GET', 'POST', 'PATCH', 'DELETE'])

export default async function handler(req: Request): Promise<Response> {
  const e = env()
  if (!e) return json({ error: 'not_configured' }, { status: 503 })
  const url = new URL(req.url)
  const path = url.pathname.replace(/^\/api\/google\//, '')
  if (!ALLOWED.some((r) => r.test(path)) || !METHODS.has(req.method)) return json({ error: 'forbidden' }, { status: 403 })

  const stored = await readSession(req, e.secret)
  if (!stored) return json({ error: 'not_signed_in' }, { status: 401 })
  let fresh = await freshSession(e, stored)
  if (!fresh) return json({ error: 'reauth' }, { status: 401 })

  const body = req.method === 'GET' || req.method === 'DELETE' ? undefined : await req.arrayBuffer()
  const forward = (token: string) => {
    const headers = new Headers({ Authorization: `Bearer ${token}` })
    const type = req.headers.get('content-type')
    if (type) headers.set('Content-Type', type)
    return fetch(`https://www.googleapis.com/${path}${url.search}`, { method: req.method, headers, body })
  }

  let upstream = await forward(fresh.session.accessToken)
  if (upstream.status === 401) {
    // Token revoked or expired early: refresh once and retry.
    fresh = await freshSession(e, fresh.session, true)
    if (!fresh) return json({ error: 'reauth' }, { status: 401, headers: { 'Set-Cookie': clearCookie(req, SESSION_COOKIE) } })
    upstream = await forward(fresh.session.accessToken)
  }

  const headers = new Headers({ 'Cache-Control': 'no-store' })
  const type = upstream.headers.get('content-type')
  if (type) headers.set('Content-Type', type)
  if (fresh.refreshed) headers.append('Set-Cookie', await sessionCookie(req, fresh.session, e.secret))
  return new Response(await upstream.arrayBuffer(), { status: upstream.status, headers })
}
