import { Layers, TriangleAlert } from 'lucide-react'
import { useCallback, useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { fmt } from '../domain/dates'
import { ZONES, type ScanRecord } from '../domain/types'
import { allPassed, CARD_ASPECT, createCamera, EMPTY_CHECKS, guidance, isCentered, OVAL, type CameraSession, type CapturedFace, type ScanChecks } from '../services/faceCamera'
import { PhotoStore } from '../services/photoStore'
import { store, useApp } from '../store/appStore'
import { Alert, Card, ChecklistItem, ComparisonSlider, Delta, Disclaimer, haptic, Screen, ScanPhoto, TagChip, UploadStatusCard } from '../ui/components'
import { StepList, ZoneTile } from '../ui/cards'

/** Camera → countdown → analyzing → result. */
export function ScanFlow({ isBaseline, onDone }: { isBaseline: boolean; onDone: () => void }) {
  const [stage, setStage] = useState<{ kind: 'camera' } | { kind: 'analyzing'; capture: CapturedFace } | { kind: 'result'; id: string }>({ kind: 'camera' })
  if (stage.kind === 'camera') return <ScanCamera isBaseline={isBaseline} onCapture={(capture) => setStage({ kind: 'analyzing', capture })} />
  if (stage.kind === 'analyzing') {
    return <Analyzing capture={stage.capture} isBaseline={isBaseline} onDone={(id) => setStage(id ? { kind: 'result', id } : { kind: 'camera' })} />
  }
  return <ScanResult scanID={stage.id} isBaseline={isBaseline} onDone={onDone} />
}

function ScanCamera({ isBaseline, onCapture }: { isBaseline: boolean; onCapture: (c: CapturedFace) => void }) {
  const { d, settings } = useApp()
  const videoRef = useRef<HTMLVideoElement>(null)
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const session = useRef<CameraSession>(undefined)
  const [checks, setChecks] = useState<ScanChecks>(EMPTY_CHECKS)
  const [countdown, setCountdown] = useState<number>()
  const [error, setError] = useState<string>()
  const [capturing, setCapturing] = useState(false)
  const [flash, setFlash] = useState(false)
  const [ghost, setGhost] = useState(settings.ghostOverlayEnabled)
  const [ghostURL, setGhostURL] = useState<string>()
  const passStart = useRef<number>(undefined)
  const lastScan = d.scans[d.scans.length - 1]
  const ghostAvailable = !isBaseline && !!lastScan

  useEffect(() => {
    if (ghostAvailable) void PhotoStore.url(PhotoStore.photoKey(lastScan.id)).then(setGhostURL)
  }, [ghostAvailable, lastScan?.id]) // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    const cam = createCamera(store.getSnapshot().demo)
    session.current = cam
    const off = cam.onChecks(setChecks)
    cam.start(videoRef.current!, canvasRef.current!).catch((e: unknown) => {
      const denied = e instanceof DOMException && (e.name === 'NotAllowedError' || e.name === 'SecurityError')
      setError(denied ? "Camera access is off. Allow it in your browser's site settings, then reload." : "The camera or face model couldn't start. Check your connection and try again.")
    })
    return () => { off(); cam.stop() }
  }, [])

  const capture = useCallback(async (manual: boolean) => {
    if (!session.current || capturing) return
    setCapturing(true)
    setFlash(true)
    haptic(20)
    try {
      const c = await session.current.capture(manual)
      session.current.stop()
      onCapture(c)
    } catch {
      setError("Couldn't capture. Please try again.")
      setCapturing(false)
    } finally {
      setTimeout(() => setFlash(false), 150)
    }
  }, [capturing, onCapture])

  // Auto-capture: all checks pass for 0.8 s → 3-2-1 countdown → capture. Any failure cancels.
  useEffect(() => {
    if (capturing) return
    if (!allPassed(checks)) {
      passStart.current = undefined
      setCountdown(undefined)
      return
    }
    passStart.current ??= Date.now()
    if (countdown != null) return
    const wait = Math.max(0, 800 - (Date.now() - passStart.current))
    const t = setTimeout(() => setCountdown(3), wait)
    return () => clearTimeout(t)
  }, [checks, capturing, countdown])

  useEffect(() => {
    if (countdown == null) return
    haptic(8)
    const t = setTimeout(() => {
      if (countdown > 1) setCountdown(countdown - 1)
      else { setCountdown(undefined); void capture(false) }
    }, 1000)
    return () => clearTimeout(t)
  }, [countdown, capture])

  const headline = countdown != null ? "Hold still. You're ready." : guidance(checks) ?? (isBaseline ? "Let's set your baseline" : "Hold still. You're ready.")
  const simulated = session.current?.kind === 'simulated'
  return (
    <Screen title={isBaseline ? 'Your first scan' : 'Daily Scan'} subtitle="PuffyMeter" tabs={!isBaseline}>
      <div className="camera-card" aria-label="Camera preview">
        <video ref={videoRef} playsInline muted style={{ display: simulated ? 'none' : undefined }} />
        <canvas ref={canvasRef} className="preview" style={{ display: simulated ? undefined : 'none' }} />
        {ghostAvailable && ghost && ghostURL && <img className="ghost" src={ghostURL} alt="" />}
        <svg viewBox={`0 0 100 ${100 / CARD_ASPECT}`} style={{ position: 'absolute', inset: 0, width: '100%', height: '100%' }} aria-hidden>
          {checks.faceCount === 1 && <FaceMesh />}
          <ellipse cx={OVAL.cx * 100} cy={(OVAL.cy * 100) / CARD_ASPECT} rx={OVAL.w * 50} ry={(OVAL.h * 50) / CARD_ASPECT}
            fill="none" stroke={allPassed(checks) ? 'var(--ring-scan)' : 'var(--warning)'} strokeWidth="0.8" style={{ transition: 'stroke .2s' }} />
        </svg>
        <span className="chip-dark">FRONT CAMERA</span>
        {ghostAvailable && (
          <button className="ghost-btn" aria-label={ghost ? "Hide yesterday's photo overlay" : "Show yesterday's photo overlay"}
            onClick={() => { setGhost(!ghost); store.setSettings({ ghostOverlayEnabled: !ghost }) }}><Layers size={18} /></button>
        )}
        {countdown != null && <div className="countdown" key={countdown} style={{ bottom: 12 }} aria-live="assertive">{countdown}</div>}
      </div>
      <h2 className="center" style={{ fontSize: 22, margin: '4px 0 0' }} aria-live="polite">{headline}</h2>
      <div className="row" style={{ alignItems: 'flex-start' }}>
        <ChecklistItem title="Centered" passed={isCentered(checks)} />
        <ChecklistItem title="Good lighting" passed={checks.goodLighting} />
        <ChecklistItem title="Neutral face" passed={checks.neutralFace} />
      </div>
      <p className="foot center" style={{ margin: 0, whiteSpace: 'pre-line' }}>
        {countdown != null ? `Auto-capture in ${countdown} seconds${ghostAvailable && ghost ? "\nYesterday's photo is faintly overlaid for alignment." : ''}`
          : isBaseline ? 'Face the camera at eye level in even light.\nYour first score is a starting point, not a verdict.'
          : 'Capture starts automatically when all three checks pass.'}
      </p>
      {simulated && <p className="foot center" style={{ margin: 0 }}>Demo camera: a sample face is used instead of your camera.</p>}
      {error && <p className="foot accent center" role="alert">{error}</p>}
      {countdown != null
        ? <button className="btn primary" onClick={() => { setCountdown(undefined); passStart.current = Date.now() + 60_000 }}>Cancel countdown</button>
        : <button className="btn primary" disabled={capturing || checks.faceCount === 0} onClick={() => capture(!allPassed(checks))}>{isBaseline ? 'Capture baseline' : 'Capture now'}</button>}
      {flash && <div className="flash" />}
    </Screen>
  )
}

