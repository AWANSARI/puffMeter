import { readFileSync } from 'node:fs'
import type { IncomingMessage, ServerResponse } from 'node:http'
import { defineConfig, loadEnv, type Plugin } from 'vite'
import react from '@vitejs/plugin-react'
import auth from './netlify/functions/auth'
import google from './netlify/functions/google'

// Mirror the production security headers (public/_headers, applied by Netlify) in `vite preview`
// so CSP problems show up locally before deploying.
function productionHeaders(): Record<string, string> {
  const headers: Record<string, string> = {}
  let inRoot = false
  for (const line of readFileSync(new URL('./public/_headers', import.meta.url), 'utf8').split('\n')) {
    if (!line.startsWith(' ') && line.trim()) inRoot = line.trim() === '/*'
    else if (inRoot && line.includes(':')) {
      const i = line.indexOf(':')
      headers[line.slice(0, i).trim()] = line.slice(i + 1).trim()
    }
  }
  return headers
}

/**
 * Runs the Netlify functions (/api/auth/*, /api/google/*) inside Vite's dev and preview servers,
 * so Google sign-in works locally with AUTH_GOOGLE_ID / AUTH_GOOGLE_SECRET / AUTH_SECRET in
 * .env.local — the same setup Atomic Tracker uses for `npm run dev`.
 */
function netlifyFunctions(): Plugin {
  const routes: [string, (req: Request) => Promise<Response>][] = [['/api/auth/', auth], ['/api/google/', google]]
  const middleware = async (req: IncomingMessage, res: ServerResponse, next: () => void) => {
    const route = routes.find(([prefix]) => req.url?.startsWith(prefix))
    if (!route) return next()
    const chunks: Buffer[] = []
    for await (const chunk of req) chunks.push(chunk as Buffer)
    const headers = new Headers()
    for (const [k, v] of Object.entries(req.headers)) if (typeof v === 'string') headers.set(k, v)
    const request = new Request(`http://${req.headers.host}${req.url}`, {
      method: req.method, headers, body: chunks.length && req.method !== 'GET' ? Buffer.concat(chunks) : undefined,
    })
    const response = await route[1](request)
    res.statusCode = response.status
    response.headers.forEach((value, key) => { if (key !== 'set-cookie') res.setHeader(key, value) })
    const cookies = response.headers.getSetCookie()
    if (cookies.length) res.setHeader('Set-Cookie', cookies)
    res.end(Buffer.from(await response.arrayBuffer()))
  }
  return {
    name: 'netlify-functions-local',
    configureServer: (server) => { server.middlewares.use(middleware) },
    configurePreviewServer: (server) => { server.middlewares.use(middleware) },
  }
}

export default defineConfig(({ mode }) => {
  // Make AUTH_* from .env.local visible to the functions (they read process.env like on Netlify).
  Object.assign(process.env, loadEnv(mode, process.cwd(), 'AUTH_'))
  return {
    plugins: [react(), netlifyFunctions()],
    build: { target: 'es2022', sourcemap: false },
    preview: { headers: productionHeaders() },
    test: { environment: 'node' },
  }
})
