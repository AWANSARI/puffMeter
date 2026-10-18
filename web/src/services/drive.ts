// Google Drive REST v3 with the non-sensitive `drive.file` scope: PuffyMeter only sees files and
// folders it created (see docs/adr/001-drive-scope.md). Requests go through our /api/google proxy
// (a Netlify function), which adds the user's token server-side. Plus a mock used by demo mode.

import { DriveNaming } from '../domain/export'
import type { UploadFailure } from '../domain/types'

export interface DriveFolder { id: string; name: string }

export class DriveError extends Error {
  constructor(public failure: UploadFailure) { super(failure) }
}

export interface DriveApi {
  /** Finds or creates the default "PuffyMeter Daily" folder at the My Drive root. */
  ensureAppFolder(): Promise<DriveFolder>
  listFolders(parentID?: string, query?: string): Promise<DriveFolder[]>
  createFolder(name: string, parentID?: string): Promise<DriveFolder>
  upload(data: Blob, name: string, parentID: string, appProperties: Record<string, string>, onProgress: (p: number) => void): Promise<string>
  fileCount(folderID: string): Promise<number>
  listScoreFiles(folderID: string): Promise<DriveFolder[]>
  download(fileID: string): Promise<Blob>
}

const API = '/api/google/drive/v3'
const UPLOAD = '/api/google/upload/drive/v3/files'
const FOLDER_MIME = 'application/vnd.google-apps.folder'
const esc = (v: string) => v.replace(/\\/g, '\\\\').replace(/'/g, "\\'")

export function failureForStatus(status: number, body = ''): UploadFailure {
  if (status === 401) return 'authExpired'
  if (status === 403) {
    if (body.includes('storageQuotaExceeded')) return 'quotaExceeded'
    if (body.includes('rateLimitExceeded')) return 'server'
    return 'authExpired'
  }
  if (status === 404) return 'folderMissing'
  if (status === 429 || status >= 500) return 'server'
  return 'unknown'
}

async function call<T>(url: string, init: RequestInit = {}): Promise<T> {
  let res: Response
  try {
    res = await fetch(url, { ...init, credentials: 'same-origin', cache: 'no-store' })
  } catch {
    throw new DriveError('network')
  }
  if (!res.ok) throw new DriveError(failureForStatus(res.status, await res.text().catch(() => '')))
  return (init.method === 'GET' || !init.method) && url.includes('alt=media') ? (res.blob() as Promise<T>) : (res.json() as Promise<T>)
}

async function listFiles(q: string, orderBy?: string): Promise<DriveFolder[]> {
  const out: DriveFolder[] = []
  let pageToken: string | undefined
  do {
    const params = new URLSearchParams({ q, fields: 'nextPageToken,files(id,name)', pageSize: '200', spaces: 'drive' })
    if (orderBy) params.set('orderBy', orderBy)
    if (pageToken) params.set('pageToken', pageToken)
    const page = await call<{ files: DriveFolder[]; nextPageToken?: string }>(`${API}/files?${params}`)
    out.push(...page.files)
    pageToken = page.nextPageToken
  } while (pageToken)
  return out
}

export const GoogleDrive: DriveApi = {
  async ensureAppFolder() {
    const name = DriveNaming.defaultFolderName
    const q = `name='${esc(name)}' and 'root' in parents and mimeType='${FOLDER_MIME}' and trashed=false`
    const existing = await listFiles(q)
    return existing[0] ?? GoogleDrive.createFolder(name)
  },

  listFolders(parentID, query) {
    let q = `'${esc(parentID ?? 'root')}' in parents and mimeType='${FOLDER_MIME}' and trashed=false`
    if (query?.trim()) q += ` and name contains '${esc(query.trim())}'`
    return listFiles(q, 'name')
  },

  createFolder(name, parentID) {
    return call<DriveFolder>(`${API}/files?fields=id,name`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        name, mimeType: FOLDER_MIME, parents: parentID ? [parentID] : undefined,
        appProperties: { [DriveNaming.appPropertyKey]: '1', kind: 'folder' },
      }),
    })
  },

  /** Multipart upload via XHR so we get progress events. Files are small (< 5 MB). */
  async upload(data, name, parentID, appProperties, onProgress) {
    const metadata = { name, parents: [parentID], mimeType: data.type, appProperties: { ...appProperties, [DriveNaming.appPropertyKey]: '1' } }
    const form = new FormData()
    form.append('metadata', new Blob([JSON.stringify(metadata)], { type: 'application/json' }))
    form.append('file', data)
    return new Promise<string>((resolve, reject) => {
      const xhr = new XMLHttpRequest()
      xhr.open('POST', `${UPLOAD}?uploadType=multipart&fields=id`)
      xhr.withCredentials = true
      xhr.upload.onprogress = (e) => { if (e.lengthComputable) onProgress(Math.min(0.99, e.loaded / e.total)) }
      xhr.onload = () => {
        if (xhr.status >= 200 && xhr.status < 300) {
          onProgress(1)
          resolve((JSON.parse(xhr.responseText) as { id: string }).id)
        } else {
          reject(new DriveError(failureForStatus(xhr.status, xhr.responseText)))
        }
      }
      xhr.onerror = () => reject(new DriveError('network'))
      xhr.send(form)
    })
  },

  async fileCount(folderID) {
    return (await listFiles(`'${esc(folderID)}' in parents and trashed=false`)).length
  },

  listScoreFiles(folderID) {
    return listFiles(`'${esc(folderID)}' in parents and trashed=false and mimeType='application/json' and ` +
      `appProperties has { key='${DriveNaming.appPropertyKey}' and value='1' }`, 'name')
  },

  download(fileID) {
    return call<Blob>(`${API}/files/${fileID}?alt=media`)
  },
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))

