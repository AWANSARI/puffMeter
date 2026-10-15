// Challenges, awards, insights and trend aggregation.

import { addDays, addMonths, daysInMonth, fmt, monthFirstDay, monthLastDay, monthOf, parseDay, type DayKey, type MonthKey } from './dates'
import { allClosed, History, Streaks } from './engine'
import type { ChallengeProgress, EarnedAward, HabitKind } from './types'

// MARK: Challenges

export interface ChallengeDefinition {
  id: string
  month: MonthKey
  title: string
  description: string
  kind: 'scanDays' | 'habitDays' | 'allRingsDays'
  habit?: HabitKind
  target: number
  requiresJoin: boolean
  rewardAwardID?: string
  rewardText?: string
  icon: 'sunrise' | 'droplet' | 'moon' | 'rings'
  accent: 'dePuff' | 'scan' | 'habits'
}

/** Monthly challenges. New months can be added here without other code changes. */
export const CHALLENGES: ChallengeDefinition[] = [
  { id: '2026-10-morning-momentum', month: '2026-10', title: 'Morning momentum', kind: 'scanDays', target: 20, requiresJoin: false,
    description: 'Scan on 20 different mornings this month. Consistency earns the badge.', rewardAwardID: 'challenge-2026-10-star', icon: 'sunrise', accent: 'dePuff' },
  { id: '2026-10-hydration', month: '2026-10', title: 'Hydration check-in', kind: 'habitDays', habit: 'water', target: 15, requiresJoin: true,
    description: 'Log your water on 15 days. No perfect amount required, just a moment of awareness.', rewardAwardID: 'challenge-2026-10-water',
    rewardText: 'Earn the October Water badge', icon: 'droplet', accent: 'habits' },
  { id: '2026-11-wind-down', month: '2026-11', title: 'A little wind-down', kind: 'habitDays', habit: 'sleep', target: 15, requiresJoin: true,
    description: 'Log your sleep on 15 nights this month. Rest shows up in the mirror.', rewardAwardID: 'challenge-2026-11-sleep',
    rewardText: 'Earn the November Rest badge', icon: 'moon', accent: 'habits' },
  { id: '2026-11-morning-momentum', month: '2026-11', title: 'Morning momentum', kind: 'scanDays', target: 20, requiresJoin: false,
    description: 'Scan on 20 different mornings this month. Consistency earns the badge.', rewardAwardID: 'challenge-2026-11-star', icon: 'sunrise', accent: 'dePuff' },
  { id: '2026-12-rings', month: '2026-12', title: 'Ring season', kind: 'allRingsDays', target: 10, requiresJoin: true,
    description: 'Close all three rings on 10 days this month.', rewardAwardID: 'challenge-2026-12-rings',
    rewardText: 'Earn the December Rings badge', icon: 'rings', accent: 'scan' },
]

export interface ChallengeStatus {
  definition: ChallengeDefinition
  progress: number
  joined: boolean
  paceText: string
  daysLeft: number
  fraction: number
  complete: boolean
}

export const Challenges = {
  forMonth(month: MonthKey): ChallengeDefinition[] {
    return CHALLENGES.filter((c) => c.month === month)
  },
  progress(c: ChallengeDefinition, history: History): number {
    return history.statsRange(monthFirstDay(c.month), monthLastDay(c.month)).filter((s) => {
      switch (c.kind) {
        case 'scanDays': return s.scanCount > 0
        case 'habitDays': return c.habit ? (c.habit === 'water' ? s.habits?.waterLiters != null
          : c.habit === 'sleep' ? s.habits?.sleepHours != null
          : c.habit === 'salt' ? s.habits?.salt != null : s.habits?.alcohol != null) : false
        case 'allRingsDays': return allClosed(s.rings)
      }
    }).length
  },
  status(c: ChallengeDefinition, history: History, records: ChallengeProgress[], today: DayKey): ChallengeStatus {
    const progress = Challenges.progress(c, history)
    const joined = !c.requiresJoin || records.some((r) => r.challengeID === c.id && r.joinedAt)
    const total = daysInMonth(c.month)
    const dayOfMonth = monthOf(today) === c.month ? parseDay(today).d : (c.month < monthOf(today) ? total : 0)
    return {
      definition: c, progress, joined,
      paceText: Challenges.paceText(progress, c.target, dayOfMonth, total),
      daysLeft: Math.max(0, total - dayOfMonth),
      fraction: Math.min(1, progress / Math.max(c.target, 1)),
      complete: progress >= c.target,
    }
  },
  /** "You're on pace" when progress/target ≥ dayOfMonth/daysInMonth. */
  paceText(progress: number, target: number, dayOfMonth: number, total: number): string {
    if (progress >= target) return 'Complete'
    const expected = Math.floor((target * dayOfMonth) / Math.max(total, 1))
    if (progress >= expected) return "You're on pace"
    return `${fmt.plural(expected - progress, 'more day')} to stay on pace`
  },
}

