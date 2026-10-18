// The PuffyMeter data layout, shared by a real folder on the device (File System Access API) and
// by backup .zip files. Plain files, readable without PuffyMeter:
//
//   puffymeter.json              everything: scans, habits, goals, awards, settings
//   photos/2026-10-08_0802.jpg   daily photos (full size)
//   scores/2026-10-08_0802.json  one scores file per scan (same format as Google Drive)
//   README.txt

import JSZip from 'jszip'
import { History } from '../domain/engine'
import { DriveNaming, scanExport } from '../domain/export'
import { emptyState, type PersistedState, type ScanRecord } from '../domain/types'

export const STATE_FILE = 'puffymeter.json'
export const FORMAT = 'puffymeter'

export interface StateFile {
  format: typeof FORMAT
  version: 1
  savedAt: string
  app: string
  state: PersistedState
}

/** Minimal file access shared by folders and zips. Paths use "/" and are relative to the root. */
export interface DataDir {
  readText(path: string): Promise<string | undefined>
  readBlob(path: string): Promise<Blob | undefined>
  write(path: string, data: Blob | string): Promise<void>
  exists(path: string): Promise<boolean>
}

const README = `PuffyMeter data folder
======================

This folder holds your PuffyMeter data as ordinary files:

  puffymeter.json   everything PuffyMeter knows (scores, habits, goals, awards, settings)
  photos/           your daily scan photos
  scores/           one small JSON file per scan

Open PuffyMeter and choose this folder (or a backup .zip of it) to pick up where you left off.
Keep it somewhere you back up. PuffyMeter is cosmetic wellness tracking, not a medical diagnosis.
`

/** Stable, human-readable photo name for a scan ("2026-10-08_0802.jpg"); unique within `taken`. */
export function photoFileName(scan: ScanRecord, taken: Set<string> = new Set()): string {
  if (scan.fileName) return scan.fileName
  const base = DriveNaming.baseName(new Date(scan.capturedAt))
  let name = `${base}.jpg`
  if (taken.has(name)) name = `${base}-${scan.id.slice(0, 6)}.jpg`
  return name
}

export function stateFile(state: PersistedState, app: string): StateFile {
  const savedAt = state.savedAt ?? new Date().toISOString()
  return { format: FORMAT, version: 1, savedAt, app, state: { ...state, savedAt } }
}

/** Parses puffymeter.json; returns undefined for anything that isn't a PuffyMeter state file. */
export function parseStateFile(text: string | undefined): StateFile | undefined {
  if (!text) return undefined
  try {
    const f = JSON.parse(text) as Partial<StateFile>
    if (f.format !== FORMAT || !f.state || !Array.isArray(f.state.scans)) return undefined
    return { ...f, state: { ...emptyState(), ...f.state } } as StateFile
  } catch {
    return undefined
  }
}

export async function readState(dir: DataDir): Promise<StateFile | undefined> {
  return parseStateFile(await dir.readText(STATE_FILE))
}

export async function writeState(dir: DataDir, state: PersistedState, app: string): Promise<void> {
  await dir.write(STATE_FILE, JSON.stringify(stateFile(state, app), null, 1))
}

export async function writeScan(dir: DataDir, scan: ScanRecord, state: PersistedState, photo: Blob | undefined, app: string) {
  const name = photoFileName(scan)
  if (photo) await dir.write(`photos/${name}`, photo)
  const h = new History(state.scans, state.habitLogs, state.goals)
  const baseline = h.baseline
  const json = scanExport(scan, {
    baselineID: baseline?.id, deltaVsYesterday: h.deltaVsPrevious(scan.dayKey),
    deltaVsBaseline: baseline ? scan.score - baseline.score : undefined, habits: h.habits.get(scan.dayKey), appVersion: app,
  })
  await dir.write(`scores/${name.replace(/\.jpg$/, '.json')}`, JSON.stringify(json, null, 2))
}

/** Writes everything (state, every photo + scores file, README). Used for backups and first folder setup. */
export async function writeAll(dir: DataDir, state: PersistedState, getPhoto: (id: string) => Promise<Blob | undefined>,
  app: string, onProgress?: (done: number, total: number) => void): Promise<void> {
  await dir.write('README.txt', README)
  let done = 0
  for (const scan of state.scans) {
    const name = photoFileName(scan)
    const already = await dir.exists(`photos/${name}`)
    await writeScan(dir, scan, state, already ? undefined : await getPhoto(scan.id), app)
    onProgress?.(++done, state.scans.length)
  }
  await writeState(dir, state, app)
}

