import JSZip from 'jszip'
import { describe, expect, it } from 'vitest'
import { sampleState } from '../domain/sampleData'
import {
  createBackup, folderDir, openBackup, parseStateFile, photoFileName, readPhoto, readState, writeAll, writeState,
} from './dataFolder'

/** In-memory stand-in for a FileSystemDirectoryHandle (the File System Access API). */
class FakeDir {
  dirs = new Map<string, FakeDir>()
  files = new Map<string, Blob>()
  constructor(public name: string) {}
  async getDirectoryHandle(n: string, o: { create?: boolean } = {}) {
    if (!this.dirs.has(n)) {
      if (!o.create) throw new DOMException('missing', 'NotFoundError')
      this.dirs.set(n, new FakeDir(n))
    }
    return this.dirs.get(n)!
  }
  async getFileHandle(n: string, o: { create?: boolean } = {}) {
    if (!this.files.has(n)) {
      if (!o.create) throw new DOMException('missing', 'NotFoundError')
      this.files.set(n, new Blob([]))
    }
    return {
      getFile: async () => new File([this.files.get(n)!], n),
      createWritable: async () => {
        let pending: Blob = new Blob([])
        return {
          write: async (d: Blob | string) => { pending = typeof d === 'string' ? new Blob([d]) : d },
          close: async () => { this.files.set(n, pending) },
        }
      },
    }
  }
}

const jpeg = (id: string) => new Blob([`photo-${id}`], { type: 'image/jpeg' })
const asHandle = (d: FakeDir) => d as unknown as FileSystemDirectoryHandle

describe('local data folder', () => {
  it('writes a readable layout and reads the state back', async () => {
    const root = new FakeDir('PuffyMeter')
    const state = sampleState()
    await writeAll(folderDir(asHandle(root)), state, async (id) => jpeg(id), 'test')
    expect([...root.files.keys()].sort()).toEqual(['README.txt', 'puffymeter.json'])
    expect(root.dirs.get('photos')!.files.has('2026-10-08_0802.jpg')).toBe(true)
    expect(root.dirs.get('scores')!.files.has('2026-10-08_0802.json')).toBe(true)
    const back = await readState(folderDir(asHandle(root)))
    expect(back?.state.scans).toHaveLength(state.scans.length)
    expect(back?.state.settings.profile?.displayName).toBe('Alex Morgan')
    const today = state.scans[state.scans.length - 1]!
    expect(await (await readPhoto(folderDir(asHandle(root)), today))!.text()).toBe(`photo-${today.id}`)
  })

  it('does not rewrite photos that are already in the folder', async () => {
    const root = new FakeDir('PuffyMeter')
    const state = sampleState()
    let calls = 0
    await writeAll(folderDir(asHandle(root)), state, async (id) => { calls++; return jpeg(id) }, 'test')
    await writeAll(folderDir(asHandle(root)), state, async (id) => { calls++; return jpeg(id) }, 'test')
    expect(calls).toBe(state.scans.length)
  })

  it('keeps the newest savedAt in puffymeter.json', async () => {
    const root = new FakeDir('PuffyMeter')
    const state = { ...sampleState(), savedAt: '2026-10-08T15:00:00.000Z' }
    await writeState(folderDir(asHandle(root)), state, 'test')
    expect((await readState(folderDir(asHandle(root))))?.savedAt).toBe('2026-10-08T15:00:00.000Z')
  })

  it('rejects files that are not PuffyMeter state', () => {
    expect(parseStateFile('{"hello":1}')).toBeUndefined()
    expect(parseStateFile('not json')).toBeUndefined()
    expect(parseStateFile(undefined)).toBeUndefined()
  })

  it('gives same-minute scans distinct photo names', () => {
    const [a] = sampleState().scans
    const taken = new Set([photoFileName(a!)])
    const b = { ...a!, id: 'abcdef123', fileName: undefined }
    expect(photoFileName(b, taken)).toMatch(/-abcdef\.jpg$/)
  })
})

describe('backup file', () => {
  it('round-trips state and photos through a .zip', async () => {
    const state = sampleState()
    const blob = await createBackup(state, async (id) => jpeg(id), 'test')
    const opened = await openBackup(blob)
    expect(opened?.state.state.scans).toHaveLength(state.scans.length)
    const scan = state.scans[3]!
    expect(await (await readPhoto(opened!.dir, scan))!.text()).toBe(`photo-${scan.id}`)
  })

  it('accepts a zip of the folder with a parent directory', async () => {
    const inner = await JSZip.loadAsync(await (await createBackup(sampleState(), async (id) => jpeg(id), 'test')).arrayBuffer())
    const outer = new JSZip()
    for (const [path, file] of Object.entries(inner.files)) {
      if (!file.dir) outer.file(`PuffyMeter/${path}`, await file.async('uint8array'))
    }
    const opened = await openBackup(await outer.generateAsync({ type: 'blob' }))
    expect(opened?.state.state.scans.length).toBeGreaterThan(0)
    expect(await readPhoto(opened!.dir, sampleState().scans[0]!)).toBeDefined()
  })

  it('rejects random zips', async () => {
    const z = new JSZip()
    z.file('hello.txt', 'hi')
    expect(await openBackup(await z.generateAsync({ type: 'blob' }))).toBeUndefined()
  })
})
