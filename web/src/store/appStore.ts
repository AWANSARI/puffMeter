// The single source of truth for the UI (port of the iOS AppModel). Holds persisted state,
// coordinates the upload queue, awards and celebrations. React reads it via useApp().

import { useSyncExternalStore } from 'react'
import { addDays, dayKeyOf, type DayKey } from '../domain/dates'
import { allClosed, History, Scoring, Streaks } from '../domain/engine'
import { DriveNaming, recordFromExport, scanExport, type ScanExport } from '../domain/export'
import { ALL_AWARDS, Awards, Challenges, Insights, type AwardDefinition } from '../domain/progress'
import { SAMPLE_TODAY, sampleNow, sampleState } from '../domain/sampleData'
import {
  defaultGoals, driveFolder, emptyState, goalsFor, isTransient, suggestedTags,
  type DriveFolderRef, type GoalSet, type HabitKind, type HabitLog, type OnboardingStep, type PersistedState,
  type ScanRecord, type Settings, type UploadFailure, type UploadJob, type UserProfile,
} from '../domain/types'
import { createMockDrive, DriveError, GoogleDrive, type DriveApi } from '../services/drive'
import type { CapturedFace } from '../services/faceCamera'
import { GoogleAuth, type GoogleSession } from '../services/googleAuth'
import {
  createBackup, folderDir, folderPermission, folderSupported, openBackup, photoFileName, readPhoto, readState,
  writeAll, writeScan, writeState, type DataDir, type StateFile,
} from '../services/dataFolder'
import { KeyValue, PhotoStore, resizeJPEG } from '../services/photoStore'
import { sampleFaceJPEG } from '../services/sampleFace'

export const APP_VERSION = '1.0 (web)'
const STORAGE_KEY = 'puffymeter.state.v1'
const BACKOFF_SECONDS = [2, 8, 30, 120]

export type UploadCardState =
  | { kind: 'uploading'; progress: number }
  | { kind: 'saved'; fileName: string; path: string }
  | { kind: 'failed'; failure: UploadFailure }
  | { kind: 'queued'; count: number }
  | { kind: 'localOnly' }

/** The local data folder: connected, waiting for a tap to re-allow access, or not set up. */
export type FolderStatus =
  | { kind: 'none' }
  | { kind: 'connected'; name: string; lastSavedAt?: string }
  | { kind: 'needsPermission'; name: string }
  | { kind: 'error'; name: string; message: string }

export interface AppSnapshot {
  data: PersistedState
  loaded: boolean
  online: boolean
  awardQueue: string[]
  showAllRingsClosed: boolean
  photosRevision: number
  demo: boolean
  /** Google sign-in is configured on this deploy (Netlify env vars present). */
  googleEnabled: boolean
  folder: FolderStatus
  /** The browser promised not to clear PuffyMeter's storage automatically. */
  persistent?: boolean
}

const FOLDER_HANDLE_KEY = 'folderHandle'

const isDemo = () => new URLSearchParams(location.search).has('demo')

class AppStore {
  private snapshot: AppSnapshot
  private listeners = new Set<() => void>()
  private processing = false
  private retryTimer = 0
  private readonly startedAt = Date.now()
  readonly drive: DriveApi

  constructor() {
    const demo = isDemo()
    this.drive = demo ? createMockDrive() : GoogleDrive
    this.snapshot = { data: emptyState(), loaded: false, online: navigator.onLine, awardQueue: [], showAllRingsClosed: false, photosRevision: 0, demo, googleEnabled: demo, folder: { kind: 'none' } }
    window.addEventListener('online', () => { this.set({ online: true }); void this.processUploads() })
    window.addEventListener('offline', () => this.set({ online: false }))
    PhotoStore.onChange(() => this.set({ photosRevision: this.snapshot.photosRevision + 1 }))
  }

  // MARK: Subscription

  subscribe = (listener: () => void) => {
    this.listeners.add(listener)
    return () => { this.listeners.delete(listener) }
  }

  getSnapshot = () => this.snapshot

  private set(patch: Partial<AppSnapshot>) {
    this.snapshot = { ...this.snapshot, ...patch }
    this.listeners.forEach((l) => l())
  }