export async function readPhoto(dir: DataDir, scan: ScanRecord): Promise<Blob | undefined> {
  return dir.readBlob(`photos/${photoFileName(scan)}`)
}

// MARK: Folder on this device (File System Access API: desktop Chrome/Edge, Android Chrome 132+)

type DirHandle = FileSystemDirectoryHandle & {
  queryPermission?: (d: { mode: 'read' | 'readwrite' }) => Promise<PermissionState>
  requestPermission?: (d: { mode: 'read' | 'readwrite' }) => Promise<PermissionState>
}

export const folderSupported = () => typeof window !== 'undefined' && 'showDirectoryPicker' in window

export async function pickFolder(): Promise<FileSystemDirectoryHandle> {
  const picker = (window as unknown as { showDirectoryPicker: (o: object) => Promise<FileSystemDirectoryHandle> }).showDirectoryPicker
  return picker({ id: 'puffymeter-data', mode: 'readwrite', startIn: 'documents' })
}

/** 'granted', 'prompt' (needs a tap to re-allow) or 'denied'. Pass request=true from a click handler. */
export async function folderPermission(handle: FileSystemDirectoryHandle, request = false): Promise<PermissionState> {
  const h = handle as DirHandle
  try {
    const state = (await h.queryPermission?.({ mode: 'readwrite' })) ?? 'granted'
    if (state === 'granted' || !request) return state
    return (await h.requestPermission?.({ mode: 'readwrite' })) ?? 'denied'
  } catch {
    return 'denied'
  }
}

export function folderDir(root: FileSystemDirectoryHandle): DataDir {
  async function dirFor(path: string, create: boolean): Promise<{ dir: FileSystemDirectoryHandle; name: string } | undefined> {
    const parts = path.split('/')
    const name = parts.pop()!
    let dir = root
    try {
      for (const p of parts) dir = await dir.getDirectoryHandle(p, { create })
    } catch {
      return undefined
    }
    return { dir, name }
  }
  async function file(path: string): Promise<File | undefined> {
    const loc = await dirFor(path, false)
    if (!loc) return undefined
    try {
      return await (await loc.dir.getFileHandle(loc.name)).getFile()
    } catch {
      return undefined
    }
  }
  return {
    readText: async (path) => (await file(path))?.text(),
    readBlob: (path) => file(path),
    exists: async (path) => !!(await file(path)),
    async write(path, data) {
      const loc = await dirFor(path, true)
      if (!loc) throw new Error(`Can't create ${path}`)
      const handle = await loc.dir.getFileHandle(loc.name, { create: true })
      // createWritable writes to a temporary file and swaps it in on close, so a crash never
      // leaves a half-written puffymeter.json behind.
      const writable = await handle.createWritable()
      await writable.write(data)
      await writable.close()
    },
  }
}

// MARK: Backup .zip (works everywhere, including iPhone via the Files app)

export function zipDir(zip: JSZip): DataDir {
  return {
    readText: async (path) => zip.file(path)?.async('string'),
    readBlob: async (path) => {
      const f = zip.file(path)
      return f ? new Blob([await f.async('arraybuffer')], { type: path.endsWith('.jpg') ? 'image/jpeg' : 'application/octet-stream' }) : undefined
    },
    exists: async (path) => !!zip.file(path),
    write: async (path, data) => { zip.file(path, data) },
  }
}

export async function createBackup(state: PersistedState, getPhoto: (id: string) => Promise<Blob | undefined>, app: string,
  onProgress?: (done: number, total: number) => void): Promise<Blob> {
  const zip = new JSZip()
  // Photos are already JPEG, so "STORE" (no compression) keeps it fast on phones.
  await writeAll(zipDir(zip), state, getPhoto, app, onProgress)
  return zip.generateAsync({ type: 'blob', compression: 'STORE', mimeType: 'application/zip' })
}

export async function openBackup(file: Blob): Promise<{ dir: DataDir; state: StateFile } | undefined> {
  try {
    const zip = await JSZip.loadAsync(await file.arrayBuffer())
    // Accept a zip of the folder itself (puffymeter.json at the root) or of its parent.
    const stateEntry = zip.file(STATE_FILE) ?? zip.file(/(^|\/)puffymeter\.json$/)[0]
    if (!stateEntry) return undefined
    const prefix = stateEntry.name.slice(0, -STATE_FILE.length)
    const dir = zipDir(prefix ? zip.folder(prefix.replace(/\/$/, ''))! : zip)
    const state = await readState(dir)
    return state ? { dir, state } : undefined
  } catch {
    return undefined
  }
}

export function backupFileName(date = new Date()): string {
  return `PuffyMeter-backup-${DriveNaming.baseName(date)}.zip`
}