function FaceMesh() {
  const cx = OVAL.cx * 100
  const cy = (OVAL.cy * 100) / CARD_ASPECT - 2
  const w = OVAL.w * 46
  const h = (OVAL.h * 39) / CARD_ASPECT
  const p = (x: number, y: number) => `${cx - w + x * 2 * w},${cy - h + y * 2 * h}`
  const outline = [[0.5, 0], [0.8, 0.08], [0.95, 0.35], [0.88, 0.62], [0.7, 0.88], [0.5, 1], [0.3, 0.88], [0.12, 0.62], [0.05, 0.35], [0.2, 0.08]]
  const inner = [[0.5, 0.25], [0.72, 0.38], [0.65, 0.62], [0.5, 0.72], [0.35, 0.62], [0.28, 0.38]]
  return (
    <g stroke="var(--ring-habits)" strokeOpacity="0.7" strokeWidth="0.25" fill="none">
      <polygon points={outline.map(([x, y]) => p(x, y)).join(' ')} />
      <polygon points={inner.map(([x, y]) => p(x, y)).join(' ')} />
      {outline.map(([x, y], i) => <line key={i} x1={p(x, y).split(',')[0]} y1={p(x, y).split(',')[1]} x2={p(...inner[i % 6] as [number, number]).split(',')[0]} y2={p(...inner[i % 6] as [number, number]).split(',')[1]} />)}
      <line x1={p(0.05, 0.35).split(',')[0]} y1={p(0.05, 0.35).split(',')[1]} x2={p(0.95, 0.35).split(',')[0]} y2={p(0.95, 0.35).split(',')[1]} />
      <line x1={p(0.5, 0).split(',')[0]} y1={p(0.5, 0).split(',')[1]} x2={p(0.5, 1).split(',')[0]} y2={p(0.5, 1).split(',')[1]} />
    </g>
  )
}