  private update(change: (d: PersistedState) => PersistedState) {
    this.set({ data: change(this.snapshot.data) })
    this.persist()
  }

  private updateSettings(patch: Partial<Settings>) {
    this.update((d) => ({ ...d, settings: { ...d.settings, ...patch } }))
  }

  private persist() {
    if (this.snapshot.demo) return // demo data lives in memory only
    this.snapshot.data.savedAt = new Date().toISOString()
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(this.snapshot.data))
    } catch { /* storage full or blocked */ }
    this.scheduleFolderSave()
  }

  // MARK: Local folder

  private folderHandle?: FileSystemDirectoryHandle
  private folderTimer = 0

  private folderDir(): DataDir | undefined {
    return this.folderHandle && this.snapshot.folder.kind === 'connected' ? folderDir(this.folderHandle) : undefined
  }

  /** Writes puffymeter.json shortly after changes settle (the folder is the durable copy). */
  private scheduleFolderSave() {
    if (!this.folderDir()) return
    clearTimeout(this.folderTimer)
    this.folderTimer = window.setTimeout(() => void this.saveStateToFolder(), 400)
  }

  private async saveStateToFolder() {
    const dir = this.folderDir()
    const folder = this.snapshot.folder
    if (!dir || folder.kind !== 'connected') return
    try {
      await writeState(dir, this.snapshot.data, APP_VERSION)
      this.set({ folder: { ...folder, lastSavedAt: new Date().toISOString() } })
    } catch (e) {
      this.set({ folder: { kind: 'error', name: folder.name, message: e instanceof Error ? e.message : 'Write failed' } })
    }
  }

  private attachFolder(handle: FileSystemDirectoryHandle) {
    this.folderHandle = handle
    this.set({ folder: { kind: 'connected', name: handle.name } })
    PhotoStore.setFallback(async (scanID) => {
      const scan = this.snapshot.data.scans.find((s) => s.id === scanID)
      return scan && this.folderHandle ? readPhoto(folderDir(this.folderHandle), scan) : undefined
    })
  }

  /** Reads the folder's puffymeter.json and adopts it when it's newer than this browser's copy. */
  private async syncFromFolder(handle: FileSystemDirectoryHandle): Promise<void> {
    const file = await readState(folderDir(handle)).catch(() => undefined)
    this.attachFolder(handle)
    const local = this.snapshot.data
    if (file && (!local.savedAt || file.savedAt > local.savedAt || local.scans.length === 0)) {
      this.adoptState(file.state, { keepFolder: true })
    } else {
      void this.saveStateToFolder()
    }
  }

  /** Looks inside a folder the user just picked: does it already hold PuffyMeter data? */
  async inspectFolder(handle: FileSystemDirectoryHandle): Promise<StateFile | undefined> {
    return readState(folderDir(handle)).catch(() => undefined)
  }

  /**
   * Starts using `handle` as the data folder. 'restore' loads the folder's data into the app;
   * 'save' writes this browser's data (and all photos) into the folder.
   */
  async useFolder(handle: FileSystemDirectoryHandle, mode: 'restore' | 'save', onProgress?: (done: number, total: number) => void) {
    await KeyValue.set(FOLDER_HANDLE_KEY, handle)
    if (mode === 'restore') {
      const file = await this.inspectFolder(handle)
      this.attachFolder(handle)
      if (file) this.adoptState(file.state, { keepFolder: true })
    } else {
      this.attachFolder(handle)
      await writeAll(folderDir(handle), this.snapshot.data, (id) => PhotoStore.get(PhotoStore.photoKey(id)), APP_VERSION, onProgress)
    }
    this.updateSettings({ storage: { kind: 'folder', name: handle.name } })
    await this.saveStateToFolder()
  }

  /** Re-allows access after a relaunch (must be called from a tap). */
  async reconnectFolder(): Promise<boolean> {
    const handle = this.folderHandle ?? (await KeyValue.get<FileSystemDirectoryHandle>(FOLDER_HANDLE_KEY))
    if (!handle) return false
    if ((await folderPermission(handle, true)) !== 'granted') return false
    await this.syncFromFolder(handle)
    return true
  }

  /** Keep going with this browser's copy for now; PuffyMeter asks again next launch. */
  skipFolderForNow() {
    this.set({ folder: { kind: 'none' } })
  }

  async stopUsingFolder() {
    await KeyValue.remove(FOLDER_HANDLE_KEY)
    this.folderHandle = undefined
    PhotoStore.setFallback(undefined)
    this.set({ folder: { kind: 'none' } })
    this.updateSettings({ storage: { kind: 'browser' } })
  }

  // MARK: Backups

  async exportBackup(onProgress?: (done: number, total: number) => void): Promise<Blob> {
    const blob = await createBackup(this.snapshot.data, (id) => PhotoStore.get(PhotoStore.photoKey(id)), APP_VERSION, onProgress)
    this.updateSettings({ lastBackupAt: new Date().toISOString() })
    return blob
  }

  /** Restores everything from a backup .zip (or a zipped PuffyMeter folder). Returns the scan count. */
  async restoreBackup(file: Blob, onProgress?: (done: number, total: number) => void): Promise<number> {
    const backup = await openBackup(file)
    if (!backup) throw new Error('not_a_backup')
    await this.importPhotos(backup.dir, backup.state.state.scans, onProgress)
    this.adoptState(backup.state.state, { keepFolder: true })
    const dir = this.folderDir()
    if (dir) await writeAll(dir, this.snapshot.data, (id) => PhotoStore.get(PhotoStore.photoKey(id)), APP_VERSION)
    return backup.state.state.scans.length
  }

  private async importPhotos(dir: DataDir, scans: ScanRecord[], onProgress?: (done: number, total: number) => void) {
    let done = 0
    for (const scan of scans) {
      const blob = await readPhoto(dir, scan)
      if (blob) await PhotoStore.save(scan.id, blob, { notify: false })
      onProgress?.(++done, scans.length)
    }
    this.set({ photosRevision: this.snapshot.photosRevision + 1 })
  }

  /** Replaces the app's data with a restored copy (from the folder or a backup). */
  private adoptState(state: PersistedState, opts: { keepFolder: boolean }) {
    const data: PersistedState = { ...emptyState(), ...state }
    if (!data.goals.length) data.goals = [defaultGoals(this.today())]
    data.uploadJobs = data.uploadJobs.map((j) => (j.state.kind === 'uploading' ? { ...j, state: { kind: 'pending' as const } } : j))
    // A folder chosen on another computer can't be reused here; keep this device's choice.
    data.settings = {
      ...data.settings,
      storage: opts.keepFolder && this.snapshot.folder.kind === 'connected'
        ? { kind: 'folder', name: this.snapshot.folder.name } : { kind: 'browser' },
    }
    this.set({ data, awardQueue: [], showAllRingsClosed: false })
    this.persist()
    void this.processUploads()
  }

  /** Asks the browser not to clear PuffyMeter's data under storage pressure or Safari's 7-day rule. */
  private async requestPersistence() {
    try {
      const persisted = (await navigator.storage?.persisted?.()) || (await navigator.storage?.persist?.()) || false
      this.set({ persistent: persisted })
    } catch { /* unsupported */ }
  }

  // MARK: Clock & derived

  now(): Date {
    return this.snapshot.demo ? new Date(sampleNow().getTime() + (Date.now() - this.startedAt)) : new Date()
  }

  today(): DayKey {
    return this.snapshot.demo ? SAMPLE_TODAY : dayKeyOf(this.now())
  }

  history(): History {
    const d = this.snapshot.data
    return historyFor(d)
  }

  // MARK: Lifecycle

  async load() {
    if (this.snapshot.loaded) return
    let data: PersistedState
    if (this.snapshot.demo) {
      data = sampleState()
    } else {
      try {
        const raw = localStorage.getItem(STORAGE_KEY)
        data = raw ? { ...emptyState(), ...(JSON.parse(raw) as PersistedState) } : emptyState()
      } catch {
        data = emptyState()
      }
    }
    if (!data.goals.length) data.goals = [defaultGoals(this.today())]
    // Interrupted uploads restart from pending.
    data.uploadJobs = data.uploadJobs.map((j) => (j.state.kind === 'uploading' ? { ...j, state: { kind: 'pending' } } : j))
    const googleEnabled = this.snapshot.demo || (await GoogleAuth.enabled())
    this.set({ data, googleEnabled })
    // Local folder first: if one was chosen, read it before showing anything.
    if (!this.snapshot.demo && folderSupported()) {
      const handle = await KeyValue.get<FileSystemDirectoryHandle>(FOLDER_HANDLE_KEY).catch(() => undefined)
      if (handle) {
        const permission = await folderPermission(handle)
        if (permission === 'granted') await this.syncFromFolder(handle)
        else {
          this.folderHandle = handle
          this.set({ folder: { kind: 'needsPermission', name: handle.name } })
        }
      }
    }
    this.set({ loaded: true })
    if (this.snapshot.demo) await this.seedDemoPhotos()
    else void this.requestPersistence()
    void this.processUploads()
  }

  private async seedDemoPhotos() {
    for (const scan of this.snapshot.data.scans) {
      if (await PhotoStore.get(PhotoStore.photoKey(scan.id))) continue
      const puffiness = Math.min(1, Math.max(0, (scan.score - 28) / 26))
      await PhotoStore.save(scan.id, await sampleFaceJPEG(puffiness, 450, 600))
    }
  }

  // MARK: Onboarding & account

  setOnboardingStep(step: OnboardingStep) {
    this.updateSettings({ onboardingStep: step })
  }

  signedIn(profile: UserProfile) {
    this.updateSettings({ profile, onboardingStep: 'driveLimitedAccess' })
  }

  /** "Use without an account": scans stay in this browser; Drive can be connected later. */
  useLocally() {
    this.updateSettings({ profile: { displayName: 'You', provider: 'local' }, drive: { kind: 'skipped' }, onboardingStep: 'storageChoice' })
  }

  connectDrive(folder: DriveFolderRef) {
    this.update((d) => {
      const jobs = [...d.uploadJobs]
      for (const scan of d.scans) if (scan.syncState !== 'synced') enqueue(jobs, scan, true)
      return { ...d, uploadJobs: jobs, settings: { ...d.settings, drive: { kind: 'connected', folder } } }
    })
    void this.processUploads()
  }

  skipDrive() {
    this.updateSettings({ drive: { kind: 'skipped' } })
  }

  disconnectDrive() {
    this.update((d) => ({ ...d, uploadJobs: [], settings: { ...d.settings, drive: { kind: 'notConnected' } } }))
  }

  /** Called after Google redirects back (/auth/complete) with a valid server session. */
  googleSignedIn(session: GoogleSession) {
    const s = this.snapshot.data.settings
    const patch: Partial<Settings> = { profile: GoogleAuth.profile(session) }
    if (s.onboardingStep === 'welcome' || s.onboardingStep === 'signIn') patch.onboardingStep = 'driveLimitedAccess'
    if (s.drive.kind === 'needsReconnect' && session.drive) patch.drive = { kind: 'connected', folder: s.drive.folder }
    this.updateSettings(patch)
    if (patch.drive) this.retryUploads()
  }

  /** Finds or creates the default Drive folder and connects it (used by onboarding and Profile). */
  async connectDefaultFolder(): Promise<DriveFolderRef> {
    const f = await this.drive.ensureAppFolder()
    const folder = { id: f.id, name: f.name, path: `My Drive / ${f.name}` }
    this.connectDrive(folder)
    return folder
  }

  async signOut(deleteLocalData: boolean) {
    await GoogleAuth.signOut()
    if (deleteLocalData) await this.deleteAllData()
    else this.updateSettings({ profile: undefined, onboardingStep: 'signIn' })
  }

  /** Erases PuffyMeter from this browser. Files in the local folder / Drive are left untouched. */
  async deleteAllData() {
    await KeyValue.remove(FOLDER_HANDLE_KEY).catch(() => undefined)
    this.folderHandle = undefined
    PhotoStore.setFallback(undefined)
    this.set({ folder: { kind: 'none' } })
    await PhotoStore.clear()
    try { localStorage.removeItem(STORAGE_KEY) } catch { /* ignore */ }
    const data = emptyState()
    data.goals = [defaultGoals(this.today())]
    this.set({ data, awardQueue: [], showAllRingsClosed: false })
    this.persist()
  }

  // MARK: Settings, goals, challenges

  setSettings(patch: Partial<Settings>) {
    this.updateSettings(patch)
  }

  updateGoals(goals: Omit<GoalSet, 'effectiveFrom'>) {
    const today = this.today()
    this.update((d) => ({ ...d, goals: [...d.goals.filter((g) => g.effectiveFrom !== today), { ...goals, effectiveFrom: today }] }))
    this.afterActivityChange()
  }

  joinChallenge(id: string) {
    if (this.snapshot.data.challengeRecords.some((r) => r.challengeID === id)) return
    this.update((d) => ({ ...d, challengeRecords: [...d.challengeRecords, { challengeID: id, joinedAt: this.now().toISOString() }] }))
    this.afterActivityChange()
  }

  // MARK: Habits

  logHabit(change: Partial<HabitLog>) {
    const today = this.today()
    this.update((d) => {
      const existing = d.habitLogs.find((h) => h.dayKey === today) ?? { dayKey: today }
      return { ...d, habitLogs: [...d.habitLogs.filter((h) => h.dayKey !== today), { ...existing, ...change, dayKey: today }] }
    })
    this.afterActivityChange()
  }

  clearHabit(kind: HabitKind) {
    const key = ({ water: 'waterLiters', sleep: 'sleepHours', salt: 'salt', alcohol: 'alcohol' } as const)[kind]
    this.logHabit({ [key]: undefined } as Partial<HabitLog>)
  }

  // MARK: Scans

  /** Scores and stores a capture. Retakes on the same day replace the day's scan. */
  async recordScan(capture: CapturedFace, isBaseline: boolean): Promise<ScanRecord> {
    const h = this.history()
    const raw = capture.raw
    const baselineRaw = isBaseline ? raw : (h.baseline?.raw ?? raw)
    const reference = Scoring.reference(baselineRaw, h.scans.filter((s) => !s.lowConfidence).map((s) => s.raw))
    const result = Scoring.score(raw, capture.quality, reference)
    const id = crypto.randomUUID()
    await PhotoStore.save(id, capture.blob)
    const taken = new Set(this.snapshot.data.scans.map((x) => photoFileName(x)))
    const day = this.snapshot.demo ? this.today() : dayKeyOf(capture.capturedAt)
    const capturedAt = this.snapshot.demo ? this.now() : capture.capturedAt
    const firstScan = this.snapshot.data.scans.length === 0
    const record: ScanRecord = {
      id, capturedAt: capturedAt.toISOString(), dayKey: day, score: result.overall, zones: result.zones, raw,
      quality: capture.quality, lowConfidence: isBaseline || firstScan ? false : result.lowConfidence,
      isBaseline: isBaseline || firstScan, notes: '', tags: suggestedTags(h.habits.get(day)),
      syncState: driveFolder(this.snapshot.data.settings.drive) ? 'queued' : 'local',
    }
    record.fileName = photoFileName(record, taken)
    this.update((d) => {
      const replaced = isBaseline ? [] : d.scans.filter((s) => s.dayKey === day).map((s) => s.id)
      const jobs = d.uploadJobs.filter((j) => !(replaced.includes(j.scanID) && j.state.kind !== 'done'))
      if (driveFolder(d.settings.drive)) enqueue(jobs, record, false)
      return { ...d, scans: [...d.scans.filter((s) => !replaced.includes(s.id)), record].sort((a, b) => a.capturedAt.localeCompare(b.capturedAt)), uploadJobs: jobs }
    })
    this.afterActivityChange()
    void this.processUploads()
    const dir = this.folderDir()
    if (dir) void writeScan(dir, record, this.snapshot.data, capture.blob, APP_VERSION).catch(() => undefined)
    return record
  }

  /** Done on the result screen: saves notes/tags and uploads the scores file. */
  finalizeScan(id: string, notes: string, tags: string[]) {
    this.update((d) => {
      const scans = d.scans.map((s) => (s.id === id ? { ...s, notes: notes.trim(), tags } : s))
      const jobs = [...d.uploadJobs]
      const scan = scans.find((s) => s.id === id)
      if (scan && driveFolder(d.settings.drive) && !jobs.some((j) => j.scanID === id && j.kind === 'scores')) {
        jobs.push(newJob(scan, 'scores'))
      }
      return { ...d, scans, uploadJobs: jobs }
    })
    void this.processUploads()
    const dir = this.folderDir()
    const scan = this.snapshot.data.scans.find((x) => x.id === id)
    if (dir && scan) void writeScan(dir, scan, this.snapshot.data, undefined, APP_VERSION).catch(() => undefined)
  }

  deleteScan(id: string) {
    this.update((d) => ({ ...d, scans: d.scans.filter((s) => s.id !== id), uploadJobs: d.uploadJobs.filter((j) => j.scanID !== id) }))
    void PhotoStore.remove(id)
    this.afterActivityChange()
  }

  // MARK: Uploads

  uploadCardState(scanID: string): UploadCardState {
    const d = this.snapshot.data
    const folder = driveFolder(d.settings.drive)
    if (!folder) return { kind: 'localOnly' }
    const scan = d.scans.find((s) => s.id === scanID)
    const jobs = d.uploadJobs.filter((j) => j.scanID === scanID)
    const saved = (): UploadCardState => ({ kind: 'saved', fileName: DriveNaming.photoName(new Date(scan!.capturedAt)), path: folder.path })
    if (!jobs.length) return scan?.syncState === 'synced' ? saved() : { kind: 'queued', count: 1 }
    const failed = jobs.find((j) => j.state.kind === 'failed')
    if (failed && failed.state.kind === 'failed') return { kind: 'failed', failure: failed.state.failure }
    if (jobs.every((j) => j.state.kind === 'done') && scan) return saved()
    if (!this.snapshot.online) return { kind: 'queued', count: this.pendingUploadCount() }
    const progress = jobs.reduce((t, j) => t + (j.state.kind === 'done' ? 1 : j.state.kind === 'uploading' ? j.state.progress : 0), 0) / jobs.length
    return { kind: 'uploading', progress }
  }

  pendingUploadCount(): number {
    return new Set(this.snapshot.data.uploadJobs.filter((j) => j.state.kind !== 'done').map((j) => j.scanID)).size
  }

  retryUploads() {
    this.update((d) => ({
      ...d, uploadJobs: d.uploadJobs.map((j) => (j.state.kind === 'failed' ? { ...j, state: { kind: 'pending' }, nextAttemptAt: undefined } : j)),
    }))
    void this.processUploads()
  }

  /** Uploads pending jobs one at a time; transient failures back off, auth/folder problems stop. */
  async processUploads() {
    const d0 = this.snapshot.data
    const folder = driveFolder(d0.settings.drive)
    if (this.processing || !this.snapshot.online || !folder || d0.settings.drive.kind === 'needsReconnect') return
    this.processing = true
    try {
      for (;;) {
        const now = this.now().toISOString()
        const job = this.snapshot.data.uploadJobs.find((j) => j.state.kind === 'pending' && (!j.nextAttemptAt || j.nextAttemptAt <= now))
        if (!job) break
        const scan = this.snapshot.data.scans.find((s) => s.id === job.scanID)
        if (!scan) {
          this.update((d) => ({ ...d, uploadJobs: d.uploadJobs.filter((j) => j.id !== job.id) }))
          continue
        }
        this.setJob(job.id, { kind: 'uploading', progress: 0 }, scan.id, 'uploading')
        try {
          const blob = await this.payload(job, scan)
          const fileID = await this.drive.upload(blob, job.fileName, folder.id, { scanID: scan.id, kind: job.kind },
            (p) => this.setJob(job.id, { kind: 'uploading', progress: p }))
          this.update((d) => {
            const scans = d.scans.map((s) => {
              if (s.id !== scan.id) return s
              const next = { ...s, [job.kind === 'photo' ? 'drivePhotoFileID' : 'driveJSONFileID']: fileID }
              return { ...next, syncState: next.drivePhotoFileID && next.driveJSONFileID ? 'synced' as const : s.syncState }
            })
            return {
              ...d, scans,
              uploadJobs: d.uploadJobs.map((j) => (j.id === job.id ? { ...j, state: { kind: 'done', fileID } } : j)),
              settings: { ...d.settings, lastSyncAt: this.now().toISOString() },
            }
          })
        } catch (e) {
          const failure: UploadFailure = e instanceof DriveError ? e.failure : 'unknown'
          this.handleFailure(job.id, failure)
          if (!isTransient(failure)) break
        }
      }
    } finally {
      this.processing = false
    }
    this.scheduleRetry()
  }

  private async payload(job: UploadJob, scan: ScanRecord): Promise<Blob> {
    if (job.kind === 'photo') {
      const original = await PhotoStore.get(PhotoStore.photoKey(scan.id))
      if (!original) throw new DriveError('unknown')
      const q = this.snapshot.data.settings.uploadQuality
      return q === 'original' ? original : resizeJPEG(original, q === 'high' ? 2048 : 1280, 0.85)
    }
    const h = this.history()
    const baseline = h.baseline
    const json = scanExport(scan, {
      baselineID: baseline?.id, deltaVsYesterday: h.deltaVsPrevious(scan.dayKey),
      deltaVsBaseline: baseline ? scan.score - baseline.score : undefined, habits: h.habits.get(scan.dayKey), appVersion: APP_VERSION,
    })
    return new Blob([JSON.stringify(json, null, 2)], { type: 'application/json' })
  }

  private setJob(id: string, state: UploadJob['state'], scanID?: string, sync?: ScanRecord['syncState']) {
    this.update((d) => ({
      ...d,
      uploadJobs: d.uploadJobs.map((j) => (j.id === id ? { ...j, state } : j)),
      scans: scanID && sync ? d.scans.map((s) => (s.id === scanID ? { ...s, syncState: sync } : s)) : d.scans,
    }))
  }

  private handleFailure(jobID: string, failure: UploadFailure) {
    this.update((d) => {
      let scanID = ''
      const jobs = d.uploadJobs.map((j) => {
        if (j.id !== jobID) return j
        scanID = j.scanID
        if (isTransient(failure) && j.retryCount < BACKOFF_SECONDS.length) {
          const next = new Date(this.now().getTime() + BACKOFF_SECONDS[j.retryCount] * 1000).toISOString()
          return { ...j, retryCount: j.retryCount + 1, nextAttemptAt: next, state: { kind: 'pending' as const } }
        }
        return { ...j, state: { kind: 'failed' as const, failure } }
      })
      const folder = driveFolder(d.settings.drive)
      const drive = failure === 'authExpired' && folder ? { kind: 'needsReconnect' as const, folder } : d.settings.drive
      return {
        ...d, uploadJobs: jobs, settings: { ...d.settings, drive },
        scans: d.scans.map((s) => (s.id === scanID ? { ...s, syncState: isTransient(failure) ? 'queued' : 'failed' } : s)),
      }
    })
  }

  private scheduleRetry() {
    clearTimeout(this.retryTimer)
    const next = this.snapshot.data.uploadJobs
      .filter((j) => j.state.kind === 'pending' && j.nextAttemptAt).map((j) => new Date(j.nextAttemptAt!).getTime()).sort()[0]
    if (next) this.retryTimer = window.setTimeout(() => void this.processUploads(), Math.max(500, next - this.now().getTime()))
  }

  /** Rebuilds history from the JSON files in the connected Drive folder (new browser or device). */
  async restoreFromDrive(): Promise<number> {
    const folder = driveFolder(this.snapshot.data.settings.drive)
    if (!folder) return 0
    const files = await this.drive.listScoreFiles(folder.id)
    const restored: ScanRecord[] = []
    for (const f of files) {
      try {
        const json = JSON.parse(await (await this.drive.download(f.id)).text()) as ScanExport
        const record = recordFromExport(json)
        if (record && !this.snapshot.data.scans.some((s) => s.id === record.id)) restored.push({ ...record, driveJSONFileID: f.id })
      } catch { /* skip unreadable files */ }
    }
    if (restored.length) this.update((d) => ({ ...d, scans: [...d.scans, ...restored].sort((a, b) => a.capturedAt.localeCompare(b.capturedAt)) }))
    return restored.length
  }

  // MARK: Awards & celebrations

  dequeueAward() {
    const [first, ...rest] = this.snapshot.awardQueue
    if (!first) return
    this.set({ awardQueue: rest })
    this.update((d) => ({ ...d, earnedAwards: d.earnedAwards.map((a) => (a.awardID === first ? { ...a, seen: true } : a)) }))
  }

  dismissAllRings() {
    this.set({ showAllRingsClosed: false })
  }

  private afterActivityChange() {
    const d = this.snapshot.data
    const today = this.today()
    const h = historyFor(d)
    const fresh = Awards.evaluate({ history: h, records: d.challengeRecords, today }, d.earnedAwards, this.now())
    if (fresh.length) {
      this.update((x) => ({ ...x, earnedAwards: [...x.earnedAwards, ...fresh] }))
      this.set({ awardQueue: [...this.snapshot.awardQueue, ...fresh.map((a) => a.awardID)] })
    }
    if (allClosed(h.stats(today).rings) && d.settings.lastCelebrationDay !== today) {
      this.updateSettings({ lastCelebrationDay: today })
      this.set({ showAllRingsClosed: true })
    }
  }
}

