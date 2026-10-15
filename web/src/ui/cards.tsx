import { CircleCheck, Circle, CircleDashed, Droplet, Minus, Moon, Plus, Sunrise, Utensils, Loader } from 'lucide-react'
import { useEffect, useRef, type ReactNode } from 'react'
import { fmt, monthLastDay } from '../domain/dates'
import type { ChallengeStatus, Correlation } from '../domain/progress'
import { ZONE_TITLES, type FaceZone } from '../domain/types'
import { Card, ProgressBar, haptic } from './components'

const RING_COLOR = { dePuff: 'var(--accent)', scan: 'var(--scan)', habits: 'var(--habits)' }
const RING_TRACK = { dePuff: 'var(--track-depuff)', scan: 'var(--track-scan)', habits: 'var(--track-habits)' }

export function ZoneTile({ zone, value }: { zone: FaceZone; value: number }) {
  return (
    <div className="card" style={{ flex: 1, padding: 12, borderRadius: 12 }}>
      <div className="foot">{ZONE_TITLES[zone]}</div>
      <div className="metric sm accent" style={{ marginTop: 6 }}>{value}</div>
    </div>
  )
}

export function GoalStepperCard({ kind, value, range, unit, message, onChange }: {
  kind: 'dePuff' | 'scan' | 'habits'; value: number; range: readonly [number, number]; unit: string; message: string; onChange: (v: number) => void
}) {
  const title = { dePuff: 'De-Puff', scan: 'Scan', habits: 'Habits' }[kind]
  const step = (d: number) => {
    const next = Math.min(range[1], Math.max(range[0], value + d))
    if (next !== value) { haptic(8); onChange(next) }
  }
  return (
    <Card>
      <div style={{ color: RING_COLOR[kind], fontWeight: 600, fontSize: 17 }}>{title}</div>
      <div className="row" style={{ margin: '6px 0' }}>
        <span className="metric xl grow" style={{ color: RING_COLOR[kind] }} aria-live="polite">{value}</span>
        <div className="row" style={{ gap: 0, background: 'var(--card-elevated)', borderRadius: 999 }}>
          <button aria-label={`Decrease ${title} goal`} disabled={value <= range[0]} onClick={() => step(-1)} style={{ width: 52, height: 36, display: 'grid', placeItems: 'center', opacity: value <= range[0] ? 0.3 : 1 }}><Minus size={20} /></button>
          <span style={{ width: 1, height: 20, background: 'var(--separator)' }} />
          <button aria-label={`Increase ${title} goal`} disabled={value >= range[1]} onClick={() => step(1)} style={{ width: 52, height: 36, display: 'grid', placeItems: 'center', opacity: value >= range[1] ? 0.3 : 1 }}><Plus size={20} /></button>
        </div>
      </div>
      <div className="headline">{unit}</div>
      <div className="foot" style={{ marginTop: 4 }}>{message}</div>
    </Card>
  )
}

export function ChallengeCard({ status, hero, onJoin }: { status: ChallengeStatus; hero?: boolean; onJoin?: () => void }) {
  const c = status.definition
  const color = RING_COLOR[c.accent]
  const Icon = { sunrise: Sunrise, droplet: Droplet, moon: Moon, rings: CircleDashed }[c.icon]
  return (
    <Card>
      {hero && <div className="center" style={{ color, padding: '8px 0 12px' }}><Icon size={56} strokeWidth={1.2} /></div>}
      <div style={{ fontSize: hero ? 22 : 20, fontWeight: 700, color: hero ? 'var(--label)' : color }}>{c.title}</div>
      <p className="body" style={{ color: 'var(--label-2)', margin: '6px 0 10px' }}>{c.description}</p>
      {status.joined ? (
        <div className="stack lg">
          <div className="row baseline" style={{ gap: 8 }}>
            <span className="metric md" style={{ color }}>{status.progress} / {c.target}</span>
            {!c.requiresJoin && <span className="foot">{c.kind === 'scanDays' ? 'days scanned' : 'days logged'}</span>}
          </div>
          <ProgressBar value={status.fraction} color={color} track={RING_TRACK[c.accent]} />
          {c.requiresJoin && <span className="pill accent" style={{ alignSelf: 'flex-start' }}>Joined · Ends {fmt.shortDay(monthLastDay(c.month))}</span>}
          <span className="foot">{c.requiresJoin ? c.rewardText : `${fmt.plural(status.daysLeft, 'day')} left · ${status.paceText}`}</span>
        </div>
      ) : (
        <div className="stack lg">
          <button className="btn primary" onClick={onJoin}>Join Challenge</button>
          {c.rewardText && <span className="foot">{c.rewardText}</span>}
        </div>
      )}
    </Card>
  )
}