// MARK: Awards

export type BadgeShape = 'coin' | 'hexagon' | 'shield' | 'star'
export type BadgeTint = 'pink' | 'lime' | 'cyan' | 'silver' | 'gold' | 'indigo'
export type BadgeIcon = 'camera' | 'flame' | 'droplet' | 'rings' | 'moon' | 'sparkles' | 'star'

export interface AwardDefinition {
  id: string
  title: string
  category: 'streaks' | 'habits' | 'challenges' | 'milestones'
  requirement: string
  celebration: string
  tagline: string
  metric:
    | { kind: 'totalScans' } | { kind: 'longestStreak' } | { kind: 'habitDays'; habit?: HabitKind }
    | { kind: 'restedDays'; minHours: number } | { kind: 'perfectWeek' } | { kind: 'personalBest'; minScans: number }
    | { kind: 'challenge'; id: string }
  target: number
  unit: string
  badge: { shape: BadgeShape; tint: BadgeTint; icon?: BadgeIcon; label?: string }
}

const streak = (days: number, tint: BadgeTint, tagline: string): AwardDefinition => ({
  id: `streak-${days}`, title: `${days}-day streak`, category: 'streaks', requirement: `Scan ${days} days in a row`,
  celebration: `You scanned for ${days} days in a row. Here's to the routine you're building.`, tagline,
  metric: { kind: 'longestStreak' }, target: days, unit: 'days', badge: { shape: 'coin', tint, icon: 'flame' },
})
const scans = (count: number, tint: BadgeTint): AwardDefinition => ({
  id: `scans-${count}`, title: `${count} scans`, category: 'milestones', requirement: `Complete ${count} scans`,
  celebration: `${count} scans and counting.`, tagline: 'Consistency, counted.', metric: { kind: 'totalScans' },
  target: count, unit: 'scans', badge: { shape: 'shield', tint, label: String(count) },
})

export const STANDARD_AWARDS: AwardDefinition[] = [
  { id: 'first-scan', title: 'First scan', category: 'milestones', requirement: 'Take your first scan',
    celebration: 'Your first scan is in. Every routine starts somewhere.', tagline: 'Day one.',
    metric: { kind: 'totalScans' }, target: 1, unit: 'scan', badge: { shape: 'hexagon', tint: 'lime', icon: 'camera' } },
  streak(3, 'silver', 'Three in a row.'),
  streak(7, 'pink', 'A week of showing up.'),
  streak(30, 'gold', 'A month of mornings.'),
  streak(100, 'indigo', 'One hundred mornings.'),
  streak(365, 'gold', 'A whole year.'),
  scans(10, 'silver'), scans(30, 'lime'), scans(100, 'gold'),
  { id: 'perfect-week', title: 'Perfect week', category: 'streaks', requirement: 'Close all rings for 7 days',
    celebration: 'You closed all three rings seven days in a row.', tagline: 'Seven for seven.',
    metric: { kind: 'perfectWeek' }, target: 7, unit: 'days', badge: { shape: 'coin', tint: 'silver', icon: 'rings' } },
  { id: 'habit-starter', title: 'Habit starter', category: 'habits', requirement: 'Log your first habit',
    celebration: 'You logged your first habit. Small check-ins add up.', tagline: 'It starts here.',
    metric: { kind: 'habitDays' }, target: 1, unit: 'day', badge: { shape: 'coin', tint: 'cyan', icon: 'droplet' } },
  { id: 'hydration-hero', title: 'Hydration hero', category: 'habits', requirement: 'Log water on 30 days',
    celebration: 'Thirty days of water check-ins.', tagline: 'Well watered.',
    metric: { kind: 'habitDays', habit: 'water' }, target: 30, unit: 'days', badge: { shape: 'shield', tint: 'cyan', icon: 'droplet' } },
  { id: 'rested', title: 'Rested', category: 'habits', requirement: 'Log 7+ hours of sleep on 14 days',
    celebration: 'Fourteen well-rested nights logged.', tagline: 'Rest shows.',
    metric: { kind: 'restedDays', minHours: 7 }, target: 14, unit: 'nights', badge: { shape: 'coin', tint: 'indigo', icon: 'moon' } },
  { id: 'personal-best', title: 'Personal best', category: 'milestones', requirement: 'Reach your lowest score after 7+ scans',
    celebration: 'Your lowest score yet.', tagline: 'New low, in the best way.',
    metric: { kind: 'personalBest', minScans: 8 }, target: 1, unit: '', badge: { shape: 'star', tint: 'pink', icon: 'sparkles' } },
]

