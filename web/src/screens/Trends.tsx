import { ChevronRight, Pause, Play, SkipBack, SkipForward, Trash2 } from 'lucide-react'
import { useEffect, useMemo, useRef, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { fmt, type DayKey, type MonthKey } from '../domain/dates'
import { RANGE_LABEL, TREND_RANGES, trendSeries, type TrendRange } from '../domain/progress'
import { ZONES, type ScanRecord } from '../domain/types'
import { PhotoStore } from '../services/photoStore'
import { store, useApp } from '../store/appStore'
import { Alert, Card, Delta, Disclaimer, ScanPhoto, Screen, SectionHeader, Segmented, TagChip, UploadStatusCard } from '../ui/components'
import { CorrelationCard, ZoneTile } from '../ui/cards'
import { HeatmapCalendar, ScoreBarChart } from '../ui/charts'

export function Trends() {
  const { history, today, goals, d } = useApp()
  const navigate = useNavigate()
  const [range, setRange] = useState<TrendRange>('W')
  const [offset, setOffset] = useState(0)
  const [selected, setSelected] = useState<string>()
  const touch = useRef(0)
  const series = trendSeries(range, history, today, offset)
  const sel = series.points.find((p) => p.id === selected)
  const recent = [...d.scans].reverse().slice(0, 10)
  return (
    <Screen title="Trends" subtitle="Your progress, in perspective">
      <Segmented options={TREND_RANGES} value={range} onChange={(r) => { setRange(r); setOffset(0); setSelected(undefined) }} />
      {range === 'D' ? (
        d.scans.length ? <ScanSummaryCard scan={history.stats(today).primaryScan ?? d.scans[d.scans.length - 1]} />
          : <Card><span className="sub">Take a scan to see today's detail.</span></Card>
      ) : (
        <Card>
          <div onTouchStart={(e) => { touch.current = e.touches[0].clientX }}
            onTouchEnd={(e) => {
              const dx = e.changedTouches[0].clientX - touch.current
              if (Math.abs(dx) < 50) return
              setSelected(undefined)
              setOffset((o) => (dx > 0 ? o - 1 : Math.min(0, o + 1)))
            }}>
            <div className="headline">Puffiness Score</div>
            <div className="row baseline" style={{ gap: 10, margin: '8px 0' }}>
              <span className="metric lg accent">{(sel?.value ?? series.average) != null ? Math.round((sel?.value ?? series.average)!) : '--'}</span>
              <span className="sub" style={{ fontSize: 20 }}>{sel ? (sel.start === sel.end ? fmt.shortDay(sel.start) : fmt.range(sel.start, sel.end)) : RANGE_LABEL[range][0]}</span>
            </div>
            {!sel && series.delta != null && <Delta value={series.delta} suffix={`points vs ${RANGE_LABEL[range][1]}`} />}
            <div style={{ marginTop: 14 }}>
              <ScoreBarChart points={series.points} goal={goals.dePuffMax} height={150} selected={selected} onSelect={setSelected} />
            </div>
            <p className="foot" style={{ margin: '10px 0 4px' }}>{fmt.range(series.start, series.end)} · Lower is better · Goal ≤{goals.dePuffMax}</p>
            <div className="row" style={{ justifyContent: 'space-between' }}>
              <button className="text-btn" style={{ fontWeight: 400, fontSize: 13 }} onClick={() => navigate('/goals')}>Goal: {goals.dePuffMax} or lower · Edit goal ›</button>
              <span className="row" style={{ gap: 4 }}>
                <button className="text-btn" aria-label="Earlier" onClick={() => { setSelected(undefined); setOffset(offset - 1) }}>‹</button>
                <button className="text-btn" aria-label="Later" disabled={offset >= 0} style={{ opacity: offset >= 0 ? 0.3 : 1 }} onClick={() => { setSelected(undefined); setOffset(offset + 1) }}>›</button>
              </span>
            </div>
          </div>
        </Card>
      )}

      <SectionHeader title="Photo timeline" action="See all" onAction={() => navigate('/scans')} />
      <div style={{ display: 'flex', gap: 8, overflowX: 'auto', margin: '0 -16px', padding: '0 16px', scrollbarWidth: 'none' }}>
        {recent.map((s) => (
          <button key={s.id} onClick={() => navigate(`/scans/${s.id}`)} style={{ flex: 'none', textAlign: 'left' }}
            aria-label={`${fmt.longDay(s.dayKey)}, score ${s.score}`}>
            <ScanPhoto scanID={s.id} thumb style={{ width: 118, height: 128 }} />
            <div style={{ fontSize: 13, fontWeight: 600, marginTop: 6 }}>{fmt.shortDay(s.dayKey)} · {s.score}</div>
          </button>
        ))}
        {!recent.length && <span className="sub">Your daily photos appear here.</span>}
      </div>
      <button className="btn secondary" disabled={d.scans.length < 2} onClick={() => navigate('/trends/time-lapse')}>Play time-lapse</button>

      <Card>
        <div style={{ fontSize: 20, fontWeight: 700 }}>Your days, connected</div>
        <p className="body sub" style={{ margin: '6px 0 8px' }}>Explore your calendar and the habits that show up alongside changes in your score.</p>
        <button className="text-btn row" style={{ fontWeight: 400, fontSize: 17, gap: 2 }} onClick={() => navigate('/trends/patterns')}>Calendar & correlations <ChevronRight size={18} /></button>
      </Card>
      <Disclaimer>Compare trends, not single numbers. Facial appearance naturally varies day to day.</Disclaimer>
    </Screen>
  )
}

function ScanSummaryCard({ scan }: { scan: ScanRecord }) {
  const { history } = useApp()
  return (
    <Card>
      <div className="row top">
        <div className="grow">
          <div className="foot">{fmt.longDay(scan.dayKey)} · {fmt.time(scan.capturedAt)}</div>
          <div className="metric lg accent" style={{ margin: '8px 0' }}>{scan.score}</div>
          <Delta value={history.deltaVsPrevious(scan.dayKey)} />
        </div>
        <ScanPhoto scanID={scan.id} thumb style={{ width: 96, height: 124 }} />
      </div>
      <div className="row" style={{ gap: 8, marginTop: 12 }}>{ZONES.map((z) => <ZoneTile key={z} zone={z} value={scan.zones[z]} />)}</div>
      {scan.tags.length > 0 && <div className="wrap" style={{ marginTop: 12 }}>{scan.tags.map((t) => <TagChip key={t} title={t} on />)}</div>}
      {scan.notes && <p className="body" style={{ margin: '12px 0 0' }}>{scan.notes}</p>}
    </Card>
  )
}

export function ScanDetail() {
  const { id } = useParams()
  const { d } = useApp()
  const navigate = useNavigate()
  const [confirm, setConfirm] = useState(false)
  const scan = d.scans.find((s) => s.id === id)
  if (!scan) return <Screen title="Scan" back><Card><span className="sub">Scan not found.</span></Card></Screen>
  return (
    <Screen title="Scan" subtitle={`${fmt.longDay(scan.dayKey)} · ${fmt.time(scan.capturedAt)}`} back>
      <ScanPhoto scanID={scan.id} radius={20} style={{ aspectRatio: '0.75' }} />
      <ScanSummaryCard scan={scan} />
      <UploadStatusCard state={store.uploadCardState(scan.id)} onAction={() => store.retryUploads()} />
      <button className="btn danger" onClick={() => setConfirm(true)}><Trash2 size={18} />Delete scan</button>
      {confirm && (
        <Alert title="Delete this scan?" message="It's removed from PuffyMeter. Files already in Google Drive stay there."
          buttons={[{ label: 'Cancel', onClick: () => setConfirm(false) },
            { label: 'Delete', destructive: true, onClick: () => { store.deleteScan(scan.id); navigate(-1) } }]} />
      )}
    </Screen>
  )
}

export function PhotoGrid() {
  const { d } = useApp()
  const navigate = useNavigate()
  return (
    <Screen title="All scans" back>
      {d.scans.length === 0 && <Card><span className="sub">Your daily photos appear here.</span></Card>}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 4 }}>
        {[...d.scans].reverse().map((s) => (
          <button key={s.id} onClick={() => navigate(`/scans/${s.id}`)} style={{ position: 'relative' }} aria-label={`${fmt.longDay(s.dayKey)}, score ${s.score}`}>
            <ScanPhoto scanID={s.id} thumb radius={6} style={{ aspectRatio: '0.75' }} />
            <span style={{ position: 'absolute', left: 4, bottom: 4, fontSize: 11, fontWeight: 600, color: '#fff', background: 'rgba(0,0,0,.45)', padding: '2px 4px', borderRadius: 4 }}>
              {fmt.shortDay(s.dayKey)} · {s.score}
            </span>
          </button>
        ))}
      </div>
    </Screen>
  )
}