function Analyzing({ capture, isBaseline, onDone }: { capture: CapturedFace; isBaseline: boolean; onDone: (id?: string) => void }) {
  const [step, setStep] = useState(0)
  const [error, setError] = useState(false)
  const [url] = useState(() => URL.createObjectURL(capture.blob))
  useEffect(() => () => URL.revokeObjectURL(url), [url])
  useEffect(() => {
    let alive = true
    const started = Date.now()
    const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))
    void (async () => {
      await sleep(500)
      if (!alive) return
      setStep(1)
      try {
        const record = await store.recordScan(capture, isBaseline)
        setStep(2)
        await sleep(Math.max(400, 1500 - (Date.now() - started)))
        setStep(3)
        await sleep(250)
        if (alive) onDone(record.id)
      } catch {
        if (alive) setError(true)
      }
    })()
    return () => { alive = false }
  }, []) // eslint-disable-line react-hooks/exhaustive-deps
  const state = (i: number) => (i < step ? 'done' : i === step ? 'active' : 'pending') as 'done' | 'active' | 'pending'
  return (
    <Screen title="Analyzing" subtitle="PuffyMeter" tabs={false}>
      <div className="photo" style={{ borderRadius: 20, aspectRatio: '0.98' }}>
        <img src={url} alt="Captured photo" />
        <div className="scanline" />
      </div>
      <h2 className="center" style={{ fontSize: 28, margin: '4px 0 0' }}>{error ? 'Something went wrong' : 'A moment for you.'}</h2>
      <p className="body sub center" style={{ margin: 0 }}>{error ? "We couldn't analyze this photo. Try again in even light." : "Comparing today's face zones with your recent scans."}</p>
      {error ? <button className="btn primary" onClick={() => onDone()}>Try again</button> : (
        <StepList steps={[
          { title: 'Photo quality checked', state: state(0) },
          { title: 'Estimating face zones', state: state(1) },
          { title: 'Preparing your comparison', state: state(2) },
        ]} />
      )}
      <Disclaimer center>Your score is a cosmetic estimate, not a diagnosis.</Disclaimer>
    </Screen>
  )
}