export function challengeAward(c: ChallengeDefinition): AwardDefinition | undefined {
  if (!c.rewardAwardID) return undefined
  const month = fmt.monthName(c.month)
  const [title, badge]: [string, AwardDefinition['badge']] =
    c.kind === 'scanDays' ? [`${month} star`, { shape: 'star', tint: 'silver' }]
    : c.kind === 'habitDays' ? [`${month} ${c.habit === 'sleep' ? 'rest' : 'water'}`,
      { shape: 'coin', tint: c.habit === 'sleep' ? 'indigo' : 'cyan', icon: c.habit === 'sleep' ? 'moon' : 'droplet' }]
    : [`${month} rings`, { shape: 'coin', tint: 'lime', icon: 'rings' }]
  return {
    id: c.rewardAwardID, title, category: 'challenges', requirement: c.description,
    celebration: `You completed ${c.title} for ${month}.`, tagline: 'Challenge complete.',
    metric: { kind: 'challenge', id: c.id }, target: c.target, unit: c.kind === 'scanDays' ? 'mornings' : 'days', badge,
  }
}

export const ALL_AWARDS: AwardDefinition[] = [
  ...STANDARD_AWARDS,
  ...CHALLENGES.map(challengeAward).filter((a): a is AwardDefinition => !!a),
]

export interface AwardContext { history: History; records: ChallengeProgress[]; today: DayKey }

export const Awards = {
  progress(award: AwardDefinition, ctx: AwardContext): { current: number; target: number; fraction: number } {
    const h = ctx.history
    let current = 0
    const m = award.metric
    switch (m.kind) {
      case 'totalScans': current = h.scanDays.size; break
      case 'longestStreak': current = Streaks.longestRun(h.scanDays); break
      case 'habitDays':
        current = [...h.habits.values()].filter((log) => {
          if (!m.habit) return !!(log.waterLiters != null || log.sleepHours != null || log.salt || log.alcohol)
          return m.habit === 'water' ? log.waterLiters != null : m.habit === 'sleep' ? log.sleepHours != null
            : m.habit === 'salt' ? !!log.salt : !!log.alcohol
        }).length
        break
      case 'restedDays': current = [...h.habits.values()].filter((l) => (l.sleepHours ?? 0) >= m.minHours).length; break
      case 'perfectWeek': current = Streaks.longestRun(new Set([...h.scanDays].filter((d) => allClosed(h.stats(d).rings)))); break
      case 'personalBest': {
        const scored = h.scans.filter((s) => !s.isBaseline)
        if (scored.length >= m.minScans) {
          const latest = scored[scored.length - 1]
          const prevBest = Math.min(...scored.slice(0, -1).map((s) => s.score))
          current = latest.score < prevBest ? 1 : 0
        }
        break
      }
      case 'challenge': {
        const c = CHALLENGES.find((x) => x.id === m.id)
        if (c) {
          const status = Challenges.status(c, h, ctx.records, ctx.today)
          current = status.joined ? status.progress : 0
        }
        break
      }
    }
    return { current, target: award.target, fraction: Math.min(1, current / Math.max(award.target, 1)) }
  },
  /** Newly earned awards. Idempotent: anything already earned is never returned again. */
  evaluate(ctx: AwardContext, earned: EarnedAward[], now: Date): EarnedAward[] {
    const have = new Set(earned.map((e) => e.awardID))
    return ALL_AWARDS.filter((a) => !have.has(a.id) && Awards.progress(a, ctx).current >= a.target)
      .map((a) => ({ awardID: a.id, earnedAt: now.toISOString(), seen: false }))
  },
}