export function TimeLapse() {
  const { d } = useApp()
  const frames = d.scans
  const [index, setIndex] = useState(Math.max(0, frames.length - 1))
  const [playing, setPlaying] = useState(false)
  const [speed, setSpeed] = useState(1)
  const [exporting, setExporting] = useState(false)
  const [video, setVideo] = useState<{ url: string; ext: string }>()
  const current = frames[index]
  useEffect(() => {
    if (!playing) return
    if (index >= frames.length - 1) setIndex(0)
    const t = setInterval(() => setIndex((i) => {
      if (i >= frames.length - 1) { setPlaying(false); return i }
      return i + 1
    }), 500 / speed)
    return () => clearInterval(t)
  }, [playing, speed]) // eslint-disable-line react-hooks/exhaustive-deps
  const exportVideo = async () => {
    setExporting(true)
    try { setVideo(await recordTimeLapse(frames)) } finally { setExporting(false) }
  }
  return (
    <Screen title="Photo time-lapse" subtitle="Your progress, in perspective" back>
      <ScanPhoto scanID={current?.id} radius={20} style={{ aspectRatio: '0.86' }} />
      {current && (
        <div className="row" style={{ justifyContent: 'space-between' }}>
          <span style={{ fontSize: 20 }}>{fmt.shortDay(current.dayKey)} · {fmt.time(current.capturedAt)}</span>
          <span className="accent" style={{ fontSize: 20, fontWeight: 700 }}>Score {current.score}</span>
        </div>
      )}
      <input type="range" min={0} max={Math.max(frames.length - 1, 1)} value={index} onChange={(e) => { setPlaying(false); setIndex(Number(e.target.value)) }}
        aria-label="Frame" style={{ width: '100%', accentColor: 'var(--accent)' }} />
      <div className="row" style={{ justifyContent: 'space-between' }}>
        <button className="chip" style={{ width: 44, justifyContent: 'center' }} onClick={() => setSpeed(speed === 0.5 ? 1 : speed === 1 ? 2 : 0.5)} aria-label="Playback speed">{speed === 0.5 ? '0.5×' : `${speed}×`}</button>
        <button aria-label="Previous photo" onClick={() => { setPlaying(false); setIndex(Math.max(0, index - 1)) }}><SkipBack size={26} /></button>
        <button aria-label={playing ? 'Pause' : 'Play'} onClick={() => setPlaying(!playing)}>{playing ? <Pause size={40} /> : <Play size={40} />}</button>
        <button aria-label="Next photo" onClick={() => { setPlaying(false); setIndex(Math.min(frames.length - 1, index + 1)) }}><SkipForward size={26} /></button>
        <span className="chip">{Math.min(index + 1, frames.length)} / {frames.length}</span>
      </div>
      <Disclaimer center>Same framing · Original photos · No smoothing</Disclaimer>
      {video
        ? <a className="btn secondary" href={video.url} download={`PuffyMeter-time-lapse.${video.ext}`}>Download time-lapse</a>
        : <button className="btn secondary" disabled={exporting || frames.length < 2} onClick={exportVideo}>{exporting ? 'Preparing…' : 'Export time-lapse'}</button>}
    </Screen>
  )
}

