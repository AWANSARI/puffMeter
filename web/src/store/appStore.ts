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
import { GoogleAuth } from '../services/googleAuth'
import { PhotoStore, resizeJPEG } from '../services/photoStore'
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

export interface AppSnapshot {
  data: PersistedState
  loaded: boolean
  online: boolean
  awardQueue: string[]
  showAllRingsClosed: boolean
  photosRevision: number
  demo: boolean
}

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
    this.snapshot = { data: emptyState(), loaded: false, online: navigator.onLine, awardQueue: [], showAllRingsClosed: false, photosRevision: 0, demo }
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
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(this.snapshot.data))
    } catch { /* storage full or blocked */ }
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
    this.set({ data, loaded: true })
    if (this.snapshot.demo) await this.seedDemoPhotos()
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
    this.updateSettings({ profile: { displayName: 'You', provider: 'local' }, drive: { kind: 'skipped' }, onboardingStep: 'permissions' })
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

  async reconnectDrive() {
    await GoogleAuth.requestDriveAccess(this.snapshot.data.settings.profile?.email)
    const folder = driveFolder(this.snapshot.data.settings.drive)
    if (folder) this.updateSettings({ drive: { kind: 'connected', folder } })
    this.retryUploads()
  }

  async signOut(deleteLocalData: boolean) {
    await GoogleAuth.signOut()
    if (deleteLocalData) await this.deleteAllData()
    else this.updateSettings({ profile: undefined, onboardingStep: 'signIn' })
  }

  async deleteAllData() {
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
    const day = this.snapshot.demo ? this.today() : dayKeyOf(capture.capturedAt)
    const capturedAt = this.snapshot.demo ? this.now() : capture.capturedAt
    const firstScan = this.snapshot.data.scans.length === 0
    const record: ScanRecord = {
      id, capturedAt: capturedAt.toISOString(), dayKey: day, score: result.overall, zones: result.zones, raw,
      quality: capture.quality, lowConfidence: isBaseline || firstScan ? false : result.lowConfidence,
      isBaseline: isBaseline || firstScan, notes: '', tags: suggestedTags(h.habits.get(day)),
      syncState: driveFolder(this.snapshot.data.settings.drive) ? 'queued' : 'local',
    }
    this.update((d) => {
      const replaced = isBaseline ? [] : d.scans.filter((s) => s.dayKey === day).map((s) => s.id)
      const jobs = d.uploadJobs.filter((j) => !(replaced.includes(j.scanID) && j.state.kind !== 'done'))
      if (driveFolder(d.settings.drive)) enqueue(jobs, record, false)
      return { ...d, scans: [...d.scans.filter((s) => !replaced.includes(s.id)), record].sort((a, b) => a.capturedAt.localeCompare(b.capturedAt)), uploadJobs: jobs }
    })
    this.afterActivityChange()
    void this.processUploads()
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