// MARK: Insights

export type Factor = 'sleep' | 'water' | 'salt' | 'cycle'
export const FACTORS: Factor[] = ['sleep', 'water', 'salt', 'cycle']
export type Strength = 'insufficient' | 'none' | 'small' | 'moderate' | 'strong'
const STRENGTH_LABEL: Record<Strength, string> = {
  insufficient: 'No conclusion yet', none: 'No clear difference', small: 'Small association',
  moderate: 'Moderate association', strong: 'Strong association',
}

export interface Correlation {
  factor: Factor
  delta?: number
  pairedDays: number
  strength: Strength
  explanation: string
  deltaText?: string
  footnote: string
}

export const Insights = {
  minPerGroup: 5,
  minPaired: 14,
  windowDays: 30,

  correlations(history: History, today: DayKey): Correlation[] {
    const start = addDays(today, -(Insights.windowDays - 1))
    const days = history.statsRange(start, today).filter((s) => s.primaryScan && !s.primaryScan.lowConfidence)
    return FACTORS.map((factor) => {
      let classify: (s: (typeof days)[number]) => boolean | undefined
      let explanation: string
      switch (factor) {
        case 'sleep':
          classify = (s) => (s.habits?.sleepHours == null ? undefined : s.habits.sleepHours >= 7)
          explanation = 'Average score after 7+ hours vs less than 7 hours.'
          break
        case 'water':
          classify = (s) => (s.habits?.waterLiters == null ? undefined : s.habits.waterLiters >= s.goals.waterGoalLiters)
          explanation = 'Average score on days with 2 L logged vs less.'
          break
        case 'salt':
          classify = (s) => (s.habits?.salt === 'high' ? true : s.habits?.salt === 'low' ? false : undefined)
          explanation = 'Average score after “high salt” evenings vs “low salt”.'
          break
        case 'cycle':
          classify = () => undefined
          explanation = 'Cycle tracking needs Apple Health, which is only in the iPhone app.'
          break
      }
      const a: number[] = []
      const b: number[] = []
      for (const s of days) {
        const c = classify(s)
        if (c === undefined || s.score == null) continue
        ;(c ? a : b).push(s.score)
      }
      const paired = a.length + b.length
      if (a.length < Insights.minPerGroup || b.length < Insights.minPerGroup || paired < Insights.minPaired) {
        return { factor, pairedDays: paired, strength: 'insufficient' as Strength,
          explanation: factor === 'cycle' ? explanation : 'More data needed to compare. Keep logging.',
          footnote: `${paired} paired days · No conclusion yet` }
      }
      const mean = (v: number[]) => v.reduce((x, y) => x + y, 0) / v.length
      const delta = mean(a) - mean(b)
      const mag = Math.abs(delta)
      const strength: Strength = mag < 2 ? 'none' : mag < 4 ? 'small' : mag <= 8 ? (paired >= 20 ? 'moderate' : 'small') : (paired >= 20 ? 'strong' : 'moderate')
      const r = Math.round(delta)
      const deltaText = r === 0 ? '±0 points' : r < 0 ? `−${-r} points` : `+${r} points`
      return { factor, delta, pairedDays: paired, strength, explanation, deltaText,
        footnote: `${paired} paired days · ${factor === 'salt' ? 'Personal tags' : STRENGTH_LABEL[strength]}` }
    })
  },

  daily(correlations: Correlation[], recentScanTimes: Date[], reminder: { hour: number; minute: number }) {
    const out: { id: string; icon?: Factor; title: string; body: string; footnote?: string }[] = []
    const best = correlations.filter((c) => c.strength !== 'insufficient' && c.strength !== 'none' && (c.delta ?? 0) < 0)
      .sort((x, y) => (x.delta ?? 0) - (y.delta ?? 0))[0]
    if (best) {
      const titles: Record<Factor, [string, string]> = {
        sleep: ['A well-rested pattern', 'Your scores tended to be lower after 7+ hours of sleep over the last month.'],
        water: ['A hydration pattern', 'Your scores tended to be lower on days you logged your water goal.'],
        salt: ['A lighter-evening pattern', 'Your scores tended to be lower after high-salt evenings.'],
        cycle: ['A cycle pattern', 'Your scores shifted around certain cycle days.'],
      }
      out.push({ id: `c-${best.factor}`, icon: best.factor, title: titles[best.factor][0], body: titles[best.factor][1],
        footnote: 'Personal association · Not proof of cause' })
    }
    if (recentScanTimes.length >= 7) {
      const target = reminder.hour * 60 + reminder.minute
      const consistent = recentScanTimes.slice(-7).every((d) => Math.abs(d.getHours() * 60 + d.getMinutes() - target) <= 15)
      out.push(consistent
        ? { id: 'consistency', title: 'Same light. Clearer comparisons.',
            body: `You've scanned within 15 minutes of ${fmt.reminder(reminder)} all week. Keep your lighting consistent, too.` }
        : { id: 'consistency', title: 'Same time, clearer trends.', body: 'Try scanning at the same time each day for clearer comparisons.' })
    }
    return out.slice(0, 2)
  },
}