/** Records the scan photos to a video with MediaRecorder (WebM or MP4, whichever the browser supports). */
async function recordTimeLapse(scans: ScanRecord[]): Promise<{ url: string; ext: string } | undefined> {
  const canvas = document.createElement('canvas')
  canvas.width = 720
  canvas.height = 960
  const ctx = canvas.getContext('2d')!
  const mime = ['video/mp4', 'video/webm;codecs=vp9', 'video/webm'].find((m) => MediaRecorder.isTypeSupported?.(m))
  if (!mime) return undefined
  const stream = canvas.captureStream(30)
  const recorder = new MediaRecorder(stream, { mimeType: mime })
  const chunks: Blob[] = []
  recorder.ondataavailable = (e) => e.data.size && chunks.push(e.data)
  const done = new Promise<void>((r) => { recorder.onstop = () => r() })
  recorder.start()
  for (const s of scans) {
    const blob = await PhotoStore.get(PhotoStore.photoKey(s.id))
    if (!blob) continue
    const img = await createImageBitmap(blob)
    const scale = Math.max(canvas.width / img.width, canvas.height / img.height)
    ctx.drawImage(img, (canvas.width - img.width * scale) / 2, (canvas.height - img.height * scale) / 2, img.width * scale, img.height * scale)
    ctx.fillStyle = 'rgba(0,0,0,.45)'
    ctx.fillRect(0, canvas.height - 64, canvas.width, 64)
    ctx.fillStyle = '#fff'
    ctx.font = '600 28px -apple-system, sans-serif'
    ctx.fillText(`${fmt.shortDay(s.dayKey)} · Score ${s.score}`, 24, canvas.height - 22)
    img.close()
    await new Promise((r) => setTimeout(r, 250))
  }
  recorder.stop()
  await done
  return { url: URL.createObjectURL(new Blob(chunks, { type: mime })), ext: mime.includes('mp4') ? 'mp4' : 'webm' }
}

export function Patterns() {
  const { history, today, correlations } = useApp()
  const [month, setMonth] = useState<MonthKey>(today.slice(0, 7))
  const [selected, setSelected] = useState<DayKey>(today)
  const line = useMemo(() => {
    const s = history.stats(selected)
    const parts = [fmt.shortDay(selected), s.score != null ? `Score ${s.score}` : 'No scan']
    if (s.habits?.sleepHours != null) parts.push(`${fmt.hours(s.habits.sleepHours)} sleep`)
    if (s.habits?.waterLiters != null) parts.push(`${fmt.liters(s.habits.waterLiters)} water`)
    return parts.join(' · ')
  }, [history, selected])
  return (
    <Screen title="Your patterns" subtitle="Your progress, in perspective" back>
      <Card>
        <HeatmapCalendar month={month} history={history} today={today} selected={selected} onSelect={setSelected} onMonth={setMonth} />
        <p className="foot" style={{ margin: '12px 0 0' }}>{line}</p>
      </Card>
      <SectionHeader title="Habit correlations" />
      <p className="body sub" style={{ margin: 0 }}>Patterns in your last 30 days. Associations don't establish what caused a change.</p>
      {correlations.map((c) => <CorrelationCard key={c.factor} c={c} />)}
      <Disclaimer>These insights are for cosmetic wellness, not health assessment or medical advice.</Disclaimer>
    </Screen>
  )
}