function ScanResult({ scanID, isBaseline, onDone }: { scanID: string; isBaseline: boolean; onDone: () => void }) {
  const { d, history, today } = useApp()
  const navigate = useNavigate()
  const scan = d.scans.find((s) => s.id === scanID)
  const [notes, setNotes] = useState(scan?.notes ?? '')
  const [tags, setTags] = useState<string[]>(scan?.tags ?? [])
  const [selected, setSelected] = useState<Set<string>>(new Set(scan?.tags ?? []))
  const [position, setPosition] = useState(0.5)
  const [alert, setAlert] = useState(false)
  const upload = store.uploadCardState(scanID)
  const failed = upload.kind === 'failed'
  useEffect(() => { if (failed) { setAlert(true); haptic([30, 40, 30]) } }, [failed])
  if (!scan) return null
  const previous = history.previousScan(scan.dayKey)
  const dayWord = (s: ScanRecord) => (s.dayKey === addDayKey(today, -1) ? 'yesterday' : fmt.shortDay(s.dayKey))
  const finish = () => { store.finalizeScan(scanID, notes, tags.filter((t) => selected.has(t))); onDone() }
  const onUploadAction = () => {
    if (upload.kind !== 'failed') return
    if (upload.failure === 'authExpired' || upload.failure === 'folderMissing') { finish(); navigate('/profile/drive') } else store.retryUploads()
  }
  return (
    <Screen title={isBaseline ? 'Baseline set' : 'Scan result'} tabs={false}
      subtitle={isBaseline ? 'Future scans compare to this one' : `${new Date(scan.capturedAt).toLocaleDateString('en-US', { month: 'long', day: 'numeric' })} · ${fmt.time(scan.capturedAt)}`}>
      <Card>
        <div className="headline">Puffiness Score</div>
        <div className="row baseline" style={{ margin: '8px 0' }}>
          <span className="metric hero accent">{scan.score}</span>
          <span className="body sub">/ 100 · Lower is better</span>
        </div>
        {isBaseline ? <span className="sub">This is your starting point, not a verdict.</span>
          : previous && <Delta value={scan.score - previous.score} size={17}
              suffix={scan.score === previous.score ? `from ${dayWord(previous)}'s ${previous.score}` : `points from ${dayWord(previous)}'s ${previous.score}`} />}
        {scan.lowConfidence && <div className="row foot" style={{ color: 'var(--warning)', marginTop: 8 }}><TriangleAlert size={16} />Lower confidence: lighting or angle differed</div>}
      </Card>
      {previous && !isBaseline ? (
        <>
          <div className="row" style={{ justifyContent: 'space-between' }}>
            <span className="sub">{dayWord(previous)[0].toUpperCase() + dayWord(previous).slice(1)} · {previous.score}</span>
            <span>Today · {scan.score}</span>
          </div>
          <ComparisonSlider before={previous.id} after={scan.id} position={position} onChange={setPosition} />
          <input type="range" min={0} max={100} value={Math.round(position * 100)} onChange={(e) => setPosition(Number(e.target.value) / 100)}
            aria-label="Comparison position" style={{ width: '100%', accentColor: 'var(--link)' }} />
        </>
      ) : <ScanPhoto scanID={scan.id} radius={20} style={{ aspectRatio: '0.75' }} />}
      <div className="row" style={{ gap: 8 }}>{ZONES.map((z) => <ZoneTile key={z} zone={z} value={scan.zones[z]} />)}</div>
      <div className="headline" style={{ marginTop: 4 }}>Notes & tags</div>
      <textarea className="field" rows={2} placeholder="Add a note" value={notes} onChange={(e) => setNotes(e.target.value)} aria-label="Notes" />
      <div className="wrap">
        {tags.map((t) => <TagChip key={t} title={t} on={selected.has(t)} onClick={() => {
          const next = new Set(selected)
          if (next.has(t)) next.delete(t); else next.add(t)
          setSelected(next)
        }} />)}
        <TagChip title="+ Tag" on={false} onClick={() => {
          const t = prompt('Add a tag')?.trim()
          if (t && !tags.includes(t)) { setTags([...tags, t]); setSelected(new Set([...selected, t])) }
        }} />
      </div>
      <UploadStatusCard state={upload} onAction={onUploadAction} />
      {failed ? (
        <>
          <button className="btn primary" onClick={() => store.retryUploads()}>Retry upload</button>
          <button className="btn secondary" onClick={finish}>Done</button>
        </>
      ) : <button className="btn primary" onClick={finish}>{upload.kind === 'queued' ? 'Done · Save locally' : 'Done'}</button>}
      <Disclaimer center>Lighting and expression can affect your score.</Disclaimer>
      {alert && (
        <Alert title="Couldn't save to Drive"
          message={upload.kind === 'failed' && upload.failure === 'authExpired'
            ? 'Your scan is safe on this device. Reconnect Google Drive in Profile to finish backing up.'
            : 'Your scan is safe on this device.\nCheck your connection and try again.'}
          buttons={[{ label: 'Later', onClick: () => setAlert(false) }, { label: 'Retry', onClick: () => { setAlert(false); store.retryUploads() } }]} />
      )}
    </Screen>
  )
}

function addDayKey(day: string, n: number) {
  const [y, m, dd] = day.split('-').map(Number)
  const date = new Date(y, m - 1, dd + n, 12)
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`
}

/** Scan tab: camera when today's scan is missing, otherwise today's result with a retake option. */
export function ScanTab() {
  const { todayStats, d, history } = useApp()
  const navigate = useNavigate()
  const [scanning, setScanning] = useState(false)
  const [confirmRetake, setConfirmRetake] = useState(false)
  const [flowKey, setFlowKey] = useState(0)
  const today = todayStats.primaryScan
  if (today && !scanning) {
    return (
      <Screen title="Daily Scan" subtitle="Done for today">
        <Card>
          <div className="row top">
            <div className="grow">
              <div className="foot">{fmt.time(today.capturedAt)}</div>
              <div className="metric lg accent" style={{ margin: '6px 0' }}>{today.score}</div>
              <Delta value={history.deltaVsPrevious(today.dayKey)} />
            </div>
            <ScanPhoto scanID={today.id} thumb style={{ width: 96, height: 124 }} />
          </div>
          <div className="row" style={{ gap: 8, marginTop: 12 }}>{ZONES.map((z) => <ZoneTile key={z} zone={z} value={today.zones[z]} />)}</div>
        </Card>
        <button className="btn primary" onClick={() => navigate(`/scans/${today.id}`)}>View result</button>
        <button className="btn secondary" onClick={() => setConfirmRetake(true)}>Retake today's scan</button>
        <Disclaimer center>A retake replaces today's photo and score.</Disclaimer>
        {confirmRetake && (
          <Alert title="Retake today's scan?" message="Your new photo and score will replace today's."
            buttons={[{ label: 'Cancel', onClick: () => setConfirmRetake(false) },
              { label: 'Retake', onClick: () => { setConfirmRetake(false); setFlowKey((k) => k + 1); setScanning(true) } }]} />
        )}
      </Screen>
    )
  }
  return <ScanFlow key={flowKey} isBaseline={d.scans.length === 0} onDone={() => { setScanning(false); if (!store.getSnapshot().showAllRingsClosed) navigate('/') }} />
}
