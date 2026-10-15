import { ArrowDown, ArrowLeftRight, ArrowUp, CircleCheck, Circle, ChevronLeft, ChevronRight, CloudAlert, CloudCheck, CloudOff, CloudUpload, Smartphone } from 'lucide-react'
import { useEffect, useRef, useState, type ReactNode } from 'react'
import { useNavigate } from 'react-router-dom'
import { fmt } from '../domain/dates'
import { FAILURE_ACTION, FAILURE_MESSAGE, type HabitKind, type HabitLog } from '../domain/types'
import { PhotoStore } from '../services/photoStore'
import { store, useApp, type UploadCardState } from '../store/appStore'

// MARK: Layout

export function Screen({ title, subtitle, back, action, children, tabs = true }: {
  title: string; subtitle?: string; back?: boolean | string; action?: ReactNode; children: ReactNode; tabs?: boolean
}) {
  const navigate = useNavigate()
  useEffect(() => { document.title = `${title} · PuffyMeter` }, [title])
  return (
    <main className={`screen${tabs ? '' : ' no-tabs'}`}>
      {(back || action) && <div className="navbar">
        {back ? (
          <button className="back" onClick={() => (typeof back === 'string' ? navigate(back) : navigate(-1))}>
            <ChevronLeft size={22} /> Back
          </button>
        ) : <span />}
        {action}
      </div>}
      <div>
        <h1 className="large-title">{title}</h1>
        {subtitle && <p className="subtitle">{subtitle}</p>}
      </div>
      {children}
    </main>
  )
}

export function Card({ children, flush, style, onClick, className = '' }: { children: ReactNode; flush?: boolean; style?: React.CSSProperties; onClick?: () => void; className?: string }) {
  return <section className={`card${flush ? ' flush' : ''} ${className}`} style={style} onClick={onClick}>{children}</section>
}

export function SectionHeader({ title, action, onAction }: { title: string; action?: string; onAction?: () => void }) {
  return (
    <div className="section-header">
      <h2>{title}</h2>
      {action && <button onClick={onAction}>{action}<ChevronRight size={18} /></button>}
    </div>
  )
}

export function Disclaimer({ children, center }: { children: ReactNode; center?: boolean }) {
  return <p className={`foot${center ? ' center' : ''}`} style={{ margin: '4px 0' }}>{children}</p>
}

// MARK: Metrics

export function Delta({ value, suffix = 'vs yesterday', size = 13 }: { value?: number; suffix?: string; size?: number }) {
  if (value == null) return null
  if (value === 0) return <span style={{ fontSize: size, color: 'var(--label-2)' }}>No change {suffix}</span>
  const down = value < 0
  return (
    <span style={{ fontSize: size, color: down ? 'var(--scan)' : 'var(--accent)', display: 'inline-flex', alignItems: 'center', gap: 4 }}
      aria-label={`${down ? 'Down' : 'Up'} ${Math.abs(value)} ${suffix}`}>
      {down ? <ArrowDown size={size} /> : <ArrowUp size={size} />}{Math.abs(value)} {suffix}
    </span>
  )
}

export function ProgressBar({ value, color, track }: { value: number; color: string; track?: string }) {
  const pct = Math.round(Math.min(1, Math.max(0, value)) * 100)
  return (
    <div className="bar" style={{ background: track ?? 'var(--secondary-fill)' }} role="progressbar" aria-valuenow={pct} aria-valuemin={0} aria-valuemax={100}>
      <div style={{ width: `${Math.max(pct, 2)}%`, background: color }} />
    </div>
  )
}

export function InsightCard({ icon, title, body, footnote }: { icon?: ReactNode; title: string; body: string; footnote?: string }) {
  return (
    <Card>
      <div className="row" style={{ marginBottom: 8 }}>
        {icon && <span style={{ color: 'var(--habits)' }}>{icon}</span>}
        <span className="headline">{title}</span>
      </div>
      <p className="body" style={{ color: 'var(--label-2)', margin: 0 }}>{body}</p>
      {footnote && <p className="foot" style={{ margin: '8px 0 0' }}>{footnote}</p>}
    </Card>
  )
}

export function ChecklistItem({ title, passed }: { title: string; passed: boolean }) {
  return (
    <div className="stack center" style={{ flex: 1, alignItems: 'center', gap: 6 }} aria-label={`${title}, ${passed ? 'passed' : 'not yet'}`}>
      {passed ? <CircleCheck size={22} color="var(--scan)" /> : <Circle size={22} color="var(--label-3)" />}
      <span style={{ fontSize: 13, color: passed ? 'var(--label)' : 'var(--label-2)' }}>{title}</span>
    </div>
  )
}

