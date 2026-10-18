// Google sign-in, Atomic Tracker style: a full-page redirect to Google handled by our Netlify
// functions (/api/auth/*). The server keeps the refresh token in an encrypted HttpOnly cookie,
// so sessions last for months and no Google token is ever visible to page JavaScript.

import type { UserProfile } from '../domain/types'

export interface GoogleSession {
  user: { name?: string; email?: string; picture?: string }
  /** Whether the user granted the drive.file permission (Google lets people untick it). */
  drive: boolean
  canRefresh: boolean
}

export class AuthError extends Error {
  constructor(public kind: 'cancelled' | 'network' | 'notConfigured' | 'scopeDenied' | 'notSignedIn' | 'other', message?: string) {
    super(message ?? kind)
  }
  get userMessage(): string | undefined {
    return authErrorMessage(this.kind)
  }
}

/** User-facing text for errors from the OAuth callback (?error=…) and the client. */
export function authErrorMessage(code: string | null | undefined): string | undefined {
  switch (code) {
    case null: case undefined: case 'cancelled': return undefined
    case 'network': return "Couldn't reach Google. Check your connection and try again."
    case 'notConfigured': case 'not_configured': return "Google sign-in isn't set up on this site yet. Choose “Use without an account” for now."
    case 'scopeDenied': return 'PuffyMeter needs permission to save to one Drive folder. Tick the Google Drive box when you sign in.'
    case 'notSignedIn': return 'Please sign in to Google again.'
    case 'state_mismatch': return 'Sign-in expired. Please try again.'
    default: return "Google sign-in didn't complete. Please try again."
  }
}

let configPromise: Promise<boolean> | undefined

export const GoogleAuth = {
  /** True when this deploy has AUTH_GOOGLE_ID / AUTH_GOOGLE_SECRET / AUTH_SECRET set. */
  enabled(): Promise<boolean> {
    configPromise ??= fetch('/api/auth/config', { cache: 'no-store' })
      .then((r) => (r.ok ? (r.json() as Promise<{ enabled: boolean }>) : { enabled: false }))
      .then((c) => !!c.enabled)
      .catch(() => false)
    return configPromise
  },

  /** Leaves the page for Google's consent screen; Google returns to `returnTo` (a path in this app). */
  signIn(returnTo = '/auth/complete', loginHint?: string) {
    const params = new URLSearchParams({ returnTo })
    if (loginHint) params.set('login_hint', loginHint)
    location.assign(`/api/auth/signin?${params}`)
  },

  async session(): Promise<GoogleSession | null> {
    try {
      const res = await fetch('/api/auth/session', { cache: 'no-store', credentials: 'same-origin' })
      if (!res.ok) return null
      const body = (await res.json()) as GoogleSession & { user: GoogleSession['user'] | null }
      return body.user ? body : null
    } catch {
      return null
    }
  },

  async signOut(): Promise<void> {
    await fetch('/api/auth/signout', { method: 'POST', credentials: 'same-origin' }).catch(() => undefined)
  },

  profile(s: GoogleSession): UserProfile {
    return { displayName: s.user.name ?? 'PuffyMeter user', email: s.user.email, provider: 'google' }
  },
}
