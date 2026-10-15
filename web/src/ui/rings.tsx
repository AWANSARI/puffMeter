import { useEffect, useState } from 'react'
import type { RingProgress, DayStats } from '../domain/engine'

export type RingSize = 'hero' | 'card' | 'compact' | 'mini' | 'logo'
const SIZES: Record<RingSize, { d: number; w: number }> = {
  hero: { d: 240, w: 28 }, card: { d: 168, w: 20 }, compact: { d: 88, w: 11 }, mini: { d: 32, w: 4.5 }, logo: { d: 26, w: 3.6 },
}

const KINDS = [
  { key: 'dePuff', color: 'var(--ring-depuff)', track: 'var(--track-depuff)', title: 'De-Puff' },
  { key: 'scan', color: 'var(--ring-scan)', track: 'var(--track-scan)', title: 'Scan' },
  { key: 'habits', color: 'var(--ring-habits)', track: 'var(--track-habits)', title: 'Habits' },
] as const

/** Apple Fitness–style triple rings: De-Puff (outer), Scan (middle), Habits (inner). */
export function ActivityRings({ progress, size, animate = true }: { progress: RingProgress; size: RingSize; animate?: boolean }) {
  const { d, w } = SIZES[size]
  const gap = w * 0.15
  const [shown, setShown] = useState(!animate)
  useEffect(() => {
    if (!animate) return
    const id = requestAnimationFrame(() => setShown(true))
    return () => cancelAnimationFrame(id)
  }, [animate])
  const value = (p: number) => (shown ? p : 0)
  const label = KINDS.map((k) => `${k.title} ${progress[k.key] >= 1 ? 'closed' : `${Math.round(Math.min(progress[k.key], 1) * 100)} percent`}`).join('. ')
  return (
    <svg width={d} height={d} viewBox={`0 0 ${d} ${d}`} role="img" aria-label={`Activity rings. ${label}.`} style={{ flex: 'none', overflow: 'visible' }}>
      <defs>
        <filter id={`cap-${size}`} x="-50%" y="-50%" width="200%" height="200%">
          <feDropShadow dx="0" dy="0" stdDeviation={w * 0.18} floodColor="#000" floodOpacity="0.5" />
        </filter>
      </defs>
      {KINDS.map((k, i) => {
        const r = d / 2 - w / 2 - i * (w + gap)
        const c = 2 * Math.PI * r
        const p = value(progress[k.key])
        const lap1 = Math.min(p, 1)
        const angle = (p * 360 - 90) * (Math.PI / 180)
        const cap = { x: d / 2 + r * Math.cos(angle), y: d / 2 + r * Math.sin(angle) }
        return (
          <g key={k.key}>
            <circle cx={d / 2} cy={d / 2} r={r} fill="none" stroke={k.track} strokeWidth={w} />
            {p > 0 && (
              <circle cx={d / 2} cy={d / 2} r={r} fill="none" stroke={k.color} strokeWidth={w} strokeLinecap="round"
                strokeDasharray={`${c * lap1} ${c}`} transform={`rotate(-90 ${d / 2} ${d / 2})`}
                style={{ transition: animate ? 'stroke-dasharray 0.9s cubic-bezier(.2,.8,.2,1)' : undefined }} />
            )}
            {p > 1 && (
              <>
                <circle cx={d / 2} cy={d / 2} r={r} fill="none" stroke={k.color} strokeWidth={w} strokeLinecap="round"
                  strokeDasharray={`${c * (p - 1)} ${c}`} transform={`rotate(-90 ${d / 2} ${d / 2})`} />
                <circle cx={cap.x} cy={cap.y} r={w / 2} fill={k.color} filter={`url(#cap-${size})`} />
              </>
            )}
            {p >= 1 && p <= 1.001 && (
              <line x1={d / 2} x2={d / 2} y1={d / 2 - r - w / 2} y2={d / 2 - r + w / 2} stroke="rgba(0,0,0,.35)" strokeWidth={1.2} />
            )}
          </g>
        )
      })}
    </svg>
  )
}

export function RingLegend({ stats }: { stats: DayStats }) {
  const rows = [
    { title: 'De-Puff', color: 'var(--accent)', value: `${stats.score ?? '--'} / ≤${stats.goals.dePuffMax}` },
    { title: 'Scan', color: 'var(--scan)', value: `${stats.scanCount} / ${stats.goals.scansPerDay}` },
    { title: 'Habits', color: 'var(--habits)', value: `${stats.habitCount} / ${stats.goals.habitsPerDay}` },
  ]
  return (
    <div className="stack" style={{ gap: 10 }}>
      {rows.map((r) => (
        <div key={r.title}>
          <div style={{ fontSize: 13, fontWeight: 600, color: r.color }}>{r.title}</div>
          <div style={{ fontSize: 22, fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>{r.value}</div>
        </div>
      ))}
    </div>
  )
}
