// Scan photos live in this browser's IndexedDB (never on a PuffyMeter server). The user's
// Google Drive folder is the backup.

const DB_NAME = 'puffymeter'
const STORE = 'photos'

let dbPromise: Promise<IDBDatabase> | undefined

function db(): Promise<IDBDatabase> {
  dbPromise ??= new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, 1)
    req.onupgradeneeded = () => req.result.createObjectStore(STORE)
    req.onsuccess = () => resolve(req.result)
    req.onerror = () => reject(req.error)
  })
  return dbPromise
}

function tx<T>(mode: IDBTransactionMode, run: (s: IDBObjectStore) => IDBRequest<T>): Promise<T> {
  return db().then((d) => new Promise<T>((resolve, reject) => {
    const req = run(d.transaction(STORE, mode).objectStore(STORE))
    req.onsuccess = () => resolve(req.result)
    req.onerror = () => reject(req.error)
  }))
}

const urlCache = new Map<string, string>()
const listeners = new Set<() => void>()

export const PhotoStore = {
  photoKey: (scanID: string) => `${scanID}.jpg`,
  thumbKey: (scanID: string) => `${scanID}-thumb.jpg`,

  async save(scanID: string, photo: Blob): Promise<void> {
    const thumb = await resizeJPEG(photo, 360, 0.8)
    await tx('readwrite', (s) => s.put(photo, PhotoStore.photoKey(scanID)))
    await tx('readwrite', (s) => s.put(thumb, PhotoStore.thumbKey(scanID)))
    for (const key of [PhotoStore.photoKey(scanID), PhotoStore.thumbKey(scanID)]) {
      const old = urlCache.get(key)
      if (old) URL.revokeObjectURL(old)
      urlCache.delete(key)
    }
    listeners.forEach((l) => l())
  },

  async get(key: string): Promise<Blob | undefined> {
    return (await tx<Blob | undefined>('readonly', (s) => s.get(key))) ?? undefined
  },

  async url(key: string): Promise<string | undefined> {
    const cached = urlCache.get(key)
    if (cached) return cached
    const blob = await PhotoStore.get(key)
    if (!blob) return undefined
    const url = URL.createObjectURL(blob)
    urlCache.set(key, url)
    return url
  },

  async remove(scanID: string): Promise<void> {
    await tx('readwrite', (s) => s.delete(PhotoStore.photoKey(scanID)))
    await tx('readwrite', (s) => s.delete(PhotoStore.thumbKey(scanID)))
  },

  async clear(): Promise<void> {
    await tx('readwrite', (s) => s.clear())
    urlCache.forEach((u) => URL.revokeObjectURL(u))
    urlCache.clear()
    listeners.forEach((l) => l())
  },

  onChange(listener: () => void): () => void {
    listeners.add(listener)
    return () => listeners.delete(listener)
  },
}

export async function loadImage(blob: Blob): Promise<ImageBitmap> {
  return createImageBitmap(blob)
}

/** Re-encodes a JPEG with its longest side limited. Canvas re-encoding also drops EXIF/GPS. */
export async function resizeJPEG(blob: Blob, maxSide: number | undefined, quality: number): Promise<Blob> {
  const bitmap = await createImageBitmap(blob)
  const scale = maxSide ? Math.min(1, maxSide / Math.max(bitmap.width, bitmap.height)) : 1
  const canvas = document.createElement('canvas')
  canvas.width = Math.round(bitmap.width * scale)
  canvas.height = Math.round(bitmap.height * scale)
  canvas.getContext('2d')!.drawImage(bitmap, 0, 0, canvas.width, canvas.height)
  bitmap.close()
  return canvasToBlob(canvas, quality)
}

export function canvasToBlob(canvas: HTMLCanvasElement, quality = 0.9): Promise<Blob> {
  return new Promise((resolve, reject) =>
    canvas.toBlob((b) => (b ? resolve(b) : reject(new Error('encode failed'))), 'image/jpeg', quality))
}
