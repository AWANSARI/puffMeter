// Deterministic sample data that reproduces the design mockups (Alex Morgan, Oct 2–8 2026,
// scores 48 44 41 39 36 40 32, zones 38/29/26). Used by demo mode (?demo) and tests.

import type { DayKey } from './dates'
import { IDEAL_QUALITY, type HabitLog, type PersistedState, type SaltLevel, type ScanRecord, type ZoneScores } from './types'

export const SAMPLE_TODAY: DayKey = '2026-10-08'
export const sampleNow = () => new Date(2026, 9, 8, 8, 2, 0)

type Row = [DayKey, number, [number, number, number], number | undefined, number | undefined, SaltLevel | undefined]

const ROWS: Row[] = [
  ['2026-09-09', 50, [56, 47, 45], 6.0, undefined, undefined],
  ['2026-09-10', 47, [53, 44, 42], 7.5, 1.5, 'low'],
  ['2026-09-12', 52, [58, 49, 47], 6.0, 1.0, 'high'],
  ['2026-09-14', 45, [51, 42, 40], 7.5, 2.0, 'low'],
  ['2026-09-15', 49, [55, 46, 44], 6.5, 1.5, 'high'],
  ['2026-09-17', 43, [49, 40, 38], 8.0, 2.0, 'low'],
  ['2026-09-19', 50, [56, 47, 45], 6.0, 1.0, 'high'],
  ['2026-09-21', 44, [50, 41, 39], 7.5, 2.0, 'low'],
  ['2026-09-23', 47, [53, 44, 42], 6.5, 1.5, 'medium'],
  ['2026-09-26', 46, [52, 43, 41], 8.0, 2.5, 'low'],
  ['2026-09-29', 46, [52, 43, 41], 6.0, 1.5, 'high'],
  ['2026-10-02', 48, [54, 45, 43], 6.0, 1.0, 'high'],
  ['2026-10-03', 44, [50, 41, 39], 7.0, 2.0, 'low'],
  ['2026-10-04', 41, [47, 38, 36], 7.5, undefined, 'low'],
  ['2026-10-05', 39, [45, 36, 34], 8.0, 2.0, 'medium'],
  ['2026-10-06', 36, [42, 33, 31], 8.0, undefined, 'low'],
  ['2026-10-07', 40, [48, 36, 31], 6.5, 1.5, 'high'],
  ['2026-10-08', 32, [38, 29, 26], 8.0, 1.5, 'low'],
]

const MINUTES = [2, 58, 5, 1, 9, 0, 3]

export function sampleScans(): ScanRecord[] {
  return ROWS.map(([day, score, [u, c, j]], i) => {
    const [y, m, d] = day.split('-').map(Number)
    const minute = day === SAMPLE_TODAY ? 2 : MINUTES[i % MINUTES.length]
    const hour = minute > 30 ? 7 : 8
    const zones: ZoneScores = { underEyes: u, cheeks: c, jawline: j }
    return {
      id: `sample-${String(i + 1).padStart(2, '0')}`,
      capturedAt: new Date(y, m - 1, d, hour, minute).toISOString(),
      dayKey: day, score, zones,
      raw: { underEyes: 0.3 + u / 1000, cheeks: 0.9 + c / 1000, jawline: 0.8 + j / 1000 },
      quality: IDEAL_QUALITY, lowConfidence: false, isBaseline: i === 0,
      notes: day === SAMPLE_TODAY ? 'Rested well. Same morning light.' : '',
      tags: day === SAMPLE_TODAY ? ['8h sleep', 'Low salt', 'No alcohol'] : [],
      drivePhotoFileID: `drive-photo-${i + 1}`, driveJSONFileID: `drive-json-${i + 1}`, syncState: 'synced',
    }
  })
}

export function sampleHabits(): HabitLog[] {
  // Oct 8 leaves alcohol unlogged so Habits shows 3 / 4 like the Summary mockup.
  return ROWS.map(([day, , , sleep, water, salt]) => ({
    dayKey: day, sleepHours: sleep, waterLiters: water, salt,
    alcohol: day === SAMPLE_TODAY ? undefined : salt === 'high' ? 'one' : 'none',
  }))
}

export function sampleState(): PersistedState {
  const at = (y: number, m: number, d: number) => new Date(y, m - 1, d, 8, 2).toISOString()
  return {
    version: 1,
    scans: sampleScans(),
    habitLogs: sampleHabits(),
    goals: [{ effectiveFrom: '2026-09-09', dePuffMax: 35, scansPerDay: 1, habitsPerDay: 4, waterGoalLiters: 2 }],
    earnedAwards: [
      { awardID: 'first-scan', earnedAt: at(2026, 9, 9), seen: true },
      { awardID: 'habit-starter', earnedAt: at(2026, 9, 12), seen: true },
      { awardID: 'scans-10', earnedAt: at(2026, 10, 2), seen: true },
      { awardID: 'streak-3', earnedAt: at(2026, 10, 4), seen: true },
      { awardID: 'streak-7', earnedAt: at(2026, 10, 8), seen: true },
    ],
    challengeRecords: [{ challengeID: '2026-10-hydration', joinedAt: at(2026, 10, 1) }],
    uploadJobs: [],
    settings: {
      onboardingStep: 'complete',
      profile: { displayName: 'Alex Morgan', email: 'alex.morgan@gmail.com', provider: 'google' },
      drive: { kind: 'connected', folder: { id: 'sample-folder', name: 'PuffyMeter Daily', path: 'My Drive / PuffyMeter Daily' } },
      reminderEnabled: true, reminderTime: { hour: 8, minute: 0 }, uploadQuality: 'high', ghostOverlayEnabled: true,
      theme: 'system', lastSyncAt: sampleNow().toISOString(),
    },
  }
}
