import { describe, expect, it } from 'vitest'
import { addDays } from './dates'
import { History, RingMath, Scoring, Streaks } from './engine'
import { DriveNaming, toCSV, CSV_HEADER } from './export'
import { ALL_AWARDS, Awards, Challenges, CHALLENGES, Insights, trendSeries } from './progress'
import { SAMPLE_TODAY, sampleHabits, sampleNow, sampleScans, sampleState } from './sampleData'

const history = () => new History(sampleScans(), sampleHabits(), sampleState().goals)
const today = SAMPLE_TODAY

describe('scoring (parity with PuffyKit)', () => {
  it('mockup zones 38/29/26 give 32', () => {
    expect(Scoring.overall({ underEyes: 38, cheeks: 29, jawline: 26 })).toBe(32)
  })
  it('maps raw values around the personal reference', () => {
    const ref = { center: 1, spread: 0.02 }
    expect(Scoring.zoneScore(1, ref)).toBe(30)
    expect(Scoring.zoneScore(1.02, ref)).toBe(45)
    expect(Scoring.zoneScore(0, ref)).toBe(0)
    expect(Scoring.zoneScore(9, ref)).toBe(100)
  })
  it('baseline scores 30 and low quality is flagged', () => {
    const raw = { underEyes: 0.3, cheeks: 0.9, jawline: 0.8 }
    const ref = Scoring.reference(raw, [])
    const low = { lighting: 0.2, yawDeg: 15, rollDeg: 2, pitchDeg: 0, neutrality: 0.4, method: 'mediapipe' as const, manual: false }
    expect(Scoring.score(raw, low, ref).lowConfidence).toBe(true)
    expect(Scoring.score(raw, { ...low, lighting: 0.9, yawDeg: 1, neutrality: 0.95 }, ref).overall).toBe(30)
  })
})

describe('rings, streaks, trends', () => {
  it('De-Puff overflow', () => {
    expect(RingMath.dePuff(32, 35)).toBeCloseTo(68 / 65)
    expect(RingMath.dePuff(undefined, 35)).toBe(0)
  })
  it('today matches the Summary mockup', () => {
    const h = history()
    const s = h.stats(today)
    expect(s.score).toBe(32)
    expect(s.habitCount).toBe(3)
    expect(RingMath.caption(s)).toBe('One more habit check-in to close all three rings.')
    expect(h.deltaVsPrevious(today)).toBe(-8)
    expect(h.zoneDeltaVsPrevious(today)).toEqual({ underEyes: -10, cheeks: -7, jawline: -5 })
  })
  it('streak rules', () => {
    const days = history().scanDays
    expect(Streaks.current(days, today)).toBe(7)
    expect(Streaks.current(days, addDays(today, 1))).toBe(7)
    expect(Streaks.current(days, addDays(today, 2))).toBe(0)
    expect(addDays('2026-12-31', 1)).toBe('2027-01-01')
  })
  it('weekly trend: 40 average, 6 better than last week', () => {
    const w = trendSeries('W', history(), today)
    expect(w.points.map((p) => p.value)).toEqual([48, 44, 41, 39, 36, 40, 32])
    expect(Math.round(w.average!)).toBe(40)
    expect(w.delta).toBe(-6)
  })
})

describe('challenges, awards, insights, export', () => {
  it('pace text', () => {
    expect(Challenges.paceText(8, 20, 8, 31)).toBe("You're on pace")
    expect(Challenges.paceText(2, 20, 15, 30)).toBe('8 more days to stay on pace')
  })
  it('hydration needs joining', () => {
    const c = CHALLENGES.find((x) => x.id === '2026-10-hydration')!
    expect(Challenges.status(c, history(), [], today).joined).toBe(false)
    expect(Challenges.status(c, history(), sampleState().challengeRecords, today).joined).toBe(true)
  })
  it('awards are idempotent and 30 scans shows 18/30', () => {
    const ctx = { history: history(), records: sampleState().challengeRecords, today }
    const first = Awards.evaluate(ctx, [], sampleNow())
    expect(first.map((a) => a.awardID)).toContain('streak-7')
    expect(Awards.evaluate(ctx, first, sampleNow())).toEqual([])
    expect(Awards.progress(ALL_AWARDS.find((a) => a.id === 'scans-30')!, ctx).current).toBe(18)
  })
  it('insights need enough data', () => {
    const c = Insights.correlations(history(), today)
    expect(c.find((x) => x.factor === 'sleep')!.strength).not.toBe('insufficient')
    expect(c.find((x) => x.factor === 'cycle')!.strength).toBe('insufficient')
  })
  it('drive file names and CSV', () => {
    expect(DriveNaming.photoName(sampleNow())).toBe('2026-10-08_0802.jpg')
    const csv = toCSV(history())
    expect(csv.startsWith(CSV_HEADER)).toBe(true)
    expect(csv.trim().split('\n')).toHaveLength(sampleScans().length + 1)
  })
})
