import type { DayKey } from './dates'

export type HabitKind = 'water' | 'sleep' | 'salt' | 'alcohol'
export const HABITS: HabitKind[] = ['water', 'sleep', 'salt', 'alcohol']
export const HABIT_TITLES: Record<HabitKind, string> = { water: 'Water', sleep: 'Sleep', salt: 'Salt', alcohol: 'Alcohol' }

export type SaltLevel = 'low' | 'medium' | 'high'
export const SALT_LEVELS: SaltLevel[] = ['low', 'medium', 'high']
export type AlcoholLevel = 'none' | 'one' | 'twoPlus'
export const ALCOHOL_LEVELS: AlcoholLevel[] = ['none', 'one', 'twoPlus']
export const ALCOHOL_TITLES: Record<AlcoholLevel, string> = { none: 'None', one: '1 drink', twoPlus: '2+ drinks' }
export const capitalize = (s: string) => s.charAt(0).toUpperCase() + s.slice(1)

export interface HabitLog {
  dayKey: DayKey
  waterLiters?: number
  sleepHours?: number
  salt?: SaltLevel
  alcohol?: AlcoholLevel
}

export function isLogged(log: HabitLog | undefined, habit: HabitKind): boolean {
  if (!log) return false
  switch (habit) {
    case 'water': return log.waterLiters != null
    case 'sleep': return log.sleepHours != null
    case 'salt': return log.salt != null
    case 'alcohol': return log.alcohol != null
  }
}

/** Each logged habit counts as one check-in toward the Habits ring. */
export function checkInCount(log: HabitLog | undefined): number {
  return HABITS.filter((h) => isLogged(log, h)).length
}

export function suggestedTags(log: HabitLog | undefined): string[] {
  if (!log) return []
  const tags: string[] = []
  if (log.sleepHours != null) tags.push(`${Number.isInteger(log.sleepHours) ? log.sleepHours : log.sleepHours.toFixed(1)}h sleep`)
  if (log.salt) tags.push(`${capitalize(log.salt)} salt`)
  if (log.alcohol) tags.push(log.alcohol === 'none' ? 'No alcohol' : ALCOHOL_TITLES[log.alcohol])
  return tags
}

export type FaceZone = 'underEyes' | 'cheeks' | 'jawline'
export const ZONES: FaceZone[] = ['underEyes', 'cheeks', 'jawline']
export const ZONE_TITLES: Record<FaceZone, string> = { underEyes: 'Under-eyes', cheeks: 'Cheeks', jawline: 'Jawline' }

export type ZoneScores = Record<FaceZone, number>
/** Size-invariant raw measurements from the face analyzer (normalized by inter-pupil distance). */
export type RawFaceMetrics = Record<FaceZone, number>

export interface ScanQuality {
  lighting: number // 0…1
  yawDeg: number
  rollDeg: number
  pitchDeg: number
  neutrality: number // 0…1
  method: 'mediapipe' | 'fixture'
  manual: boolean
}

export function qualityComposite(q: ScanQuality): number {
  const maxAngle = Math.max(Math.abs(q.yawDeg), Math.abs(q.rollDeg), Math.abs(q.pitchDeg))
  const pose = Math.max(0, 1 - maxAngle / 20)
  return Math.min(1, Math.max(0, q.lighting * 0.4 + q.neutrality * 0.3 + pose * 0.3))
}

export const IDEAL_QUALITY: ScanQuality = {
  lighting: 0.9, yawDeg: 1, rollDeg: 0.5, pitchDeg: 0, neutrality: 0.95, method: 'fixture', manual: false,
}

export type SyncState = 'local' | 'queued' | 'uploading' | 'synced' | 'failed'

export interface ScanRecord {
  id: string
  capturedAt: string // ISO 8601
  dayKey: DayKey
  score: number
  zones: ZoneScores
  raw: RawFaceMetrics
  quality: ScanQuality
  lowConfidence: boolean
  isBaseline: boolean
  notes: string
  tags: string[]
  drivePhotoFileID?: string
  driveJSONFileID?: string
  syncState: SyncState
}

export interface GoalSet {
  effectiveFrom: DayKey
  dePuffMax: number
  scansPerDay: number
  habitsPerDay: number
  waterGoalLiters: number
}