function newJob(scan: ScanRecord, kind: 'photo' | 'scores'): UploadJob {
  const date = new Date(scan.capturedAt)
  return {
    id: crypto.randomUUID(), scanID: scan.id, kind, retryCount: 0, createdAt: new Date().toISOString(), state: { kind: 'pending' },
    fileName: kind === 'photo' ? DriveNaming.photoName(date) : DriveNaming.scoresName(date),
  }
}

function enqueue(jobs: UploadJob[], scan: ScanRecord, includeScores: boolean) {
  if (!scan.drivePhotoFileID && !jobs.some((j) => j.scanID === scan.id && j.kind === 'photo')) jobs.push(newJob(scan, 'photo'))
  if (includeScores && !scan.driveJSONFileID && !jobs.some((j) => j.scanID === scan.id && j.kind === 'scores')) jobs.push(newJob(scan, 'scores'))
}

const historyCache = new WeakMap<PersistedState, History>()
function historyFor(d: PersistedState): History {
  let h = historyCache.get(d)
  if (!h) {
    h = new History(d.scans, d.habitLogs, d.goals)
    historyCache.set(d, h)
  }
  return h
}

export const store = new AppStore()

// Handy for debugging in the dev server only (stripped from production builds).
if (import.meta.env.DEV) (window as unknown as { __puffymeter: AppStore }).__puffymeter = store

/** Subscribes a component to the store and returns handy derived values. */
export function useApp() {
  const snap = useSyncExternalStore(store.subscribe, store.getSnapshot)
  const d = snap.data
  const today = store.today()
  const history = historyFor(d)
  const todayStats = history.stats(today)
  const correlations = Insights.correlations(history, today)
  return {
    snap, d, settings: d.settings, today, history, todayStats,
    goals: goalsFor(d.goals, today),
    streak: Streaks.current(history.scanDays, today),
    todayLog: history.habits.get(today),
    awardContext: { history, records: d.challengeRecords, today },
    challengeStatuses: Challenges.forMonth(today.slice(0, 7)).map((c) => Challenges.status(c, history, d.challengeRecords, today)),
    correlations,
    dailyInsights: history.scanDays.size >= 7
      ? Insights.daily(correlations, history.scans.filter((s) => !s.isBaseline).slice(-7).map((s) => new Date(s.capturedAt)), d.settings.reminderTime)
      : [],
    lastSeven: history.statsRange(addDays(today, -6), today),
    folder: driveFolder(d.settings.drive),
  }
}

export function awardByID(id: string): AwardDefinition | undefined {
  return ALL_AWARDS.find((a) => a.id === id)
}
