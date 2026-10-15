// Google sign-in for the web with Google Identity Services (token model, no backend).
// Profile scopes at sign-in; the non-sensitive `drive.file` scope is requested incrementally on
// the Connect Google Drive screen. Tokens live in memory and sessionStorage only (≈1 hour).

import type { UserProfile } from '../domain/types'

const CLIENT_ID = (import.meta.env.VITE_GOOGLE_CLIENT_ID as string | undefined)?.trim() || undefined
export const DRIVE_SCOPE = 'https://www.googleapis.com/auth/drive.file'
const PROFILE_SCOPES = 'openid email profile'
const TOKEN_KEY = 'puffymeter.googleToken'

interface TokenResponse { access_token?: string; expires_in?: number; scope?: string; error?: string; error_description?: string }
interface TokenClient { requestAccessToken(o?: { prompt?: string; scope?: string; include_granted_scopes?: boolean; hint?: string }): void }
interface GoogleGlobal {
  accounts: { oauth2: {
    initTokenClient(c: { client_id: string; scope: string; callback: (r: TokenResponse) => void; error_callback?: (e: { type: string }) => void }): TokenClient
    revoke(token: string, done?: () => void): void
  } }
}
declare global { interface Window { google?: GoogleGlobal } }

export class AuthError extends Error {
  constructor(public kind: 'cancelled' | 'network' | 'notConfigured' | 'scopeDenied' | 'notSignedIn' | 'other', message?: string) {
    super(message ?? kind)
  }
  get userMessage(): string | undefined {
    switch (this.kind) {
      case 'cancelled': return undefined
      case 'network': return "Couldn't reach Google. Check your connection and try again."
      case 'notConfigured': return "Google sign-in isn't set up on this site yet. Choose “Use without an account” for now."
      case 'scopeDenied': return 'PuffyMeter needs permission to save to one Drive folder.'
      case 'notSignedIn': return 'Please sign in to Google again.'
      default: return this.message
    }
  }
}

let scriptPromise: Promise<GoogleGlobal> | undefined
function loadGIS(): Promise<GoogleGlobal> {
  scriptPromise ??= new Promise((resolve, reject) => {
    if (window.google?.accounts) return resolve(window.google)
    const s = document.createElement('script')
    s.src = 'https://accounts.google.com/gsi/client'
    s.async = true
    s.onload = () => (window.google ? resolve(window.google) : reject(new AuthError('network')))
    s.onerror = () => { scriptPromise = undefined; reject(new AuthError('network')) }
    document.head.appendChild(s)
  })
  return scriptPromise
}

interface StoredToken { token: string; expiresAt: number; scope: string; email?: string }

function readToken(): StoredToken | undefined {
  try {
    const t = JSON.parse(sessionStorage.getItem(TOKEN_KEY) ?? 'null') as StoredToken | null
    return t ?? undefined
  } catch { return undefined }
}

function writeToken(t: StoredToken | undefined) {
  try {
    if (t) sessionStorage.setItem(TOKEN_KEY, JSON.stringify(t))
    else sessionStorage.removeItem(TOKEN_KEY)
  } catch { /* private mode */ }
}

async function requestToken(scope: string, prompt: string, hint?: string): Promise<StoredToken> {
  if (!CLIENT_ID) throw new AuthError('notConfigured')
  const google = await loadGIS()
  return new Promise((resolve, reject) => {
    const client = google.accounts.oauth2.initTokenClient({
      client_id: CLIENT_ID,
      scope,
      callback: (r) => {
        if (r.error || !r.access_token) {
          reject(new AuthError(r.error === 'access_denied' ? 'cancelled' : 'other', r.error_description ?? r.error))
          return
        }
        const stored = { token: r.access_token, expiresAt: Date.now() + (r.expires_in ?? 3600) * 1000 - 60_000, scope: r.scope ?? scope, email: hint }
        writeToken(stored)
        resolve(stored)
      },
      error_callback: (e) => reject(new AuthError(e.type === 'popup_closed' ? 'cancelled' : 'other', 'Sign-in window was blocked or closed.')),
    })
    client.requestAccessToken({ prompt, scope, include_granted_scopes: true, hint })
  })
}

export const GoogleAuth = {
  configured: !!CLIENT_ID,

  /** Must be called from a click handler (opens Google's popup). */
  async signIn(): Promise<UserProfile> {
    const t = await requestToken(PROFILE_SCOPES, 'select_account')
    const info = await fetch('https://www.googleapis.com/oauth2/v3/userinfo', { headers: { Authorization: `Bearer ${t.token}` } })
      .then((r) => r.json() as Promise<{ name?: string; email?: string }>)
      .catch(() => { throw new AuthError('network') })
    writeToken({ ...t, email: info.email })
    return { displayName: info.name ?? 'PuffyMeter user', email: info.email, provider: 'google' }
  },

  /** Adds `drive.file`. Must be called from a click handler. */
  async requestDriveAccess(email?: string): Promise<void> {
    const t = await requestToken(`${PROFILE_SCOPES} ${DRIVE_SCOPE}`, '', email ?? readToken()?.email)
    if (!t.scope.split(' ').includes(DRIVE_SCOPE)) throw new AuthError('scopeDenied')
  },

  hasDriveToken(): boolean {
    const t = readToken()
    return !!t && t.expiresAt > Date.now() && t.scope.split(' ').includes(DRIVE_SCOPE)
  },

  /** A valid Drive token, or throws `notSignedIn` (the UI then offers Reconnect, a user gesture). */
  async driveToken(): Promise<string> {
    const t = readToken()
    if (t && t.expiresAt > Date.now() && t.scope.split(' ').includes(DRIVE_SCOPE)) return t.token
    throw new AuthError('notSignedIn')
  },

  async signOut(): Promise<void> {
    const t = readToken()
    writeToken(undefined)
    if (t && window.google) window.google.accounts.oauth2.revoke(t.token)
  },
}