// MARK: Trends

export type TrendRange = 'D' | 'W' | 'M' | '6M' | 'Y'
export const TREND_RANGES: TrendRange[] = ['D', 'W', 'M', '6M', 'Y']
export const RANGE_LABEL: Record<TrendRange, [string, string]> = {
  D: ['today', 'yesterday'], W: ['weekly average', 'previous week'], M: ['monthly average', 'previous month'],
  '6M': ['6-month average', 'previous 6 months'], Y: ['yearly average', 'previous year'],
}

export interface TrendPoint { id: string; label: string; start: DayKey; end: DayKey; value?: number; current: boolean }
export interface TrendSeries { points: TrendPoint[]; start: DayKey; end: DayKey; average?: number; previousAverage?: number; delta?: number }

export function trendSeries(range: TrendRange, history: History, today: DayKey, offset = 0): TrendSeries {
  let points: TrendPoint[]
  let prevStart: DayKey
  let prevEnd: DayKey
  if (range === 'D' || range === 'W' || range === 'M') {
    const span = range === 'M' ? 30 : 7
    const end = addDays(today, span * offset)
    const start = addDays(end, -(span - 1))
    points = history.statsRange(start, end).map((s) => ({
      id: s.day, label: range === 'M' ? String(parseDay(s.day).d) : fmt.weekdayInitial(s.day),
      start: s.day, end: s.day, value: s.score, current: s.day === end,
    }))
    prevStart = addDays(start, -span)
    prevEnd = addDays(start, -1)
  } else if (range === '6M') {
    const end = addDays(today, 182 * offset)
    points = Array.from({ length: 26 }, (_, i) => {
      const weeksAgo = 25 - i
      const weekEnd = addDays(end, -7 * weeksAgo)
      const weekStart = addDays(weekEnd, -6)
      return { id: weekStart, label: fmt.shortDay(weekStart), start: weekStart, end: weekEnd,
        value: history.average(weekStart, weekEnd), current: weeksAgo === 0 }
    })
    prevStart = addDays(points[0].start, -182)
    prevEnd = addDays(points[0].start, -1)
  } else {
    const endMonth = addMonths(monthOf(today), 12 * offset)
    points = Array.from({ length: 12 }, (_, i) => {
      const month = addMonths(endMonth, i - 11)
      return { id: month, label: new Date(`${month}-15T12:00:00`).toLocaleDateString('en-US', { month: 'narrow' }),
        start: monthFirstDay(month), end: monthLastDay(month),
        value: history.average(monthFirstDay(month), monthLastDay(month)), current: i === 11 }
    })
    prevStart = monthFirstDay(addMonths(endMonth, -23))
    prevEnd = addDays(points[0].start, -1)
  }
  const start = points[0].start
  const end = points[points.length - 1].end
  const average = history.average(start, end)
  const previousAverage = history.average(prevStart, prevEnd)
  return { points, start, end, average, previousAverage,
    delta: average != null && previousAverage != null ? Math.round(average - previousAverage) : undefined }
}

/** Heatmap intensity bucket: 0 (best, brightest) … 3 (highest score, dimmest). */
export function heatBucket(score: number, goal: number): number {
  return score <= goal ? 0 : score <= goal + 7 ? 1 : score <= goal + 15 ? 2 : 3
}