export const GOAL_RANGES = { dePuff: [10, 90], scans: [1, 3], habits: [1, 4] } as const

export function defaultGoals(day: DayKey): GoalSet {
  return { effectiveFrom: day, dePuffMax: 35, scansPerDay: 1, habitsPerDay: 4, waterGoalLiters: 2 }
}

/** Goals apply from their effective day forward; past days keep the goals they had. */
export function goalsFor(goals: GoalSet[], day: DayKey): GoalSet {
  const sorted = [...goals].sort((a, b) => a.effectiveFrom.localeCompare(b.effectiveFrom))
  let match: GoalSet | undefined
  for (const g of sorted) if (g.effectiveFrom <= day) match = g
  return match ?? sorted[0] ?? defaultGoals(day)
}

export interface EarnedAward { awardID: string; earnedAt: string; seen: boolean }
export interface ChallengeProgress { challengeID: string; joinedAt?: string }

export type UploadFailure = 'network' | 'authExpired' | 'folderMissing' | 'quotaExceeded' | 'server' | 'unknown'
export const FAILURE_MESSAGE: Record<UploadFailure, string> = {
  network: "Couldn't reach Google Drive.",
  authExpired: 'Google Drive session expired.',
  folderMissing: 'Folder not found.',
  quotaExceeded: 'Your Google Drive is full.',
  server: 'Google Drive is having trouble right now.',
  unknown: 'Something went wrong.',
}
export const FAILURE_ACTION: Record<UploadFailure, string> = {
  network: 'Retry', authExpired: 'Reconnect', folderMissing: 'Choose Folder', quotaExceeded: 'Retry', server: 'Retry', unknown: 'Retry',
}
export const isTransient = (f: UploadFailure) => f === 'network' || f === 'server'

export type UploadState =
  | { kind: 'pending' }
  | { kind: 'uploading'; progress: number }
  | { kind: 'done'; fileID: string }
  | { kind: 'failed'; failure: UploadFailure }

export interface UploadJob {
  id: string
  scanID: string
  kind: 'photo' | 'scores'
  fileName: string
  state: UploadState
  retryCount: number
  createdAt: string
  nextAttemptAt?: string
}

export interface DriveFolderRef { id: string; name: string; path: string }

export type DriveConnection =
  | { kind: 'notConnected' }
  | { kind: 'skipped' }
  | { kind: 'connected'; folder: DriveFolderRef }
  | { kind: 'needsReconnect'; folder: DriveFolderRef }

export const driveFolder = (d: DriveConnection) =>
  d.kind === 'connected' || d.kind === 'needsReconnect' ? d.folder : undefined

export type OnboardingStep =
  | 'welcome' | 'signIn' | 'driveLimitedAccess' | 'driveFolderPicker' | 'driveConnected' | 'permissions' | 'baselineScan' | 'complete'

export interface UserProfile { displayName: string; email?: string; provider: 'google' | 'local' }

export interface Settings {
  onboardingStep: OnboardingStep
  profile?: UserProfile
  drive: DriveConnection
  reminderEnabled: boolean
  reminderTime: { hour: number; minute: number }
  uploadQuality: 'original' | 'high' | 'compact'
  ghostOverlayEnabled: boolean
  theme: 'system' | 'dark' | 'light'
  lastCelebrationDay?: DayKey
  lastSyncAt?: string
}

export const DEFAULT_SETTINGS: Settings = {
  onboardingStep: 'welcome',
  drive: { kind: 'notConnected' },
  reminderEnabled: true,
  reminderTime: { hour: 8, minute: 0 },
  uploadQuality: 'high',
  ghostOverlayEnabled: true,
  theme: 'system',
}

export interface PersistedState {
  version: 1
  scans: ScanRecord[]
  habitLogs: HabitLog[]
  goals: GoalSet[]
  earnedAwards: EarnedAward[]
  challengeRecords: ChallengeProgress[]
  uploadJobs: UploadJob[]
  settings: Settings
}

export const emptyState = (): PersistedState => ({
  version: 1, scans: [], habitLogs: [], goals: [], earnedAwards: [], challengeRecords: [], uploadJobs: [],
  settings: structuredClone(DEFAULT_SETTINGS),
})
