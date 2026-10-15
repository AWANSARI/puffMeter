// Scoring, rings, streaks and per-day history. A direct port of PuffyKit's Swift domain layer
// so the web and iOS apps produce identical numbers.

import { addDays, dayRange, type DayKey } from './dates'
import {
  checkInCount, goalsFor, qualityComposite, ZONES,
  type FaceZone, type GoalSet, type HabitLog, type RawFaceMetrics, type ScanQuality, type ScanRecord, type ZoneScores,
} from './types'

const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v))

// MARK: Scoring

/**
 * Maps raw, IPD-normalized face metrics to a 0–100 Puffiness Score (lower is better).
 * 30 is roughly the user's typical good day; each personal standard deviation adds 15 points.
 */
export type ZoneReference = Record<FaceZone, { center: number; spread: number }>

export const Scoring = {
  zoneWeights: { underEyes: 0.4, cheeks: 0.3, jawline: 0.3 } as Record<FaceZone, number>,
  typicalScore: 30,
  pointsPerSpread: 15,
  lowConfidenceThreshold: 0.6,
  minimumHistory: 7,
  historyWindow: 30,
  referencePercentile: 0.2,
  minimumSpread: { underEyes: 0.012, cheeks: 0.015, jawline: 0.015 } as Record<FaceZone, number>,

  reference(baseline: RawFaceMetrics, history: RawFaceMetrics[]): ZoneReference {
    const recent = history.slice(-Scoring.historyWindow)
    const out = {} as Record<FaceZone, { center: number; spread: number }>
    for (const zone of ZONES) {
      const floor = Scoring.minimumSpread[zone]
      if (recent.length < Scoring.minimumHistory) {
        out[zone] = { center: baseline[zone], spread: floor }
      } else {
        const values = recent.map((r) => r[zone])
        out[zone] = { center: percentile(values, Scoring.referencePercentile), spread: Math.max(stdDev(values), floor) }
      }
    }
    return out
  },

  zoneScore(raw: number, ref: { center: number; spread: number }): number {
    const z = (raw - ref.center) / ref.spread
    return clamp(Math.round(Scoring.typicalScore + Scoring.pointsPerSpread * z), 0, 100)
  },

  overall(zones: ZoneScores): number {
    const total = ZONES.reduce((sum, z) => sum + zones[z] * Scoring.zoneWeights[z], 0)
    return clamp(Math.round(total), 0, 100)
  },

  score(raw: RawFaceMetrics, quality: ScanQuality, reference: ZoneReference): { zones: ZoneScores; overall: number; lowConfidence: boolean } {
    const zones = {} as ZoneScores
    for (const z of ZONES) zones[z] = Scoring.zoneScore(raw[z], reference[z])
    return { zones, overall: Scoring.overall(zones), lowConfidence: qualityComposite(quality) < Scoring.lowConfidenceThreshold }
  },
}

export function percentile(values: number[], p: number): number {
  if (!values.length) return 0
  const sorted = [...values].sort((a, b) => a - b)
  const pos = p * (sorted.length - 1)
  const lo = Math.floor(pos)
  const hi = Math.ceil(pos)
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo)
}

export function stdDev(values: number[]): number {
  if (values.length < 2) return 0
  const mean = values.reduce((a, b) => a + b, 0) / values.length
  return Math.sqrt(values.reduce((a, v) => a + (v - mean) ** 2, 0) / (values.length - 1))
}

// MARK: Rings

export interface RingProgress { dePuff: number; scan: number; habits: number }
export const ZERO_RINGS: RingProgress = { dePuff: 0, scan: 0, habits: 0 }
export const allClosed = (p: RingProgress) => p.dePuff >= 1 && p.scan >= 1 && p.habits >= 1
const closedCount = (p: RingProgress) => [p.dePuff, p.scan, p.habits].filter((v) => v >= 1).length

export const RingMath = {
  /** (100 − score) / (100 − goal): score 32 with goal 35 → 1.046 (closed with overlap). */
  dePuff(score: number | undefined, goal: number): number {
    if (score == null) return 0
    return Math.max(0, (100 - score) / (100 - clamp(goal, 0, 99)))
  },
  ratio(count: number, goal: number): number {
    return count / Math.max(goal, 1)
  },
  caption(stats: DayStats): string {
    const p = stats.rings
    if (allClosed(p)) return 'All three rings closed today.'
    if (stats.scanCount === 0 && stats.habitCount === 0) return "Start with today's scan."
    if (closedCount(p) === 2) {
      if (p.scan < 1) return 'Scan to close your Scan ring.'
      if (p.habits < 1) {
        const remaining = stats.goals.habitsPerDay - stats.habitCount
        return remaining === 1
          ? 'One more habit check-in to close all three rings.'
          : `${remaining} more habit check-ins to close all three rings.`
      }
      return `Your De-Puff ring closes at ${stats.goals.dePuffMax} or lower.`
    }
    if (p.scan < 1) return "Start with today's scan."
    if (p.habits < 1) return 'Log your habits to fill the Habits ring.'
    return `Your De-Puff ring closes at ${stats.goals.dePuffMax} or lower.`
  },
}