export function Toggle({ checked, onChange, label }: { checked: boolean; onChange: (v: boolean) => void; label: string }) {
  return (
    <label className="toggle">
      <input type="checkbox" role="switch" checked={checked} aria-label={label} onChange={(e) => onChange(e.target.checked)} />
      <span />
    </label>
  )
}

export function Segmented<T extends string>({ options, value, onChange }: { options: T[]; value: T; onChange: (v: T) => void }) {
  return (
    <div className="segmented" role="group">
      {options.map((o) => <button key={o} aria-pressed={o === value} onClick={() => onChange(o)}>{o}</button>)}
    </div>
  )
}

// MARK: Chips

export function HabitChip({ kind, log, waterGoal, onClick }: { kind: HabitKind; log?: HabitLog; waterGoal: number; onClick: () => void }) {
  let label: string
  let logged: boolean
  switch (kind) {
    case 'water':
      logged = log?.waterLiters != null
      label = `+ Water · ${log?.waterLiters ?? 0} / ${fmt.liters(waterGoal)}`
      break
    case 'sleep':
      logged = log?.sleepHours != null
      label = `Sleep · ${logged ? fmt.hours(log!.sleepHours!) : 'Log'}`
      break
    case 'salt':
      logged = !!log?.salt
      label = `Salt · ${log?.salt ? log.salt[0].toUpperCase() + log.salt.slice(1) : 'Log'}`
      break
    case 'alcohol':
      logged = !!log?.alcohol
      label = `Alcohol · ${log?.alcohol === 'none' ? 'None' : log?.alcohol === 'one' ? '1 drink' : log?.alcohol === 'twoPlus' ? '2+ drinks' : 'Log'}`
      break
  }
  return <button className={`chip${logged ? '' : ' off'}`} onClick={onClick}>{!logged && kind !== 'water' ? '+ ' : ''}{label}</button>
}

export function TagChip({ title, on, onClick }: { title: string; on: boolean; onClick?: () => void }) {
  return <button className={`chip${on ? '' : ' neutral'}`} aria-pressed={on} onClick={onClick}>{title}</button>
}

// MARK: Upload status

export function UploadStatusCard({ state, onAction }: { state: UploadCardState; onAction?: () => void }) {
  const cfg = {
    uploading: { icon: <CloudUpload size={22} />, color: 'var(--habits)', title: 'Uploading to Google Drive' },
    saved: { icon: <CloudCheck size={22} />, color: 'var(--scan)', title: 'Saved to Google Drive' },
    failed: { icon: <CloudAlert size={22} />, color: 'var(--accent)', title: 'Upload failed' },
    queued: { icon: <CloudOff size={22} />, color: 'var(--label-2)', title: 'Offline · Upload queued' },
    localOnly: { icon: <Smartphone size={22} />, color: 'var(--label-2)', title: 'Saved on this device' },
  }[state.kind]
  const subtitle = state.kind === 'uploading' ? `Daily photo and notes · ${Math.round(state.progress * 100)}%`
    : state.kind === 'saved' ? state.path
    : state.kind === 'failed' ? `Your scan is safe on this device. ${FAILURE_MESSAGE[state.failure]}`
    : state.kind === 'queued' ? "Will sync when you're back online."
    : 'Connect Google Drive in Profile to back up your scans.'
  return (
    <Card>
      <div className="row top">
        <span style={{ color: cfg.color }}>{cfg.icon}</span>
        <div className="grow">
          <div className="headline" style={{ color: cfg.color }}>{cfg.title}</div>
          <div className="foot">{subtitle}</div>
        </div>
        {state.kind === 'failed' && onAction && <button className="text-btn" onClick={onAction}>{FAILURE_ACTION[state.failure]}</button>}
      </div>
      {state.kind === 'uploading' && <div style={{ marginTop: 10 }}><ProgressBar value={state.progress} color="var(--habits)" /></div>}
      {state.kind === 'saved' && <div className="foot" style={{ marginTop: 8 }}>{state.fileName} · Synced just now</div>}
      {state.kind === 'queued' && <div className="foot" style={{ marginTop: 8 }}>Saved locally · {fmt.plural(state.count, 'item')} waiting to sync</div>}
    </Card>
  )
}

// MARK: Photos

export function ScanPhoto({ scanID, thumb, radius = 12, style }: { scanID?: string; thumb?: boolean; radius?: number; style?: React.CSSProperties }) {
  const { snap } = useApp()
  const [url, setUrl] = useState<string>()
  useEffect(() => {
    let alive = true
    if (!scanID) { setUrl(undefined); return }
    const key = thumb ? PhotoStore.thumbKey(scanID) : PhotoStore.photoKey(scanID)
    PhotoStore.url(key).then((u) => { if (alive) setUrl(u) })
    return () => { alive = false }
  }, [scanID, thumb, snap.photosRevision])
  return (
    <div className="photo" style={{ borderRadius: radius, ...style }}>
      {url ? <img src={url} alt="Scan photo" draggable={false} /> : <div style={{ width: '100%', height: '100%' }} aria-label="No photo" />}
    </div>
  )
}

