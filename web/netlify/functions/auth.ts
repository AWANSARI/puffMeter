// /api/auth/* — Google sign-in for PuffyMeter (same pattern as Atomic Tracker's Auth.js setup).
//
//   GET  /api/auth/config            { enabled } — is Google sign-in configured on this deploy?
//   GET  /api/auth/signin?returnTo=  302 → Google consent (openid email profile drive.file, offline)
//   GET  /api/auth/callback/google   code exchange → encrypted session cookie → 302 returnTo
//   GET  /api/auth/session           { user, drive } or 401 (never returns tokens)
//   POST /api/auth/signout           revoke + clear cookie

import {
  clearCookie, DRIVE_SCOPE, env, exchangeCode, GOOGLE_SCOPES, idTokenClaims, json, pkceChallenge, randomToken,
  readCookie, readSession, redirect, redirectURI, safeReturnTo, sessionCookie, SESSION_COOKIE, STATE_COOKIE,
  stateCookie, unseal, type OAuthState, type Session,
} from '../lib/session'

export const config = { path: '/api/auth/*' }

export default async function handler(req: Request): Promise<Response> {
  const url = new URL(req.url)
  const action = url.pathname.replace(/^\/api\/auth\/?/, '')
  const e = env()

  if (action === 'config') return json({ enabled: !!e })
  if (!e) return json({ error: 'not_configured' }, { status: 503 })

  switch (action) {
    case 'signin': {
      const state = randomToken(16)
      const verifier = randomToken(32)
      const returnTo = safeReturnTo(url.searchParams.get('returnTo'))
      const auth = new URL('https://accounts.google.com/o/oauth2/v2/auth')
      auth.search = new URLSearchParams({
        client_id: e.clientId,
        redirect_uri: redirectURI(req),
        response_type: 'code',
        scope: GOOGLE_SCOPES,
        // offline + consent ensures Google sends a refresh_token.
        access_type: 'offline',
        prompt: 'consent',
        include_granted_scopes: 'true',
        state,
        code_challenge: await pkceChallenge(verifier),
        code_challenge_method: 'S256',
      }).toString()
      const hint = url.searchParams.get('login_hint')
      if (hint) auth.searchParams.set('login_hint', hint)
      return redirect(auth.toString(), [await stateCookie(req, { state, verifier, returnTo }, e.secret)])
    }

    case 'callback/google': {
      const back = (path: string, error?: string) => {
        const target = new URL(path, url.origin)
        if (error) target.searchParams.set('error', error)
        return target.pathname + target.search
      }
      const raw = readCookie(req, STATE_COOKIE)
      const saved = raw ? await unseal<OAuthState>(raw, e.secret) : undefined
      const returnTo = saved?.returnTo ?? '/auth/complete'
      const error = url.searchParams.get('error')
      if (error) return redirect(back(returnTo, error === 'access_denied' ? 'cancelled' : error), [clearCookie(req, STATE_COOKIE)])
      const code = url.searchParams.get('code')
      if (!saved || !code || url.searchParams.get('state') !== saved.state) {
        return redirect(back(returnTo, 'state_mismatch'), [clearCookie(req, STATE_COOKIE)])
      }
      try {
        const t = await exchangeCode(e, code, saved.verifier, redirectURI(req))
        const claims = idTokenClaims(t.id_token)
        const previous = await readSession(req, e.secret)
        const session: Session = {
          sub: claims.sub ?? previous?.sub ?? 'unknown',
          name: claims.name, email: claims.email, picture: claims.picture,
          accessToken: t.access_token,
          // Google only sends a refresh token on consent; keep the old one if this time it didn't.
          refreshToken: t.refresh_token ?? previous?.refreshToken,
          expiresAt: Math.floor(Date.now() / 1000) + t.expires_in,
          scope: t.scope ?? GOOGLE_SCOPES,
        }
        return redirect(returnTo, [await sessionCookie(req, session, e.secret), clearCookie(req, STATE_COOKIE)])
      } catch {
        return redirect(back(returnTo, 'exchange_failed'), [clearCookie(req, STATE_COOKIE)])
      }
    }

    case 'session': {
      const s = await readSession(req, e.secret)
      if (!s) return json({ user: null }, { status: 401 })
      return json({
        user: { name: s.name, email: s.email, picture: s.picture },
        drive: s.scope.split(' ').includes(DRIVE_SCOPE),
        canRefresh: !!s.refreshToken,
      })
    }

    case 'signout': {
      if (req.method !== 'POST') return json({ error: 'method' }, { status: 405 })
      const s = await readSession(req, e.secret)
      const token = s?.refreshToken ?? s?.accessToken
      if (token) {
        await fetch(`https://oauth2.googleapis.com/revoke?token=${encodeURIComponent(token)}`, { method: 'POST' }).catch(() => undefined)
      }
      return json({ ok: true }, { cookies: [clearCookie(req, SESSION_COOKIE)] })
    }

    default:
      return json({ error: 'not_found' }, { status: 404 })
  }
}
