import { readFileSync } from 'node:fs'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

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

export default defineConfig({
  plugins: [react()],
  build: { target: 'es2022', sourcemap: false },
  preview: { headers: productionHeaders() },
  test: { environment: 'node' },
} as never)