/** Before/after split with a draggable handle; `position` is how much of "before" shows. */
export function ComparisonSlider({ before, after, position, onChange }: { before?: string; after?: string; position: number; onChange: (p: number) => void }) {
  const ref = useRef<HTMLDivElement>(null)
  const drag = (clientX: number) => {
    const rect = ref.current!.getBoundingClientRect()
    onChange(Math.min(1, Math.max(0, (clientX - rect.left) / rect.width)))
  }
  return (
    <div ref={ref} className="photo" style={{ borderRadius: 20, aspectRatio: '1.48', touchAction: 'none', userSelect: 'none' }}
      onPointerDown={(e) => { (e.target as HTMLElement).setPointerCapture(e.pointerId); drag(e.clientX) }}
      onPointerMove={(e) => { if (e.buttons) drag(e.clientX) }}
      role="slider" aria-label="Before and after comparison" aria-valuenow={Math.round((1 - position) * 100)} aria-valuemin={0} aria-valuemax={100}
      tabIndex={0} onKeyDown={(e) => {
        if (e.key === 'ArrowLeft') onChange(Math.max(0, position - 0.1))
        if (e.key === 'ArrowRight') onChange(Math.min(1, position + 0.1))
      }}>
      <div style={{ position: 'absolute', inset: 0 }}><ScanPhoto scanID={after} radius={0} style={{ width: '100%', height: '100%' }} /></div>
      <div style={{ position: 'absolute', inset: 0, clipPath: `inset(0 ${100 - position * 100}% 0 0)` }}>
        <ScanPhoto scanID={before} radius={0} style={{ width: '100%', height: '100%' }} />
      </div>
      <div style={{ position: 'absolute', top: 0, bottom: 0, left: `calc(${position * 100}% - 1px)`, width: 2, background: '#fff' }} />
      <div style={{ position: 'absolute', top: '50%', left: `${position * 100}%`, transform: 'translate(-50%, -50%)', width: 44, height: 44,
        borderRadius: '50%', background: '#fff', color: '#000', display: 'grid', placeItems: 'center', boxShadow: '0 2px 10px rgba(0,0,0,.25)' }}>
        <ArrowLeftRight size={20} />
      </div>
    </div>
  )
}

// MARK: Overlays

export function Sheet({ title, onClose, children, cancel = 'Cancel', trailing }: { title?: string; onClose: () => void; children: ReactNode; cancel?: string | null; trailing?: ReactNode }) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose() }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onClose])
  return (
    <div className="backdrop" onClick={onClose}>
      <div className="sheet" role="dialog" aria-modal="true" aria-label={title} onClick={(e) => e.stopPropagation()}>
        <div className="grabber" />
        {(title || cancel) && (
          <div className="sheet-header">
            {cancel ? <button className="link-btn" onClick={onClose}>{cancel}</button> : <span />}
            {title && <h3>{title}</h3>}
            {trailing ?? <span style={{ width: 56 }} />}
          </div>
        )}
        {children}
      </div>
    </div>
  )
}

export function Alert({ title, message, buttons }: { title: string; message: string; buttons: { label: string; onClick: () => void; destructive?: boolean }[] }) {
  return (
    <div className="backdrop alert-backdrop">
      <div className="alert" role="alertdialog" aria-modal="true" aria-label={title}>
        <div className="content">
          <div className="headline" style={{ marginBottom: 4 }}>{title}</div>
          <div className="foot" style={{ color: 'var(--label)', whiteSpace: 'pre-line' }}>{message}</div>
        </div>
        <div className="buttons">
          {buttons.map((b) => (
            <button key={b.label} onClick={b.onClick} style={b.destructive ? { color: 'var(--destructive)' } : undefined}>{b.label}</button>
          ))}
        </div>
      </div>
    </div>
  )
}

export function Toast({ message, onDone }: { message: string; onDone: () => void }) {
  useEffect(() => {
    const t = setTimeout(onDone, 2600)
    return () => clearTimeout(t)
  }, [onDone])
  return <div className="toast" role="status">{message}</div>
}

export function haptic(pattern: number | number[] = 10) {
  // Browsers only allow vibration after the user has interacted with the page.
  const active = (navigator as Navigator & { userActivation?: { hasBeenActive: boolean } }).userActivation?.hasBeenActive ?? true
  try { if (active) navigator.vibrate?.(pattern) } catch { /* unsupported (e.g. iOS Safari) */ }
}

export { store }
