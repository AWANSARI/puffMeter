import { ChevronLeft, ChevronRight } from 'lucide-react'
import { addMonths, daysInMonth, fmt, monthFirstDay, weekdayIndexMondayFirst, type DayKey, type MonthKey } from '../domain/dates'
import type { DayStats, History } from '../domain/engine'
import { heatBucket, type TrendPoint } from '../domain/progress'
import { ActivityRings } from './rings'

/** Score bars with value labels, an optional goal rule, and the current/selected bar highlighted. */
export function ScoreBarChart({ points, goal, height = 140, selected, onSelect }: {
  points: TrendPoint[]; goal?: number; height?: number; selected?: string; onSelect?: (id?: string) => void
}) {
  const max = Math.max(...points.map((p) => p.value ?? 0), goal ?? 0, 10) * 1.18
  const dense = points.length > 14
  const labelEvery = dense ? Math.ceil(points.length / 7) : 1
  const summary = points.filter((p) => p.value != null).map((p) => `${p.label} ${Math.round(p.value!)}`).join(', ')
  return (
    <div role="img" aria-label={`Puffiness Score chart, lower is better. ${summary}`} style={{ position: 'relative' }}>
      <div style={{ display: 'flex', alignItems: 'flex-end', gap: dense ? 2 : 10, height }}>
        {points.map((p) => {
          const hl = selected ? selected === p.id : p.current
          return (
            <button key={p.id} onClick={() => onSelect?.(selected === p.id ? undefined : p.id)}
              style={{ flex: 1, height: '100%', display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', alignItems: 'center', gap: 4 }}
              aria-label={`${p.label}: ${p.value != null ? Math.round(p.value) : 'no scan'}`}>
              {!dense && p.value != null && <span style={{ fontSize: 12, color: 'var(--label-2)' }}>{Math.round(p.value)}</span>}
              <div style={{ width: dense ? '100%' : '72%', height: p.value != null ? `${(p.value / max) * 100}%` : 0, borderRadius: 3,
                background: hl ? 'var(--accent)' : 'var(--track-depuff)', transition: 'height .4s ease' }} />
            </button>
          )
        })}
      </div>
      {goal != null && (
        <div aria-hidden style={{ position: 'absolute', left: 0, right: 0, bottom: `${(goal / max) * height}px`, height: 1, background: 'var(--label-3)' }} />
      )}
      <div style={{ display: 'flex', gap: dense ? 2 : 10, marginTop: 6 }}>
        {points.map((p, i) => {
          const hl = selected ? selected === p.id : p.current
          return (
            <span key={p.id} style={{ flex: 1, textAlign: 'center', fontSize: 12, fontWeight: hl ? 600 : 400, color: hl ? 'var(--label)' : 'var(--label-2)', whiteSpace: 'nowrap', overflow: 'visible' }}>
              {i % labelEvery === 0 || p.current ? p.label : ''}
            </span>
          )
        })}
      </div>
    </div>
  )
}

export function StreakRow({ days }: { days: DayStats[] }) {
  return (
    <div style={{ display: 'flex' }}>
      {days.map((d) => (
        <div key={d.day} style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6 }}
          aria-label={`${fmt.longDay(d.day)}: ${d.scanCount ? 'scanned' : 'no scan'}`}>
          <ActivityRings progress={d.rings} size="mini" animate={false} />
          <span className="foot">{fmt.weekdayInitial(d.day)}</span>
        </div>
      ))}
    </div>
  )
}

/** Month heatmap: scanned days tinted by score (brighter = lower = better). Monday-first. */
export function HeatmapCalendar({ month, history, today, selected, onSelect, onMonth }: {
  month: MonthKey; history: History; today: DayKey; selected?: DayKey; onSelect: (d: DayKey) => void; onMonth: (m: MonthKey) => void
}) {
  const blanks = weekdayIndexMondayFirst(monthFirstDay(month))
  const days = Array.from({ length: daysInMonth(month) }, (_, i) => `${month}-${String(i + 1).padStart(2, '0')}`)
  const heat = (bucket: number) => `rgba(255, 16, 80, ${[0.95, 0.62, 0.42, 0.26][bucket]})`
  return (
    <div className="stack lg">
      <div className="row">
        <h2 style={{ margin: 0, fontSize: 22 }} className="grow">{fmt.monthYear(month)}</h2>
        <button aria-label="Previous month" onClick={() => onMonth(addMonths(month, -1))} style={{ color: 'var(--accent)', padding: 6 }}><ChevronLeft /></button>
        <button aria-label="Next month" disabled={month >= today.slice(0, 7)} onClick={() => onMonth(addMonths(month, 1))}
          style={{ color: 'var(--accent)', padding: 6, opacity: month >= today.slice(0, 7) ? 0.3 : 1 }}><ChevronRight /></button>
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: 6 }}>
        {['M', 'T', 'W', 'T', 'F', 'S', 'S'].map((w, i) => <span key={i} className="foot center">{w}</span>)}
        {Array.from({ length: blanks }, (_, i) => <span key={`b${i}`} />)}
        {days.map((day) => {
          const s = history.stats(day)
          const future = day > today
          const bg = s.score == null ? 'var(--card-elevated)' : day === today ? 'var(--accent)' : heat(heatBucket(s.score, s.goals.dePuffMax))
          return (
            <button key={day} disabled={future} onClick={() => onSelect(day)}
              aria-label={`${fmt.longDay(day)}: ${s.score != null ? `score ${s.score}` : 'no scan'}`} aria-pressed={selected === day}
              style={{ minHeight: 44, borderRadius: 8, background: bg, opacity: future ? 0.5 : 1, fontSize: 15,
                fontWeight: s.score != null ? 600 : 400, color: s.score != null ? '#fff' : 'var(--label-2)',
                outline: selected === day ? '2px solid var(--label)' : 'none', outlineOffset: -2 }}>
              {Number(day.slice(8))}
            </button>
          )
        })}
      </div>
      <div className="row" style={{ gap: 6 }}>
        <span className="foot">Lower score</span>
        {[0, 1, 2, 3].map((b) => <span key={b} style={{ width: 18, height: 10, borderRadius: 3, background: heat(b) }} />)}
        <span className="foot">Higher</span>
      </div>
    </div>
  )
}