/** Behaves like Drive (latency, progress) without a Google account. Used by demo mode. */
export function createMockDrive(): DriveApi & { failNext?: UploadFailure } {
  const folders: Record<string, DriveFolder[]> = {
    root: [
      { id: 'sample-folder', name: 'PuffyMeter Daily' }, { id: 'personal', name: 'Personal' },
      { id: 'photos', name: 'Photos' }, { id: 'wellness', name: 'Wellness' },
    ],
    personal: [{ id: 'journal', name: 'Journal' }],
  }
  const files = new Map<string, Blob>()
  const mock: DriveApi & { failNext?: UploadFailure } = {
    async ensureAppFolder() {
      await sleep(400)
      return folders.root.find((f) => f.name === DriveNaming.defaultFolderName) ?? mock.createFolder(DriveNaming.defaultFolderName)
    },
    async listFolders(parentID, query) {
      await sleep(400)
      const all = folders[parentID ?? 'root'] ?? []
      return query ? all.filter((f) => f.name.toLowerCase().includes(query.toLowerCase())) : all
    },
    async createFolder(name, parentID) {
      await sleep(400)
      const f = { id: crypto.randomUUID(), name }
      ;(folders[parentID ?? 'root'] ??= []).push(f)
      folders[parentID ?? 'root'].sort((a, b) => a.name.localeCompare(b.name))
      return f
    },
    async upload(data, _name, _parent, _props, onProgress) {
      for (let i = 1; i <= 10; i++) { await sleep(120); onProgress((i / 10) * 0.99) }
      if (mock.failNext) { const f = mock.failNext; mock.failNext = undefined; throw new DriveError(f) }
      const id = `mock-${crypto.randomUUID().slice(0, 8)}`
      files.set(id, data)
      onProgress(1)
      return id
    },
    async fileCount() { return files.size + 36 },
    async listScoreFiles() { return [] },
    async download(id) {
      const f = files.get(id)
      if (!f) throw new DriveError('folderMissing')
      return f
    },
  }
  return mock
}