export function CorrelationCard({ c }: { c: Correlation }) {
  const Icon = { sleep: Moon, water: Droplet, salt: Utensils, cycle: CircleDashed }[c.factor]
  const color = c.strength === 'insufficient' ? 'var(--label-2)' : (c.delta ?? 0) <= 0 ? 'var(--habits)' : 'var(--accent)'
  return (
    <Card>
      <div className="row"><span style={{ color: c.factor === 'salt' && c.strength !== 'insufficient' ? 'var(--accent)' : color }}><Icon size={22} /></span>
        <span className="headline">{c.factor[0].toUpperCase() + c.factor.slice(1)}</span></div>
      <div className="metric sm" style={{ color, margin: '10px 0 8px' }}>{c.deltaText ?? 'More data needed'}</div>
      <p className="body" style={{ color: 'var(--label-2)', margin: 0 }}>{c.explanation}</p>
      <p className="foot" style={{ margin: '8px 0 0' }}>{c.footnote}</p>
    </Card>
  )
}

export function StepList({ steps }: { steps: { title: string; state: 'pending' | 'active' | 'done' }[] }) {
  return (
    <Card>
      <div className="stack lg">
        {steps.map((s) => (
          <div key={s.title} className="row" aria-label={`${s.title}: ${s.state}`}>
            {s.state === 'done' ? <CircleCheck size={22} color="var(--scan)" />
              : s.state === 'active' ? <Loader size={22} color="var(--habits)" style={{ animation: 'spin 1s linear infinite' }} />
              : <Circle size={22} color="var(--label-3)" />}
            <span className="body" style={{ color: s.state === 'done' ? 'var(--scan)' : s.state === 'active' ? 'var(--habits)' : 'var(--label-2)' }}>
              {s.title}{s.state === 'active' ? '…' : ''}
            </span>
          </div>
        ))}
      </div>
      <style>{'@keyframes spin { to { transform: rotate(360deg) } }'}</style>
    </Card>
  )
}

/** Lightweight canvas confetti burst. */
export function Confetti() {
  const ref = useRef<HTMLCanvasElement>(null)
  useEffect(() => {
    if (matchMedia('(prefers-reduced-motion: reduce)').matches) return
    const canvas = ref.current!
    const ctx = canvas.getContext('2d')!
    const dpr = devicePixelRatio || 1
    canvas.width = canvas.offsetWidth * dpr
    canvas.height = canvas.offsetHeight * dpr
    ctx.scale(dpr, dpr)
    const colors = ['#FF1050', '#96E52B', '#1EEAEF', '#ffffff']
    const pieces = Array.from({ length: 80 }, (_, i) => ({
      x: Math.random() * canvas.offsetWidth, y: -20 - Math.random() * 200, v: 140 + Math.random() * 220,
      spin: Math.random() * 6, size: 5 + Math.random() * 6, color: colors[i % colors.length], sway: Math.random() * 6,
    }))
    let raf = 0
    const start = performance.now()
    const tick = (t: number) => {
      const s = (t - start) / 1000
      ctx.clearRect(0, 0, canvas.offsetWidth, canvas.offsetHeight)
      for (const p of pieces) {
        const y = p.y + p.v * s
        if (y > canvas.offsetHeight + 20) continue
        ctx.save()
        ctx.translate(p.x + Math.sin(s * 3 + p.sway) * 16, y)
        ctx.rotate(s * 4 + p.spin)
        ctx.fillStyle = p.color
        ctx.fillRect(-p.size / 2, -p.size / 4, p.size, p.size / 2)
        ctx.restore()
      }
      if (s < 4) raf = requestAnimationFrame(tick)
    }
    raf = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(raf)
  }, [])
  return <canvas ref={ref} aria-hidden style={{ position: 'fixed', inset: 0, width: '100%', height: '100%', pointerEvents: 'none', zIndex: 55 }} />
}

export function Labeled({ label, children }: { label: string; children: ReactNode }) {
  return <div className="stack"><span className="foot" style={{ textTransform: 'uppercase' }}>{label}</span>{children}</div>
}