export interface DayStats {
  day: DayKey
  goals: GoalSet
  /** The scan that counts for the day (retakes replace it, so the latest one). */
  primaryScan?: ScanRecord
  scanCount: number
  habits?: HabitLog
  score?: number
  habitCount: number
  rings: RingProgress
}

// MARK: History

export class History {
  readonly scans: ScanRecord[]
  readonly habits: Map<DayKey, HabitLog>
  readonly goals: GoalSet[]
  private readonly byDay: Map<DayKey, ScanRecord[]>

  constructor(scans: ScanRecord[], habitLogs: HabitLog[], goals: GoalSet[]) {
    this.scans = [...scans].sort((a, b) => a.capturedAt.localeCompare(b.capturedAt))
    this.habits = new Map(habitLogs.map((h) => [h.dayKey, h]))
    this.goals = goals
    this.byDay = new Map()
    for (const s of this.scans) {
      const list = this.byDay.get(s.dayKey) ?? []
      list.push(s)
      this.byDay.set(s.dayKey, list)
    }
  }

  get scanDays(): Set<DayKey> {
    return new Set(this.byDay.keys())
  }

  get baseline(): ScanRecord | undefined {
    return this.scans.find((s) => s.isBaseline) ?? this.scans[0]
  }

  scansOn(day: DayKey): ScanRecord[] {
    return this.byDay.get(day) ?? []
  }

  stats(day: DayKey): DayStats {
    const dayScans = this.scansOn(day)
    const goals = goalsFor(this.goals, day)
    const primaryScan = dayScans[dayScans.length - 1]
    const habits = this.habits.get(day)
    const habitCount = checkInCount(habits)
    return {
      day, goals, primaryScan, scanCount: dayScans.length, habits, score: primaryScan?.score, habitCount,
      rings: {
        dePuff: RingMath.dePuff(primaryScan?.score, goals.dePuffMax),
        scan: RingMath.ratio(dayScans.length, goals.scansPerDay),
        habits: RingMath.ratio(habitCount, goals.habitsPerDay),
      },
    }
  }

  statsRange(start: DayKey, end: DayKey): DayStats[] {
    return dayRange(start, end).map((d) => this.stats(d))
  }

  previousScan(before: DayKey): ScanRecord | undefined {
    let found: ScanRecord | undefined
    for (const s of this.scans) if (s.dayKey < before) found = s
    return found
  }

  deltaVsPrevious(day: DayKey): number | undefined {
    const today = this.stats(day).score
    const prev = this.previousScan(day)?.score
    return today == null || prev == null ? undefined : today - prev
  }

  zoneDeltaVsPrevious(day: DayKey): ZoneScores | undefined {
    const today = this.stats(day).primaryScan?.zones
    const prev = this.previousScan(day)?.zones
    if (!today || !prev) return undefined
    return { underEyes: today.underEyes - prev.underEyes, cheeks: today.cheeks - prev.cheeks, jawline: today.jawline - prev.jawline }
  }

  average(start: DayKey, end: DayKey): number | undefined {
    const values = this.statsRange(start, end).map((s) => s.score).filter((v): v is number => v != null)
    return values.length ? values.reduce((a, b) => a + b, 0) / values.length : undefined
  }
}

// MARK: Streaks

export const Streaks = {
  /** Consecutive scan days ending today or yesterday (not broken until a full day passes). */
  current(scanDays: Set<DayKey>, today: DayKey): number {
    let cursor = scanDays.has(today) ? today : addDays(today, -1)
    let count = 0
    while (scanDays.has(cursor)) {
      count++
      cursor = addDays(cursor, -1)
    }
    return count
  },
  longestRun(days: Set<DayKey>): number {
    let best = 0
    for (const day of days) {
      if (days.has(addDays(day, -1))) continue
      let length = 1
      let next = addDays(day, 1)
      while (days.has(next)) {
        length++
        next = addDays(next, 1)
      }
      best = Math.max(best, length)
    }
    return best
  },
}
