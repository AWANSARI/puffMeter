import { Archive, CloudAlert, CloudCheck, CloudOff, CloudUpload, Droplet, Flame, HardDrive, Minus, Moon, Plus, Smartphone, Sparkles, TriangleAlert, Utensils } from 'lucide-react'
import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { fmt } from '../domain/dates'
import { RingMath } from '../domain/engine'
import { trendSeries } from '../domain/progress'
import { ALCOHOL_LEVELS, ALCOHOL_TITLES, capitalize, HABIT_TITLES, HABITS, SALT_LEVELS, ZONES, ZONE_TITLES, type HabitKind } from '../domain/types'
import { store, useApp } from '../store/appStore'
import { Card, Delta, Disclaimer, HabitChip, haptic, InsightCard, ScanPhoto, Screen, SectionHeader, Segmented, Sheet } from '../ui/components'
import { ScoreBarChart, StreakRow } from '../ui/charts'
import { ActivityRings, RingLegend } from '../ui/rings'

export function Summary() {
  const app = useApp()
  const { todayStats: stats, history, today, streak, settings, folder, snap } = app
  const navigate = useNavigate()
  const [logging, setLogging] = useState<HabitKind>()
  const scan = stats.primaryScan
  const week = trendSeries('W', history, today)
  const zoneDeltas = scan ? history.zoneDeltaVsPrevious(scan.dayKey) : undefined
  const upload = scan ? store.uploadCardState(scan.id) : undefined
  // Only-in-this-browser data with no recent backup: browsers (especially Safari) can clear it.
  const lastBackup = settings.lastBackupAt ? new Date(settings.lastBackupAt).getTime() : 0
  const needsBackup = !snap.demo && history.scans.length >= 3 && snap.folder.kind !== 'connected' && !folder
    && Date.now() - lastBackup > 7 * 86_400_000
  return (
    <Screen title="Summary" subtitle={fmt.longDay(today)} action={<button className="action" onClick={() => navigate('/goals')}>Edit</button>}>
      {settings.drive.kind === 'needsReconnect' && (
        <Banner icon={<CloudAlert size={20} />} text="Google Drive needs to reconnect" action="Reconnect" onClick={() => navigate('/profile/drive')} />
      )}
      {settings.drive.kind === 'notConnected' && settings.onboardingStep === 'complete' && (
        <Banner icon={<HardDrive size={20} />} text="Back up your scans to Google Drive" action="Connect" color="var(--link)" onClick={() => navigate('/profile/drive')} />
      )}

      {needsBackup && (
        <Banner icon={<Archive size={20} />} text="Your data is only in this browser. Save a backup so it's never lost." action="Back up"
          color="var(--link)" onClick={() => navigate('/profile/storage')} />
      )}

      <Card>
        <div className="row" style={{ gap: 20, flexWrap: 'wrap' }}>
          <ActivityRings progress={stats.rings} size="card" />
          <RingLegend stats={stats} />
        </div>
        <p className="foot" style={{ margin: '14px 0 0' }}>{RingMath.caption(stats)}</p>
      </Card>

      {scan ? (
        <>
          <Card onClick={() => navigate(`/scans/${scan.id}`)} style={{ cursor: 'pointer' }}>
            <div className="row top">
              <div className="stack grow" style={{ gap: 4 }}>
                <span className="headline">Puffiness Score</span>
                <span className="metric xl accent" style={{ margin: '8px 0' }} aria-label={`Score ${scan.score}`}>{scan.score}</span>
                <Delta value={history.deltaVsPrevious(scan.dayKey)} />
                <span className="foot">0–100 · Lower is better</span>
                <span className="foot">Scanned at {fmt.time(scan.capturedAt)}</span>
                {scan.lowConfidence && <span className="foot row" style={{ color: 'var(--warning)', gap: 4 }}><TriangleAlert size={14} />Lower confidence</span>}
                {upload && <SyncLabel state={upload.kind} folderName={folder?.name} />}
              </div>
              <ScanPhoto scanID={scan.id} thumb style={{ width: 126, height: 162, flex: 'none' }} />
            </div>
          </Card>
          <SectionHeader title="Face zones" />
          <Card flush>
            <div style={{ padding: '8px 0' }}>
              {ZONES.map((z) => {
                const delta = zoneDeltas?.[z]
                return (
                  <div key={z} className="row" style={{ padding: '8px 16px' }}>
                    <span className="body grow">{ZONE_TITLES[z]}</span>
                    <span style={{ fontSize: 22, fontWeight: 700, fontVariantNumeric: 'tabular-nums' }}>{scan.zones[z]}</span>
                    <span style={{ width: 40, textAlign: 'right' }}>{delta ? <Delta value={delta} suffix="" size={12} /> : null}</span>
                  </div>
                )
              })}
            </div>
          </Card>
        </>
      ) : (
        <Card>
          <div className="headline">{history.scans.length ? "Today's scan" : 'Set your baseline'}</div>
          <p className="sub" style={{ margin: '6px 0 12px' }}>{history.scans.length ? "Take today's scan to see your Puffiness Score." : 'Take your baseline scan to start tracking.'}</p>
          {history.previousScan(today) && <p className="foot" style={{ marginTop: -6 }}>Last score: {history.previousScan(today)!.score}</p>}
          <button className="btn primary" onClick={() => navigate('/scan')}>Scan now</button>
        </Card>
      )}

      <SectionHeader title="Last 7 days" action="Trends" onAction={() => navigate('/trends')} />
      <Card>
        <div className="row baseline" style={{ gap: 8, marginBottom: 14, flexWrap: 'wrap' }}>
          <span className="metric md accent">{week.average != null ? Math.round(week.average) : '--'}</span>
          <span className="body sub">average{week.delta != null ? ` · ${week.delta === 0 ? 'same as' : week.delta < 0 ? `↓ ${-week.delta} from` : `↑ ${week.delta} from`} last week` : ''}</span>
        </div>
        <ScoreBarChart points={week.points} />
        <p className="foot" style={{ margin: '10px 0 0' }}>{fmt.range(week.start, week.end)} · Lower is better</p>
      </Card>

      <Card>
        <div className="row" style={{ marginBottom: 12 }}>
          <Flame size={22} color="var(--accent)" />
          <span style={{ fontSize: 20, fontWeight: 700 }}>{streak > 0 ? `${streak}-day scan streak` : 'Start a streak'}</span>
        </div>
        <StreakRow days={app.lastSeven} />
        <p className="foot" style={{ margin: '12px 0 0' }}>
          {streak === 0 ? 'Scan tomorrow morning to begin.' : streak < 3 ? 'A good start. Same time tomorrow?' : streak < 7 ? 'Your morning routine is building.' : 'Your morning routine is taking shape.'}
        </p>
      </Card>

      <SectionHeader title="Daily insights" />
      {app.dailyInsights.length ? app.dailyInsights.map((i) => (
        <InsightCard key={i.id} icon={i.icon === 'sleep' ? <Moon size={22} /> : i.icon === 'water' ? <Droplet size={22} /> : i.icon ? <Utensils size={22} /> : undefined}
          title={i.title} body={i.body} footnote={i.footnote} />
      )) : <InsightCard icon={<Sparkles size={22} />} title="Insights are on the way" body="Insights appear after a week of scans." />}

      <SectionHeader title="Quick log" />
      <div className="wrap">
        {HABITS.map((h) => <HabitChip key={h} kind={h} log={app.todayLog} waterGoal={stats.goals.waterGoalLiters} onClick={() => setLogging(h)} />)}
      </div>
      <Disclaimer>Cosmetic wellness only. Scores can vary with lighting, expression, and daily changes.</Disclaimer>
      {snap.demo && <Disclaimer>Demo mode: sample data on Oct 8, 2026. Nothing is saved.</Disclaimer>}
      {logging && <QuickLogSheet kind={logging} onClose={() => setLogging(undefined)} />}
    </Screen>
  )
}

function Banner({ icon, text, action, onClick, color = 'var(--accent)' }: { icon: React.ReactNode; text: string; action: string; onClick: () => void; color?: string }) {
  return (
    <div className="card row" style={{ boxShadow: `inset 0 0 0 1px ${color}55` }}>
      <span style={{ color }}>{icon}</span>
      <span className="grow sub" style={{ color: 'var(--label)' }}>{text}</span>
      <button className="text-btn" style={{ color }} onClick={onClick}>{action}</button>
    </div>
  )
}

function SyncLabel({ state, folderName }: { state: string; folderName?: string }) {
  const map: Record<string, [React.ReactNode, string, string]> = {
    saved: [<CloudCheck size={16} />, `Saved in ${folderName ?? 'Google Drive'}`, 'var(--label-2)'],
    uploading: [<CloudUpload size={16} />, 'Uploading to Google Drive', 'var(--habits)'],
    failed: [<CloudAlert size={16} />, 'Upload failed · Tap to retry', 'var(--accent)'],
    queued: [<CloudOff size={16} />, 'Waiting to sync', 'var(--label-2)'],
    localOnly: [<Smartphone size={16} />, 'Saved on this device', 'var(--label-2)'],
  }
  const [icon, text, color] = map[state]
  return <span className="foot row" style={{ gap: 6, color, marginTop: 6 }}>{icon}{text}</span>
}

export function QuickLogSheet({ kind, onClose }: { kind: HabitKind; onClose: () => void }) {
  const { todayLog, goals } = useApp()
  const [water, setWater] = useState(todayLog?.waterLiters ?? 0)
  const [sleep, setSleep] = useState(todayLog?.sleepHours ?? 7.5)
  const [salt, setSalt] = useState(todayLog?.salt ?? 'low')
  const [alcohol, setAlcohol] = useState(todayLog?.alcohol ?? 'none')
  const logged = kind === 'water' ? todayLog?.waterLiters != null : kind === 'sleep' ? todayLog?.sleepHours != null : kind === 'salt' ? !!todayLog?.salt : !!todayLog?.alcohol
  const save = () => {
    haptic(10)
    store.logHabit(kind === 'water' ? { waterLiters: water } : kind === 'sleep' ? { sleepHours: sleep } : kind === 'salt' ? { salt } : { alcohol })
    onClose()
  }
  const stepBtn = (icon: React.ReactNode, label: string, fn: () => void) => (
    <button aria-label={label} onClick={() => { haptic(6); fn() }} style={{ width: 52, height: 52, borderRadius: 26, background: 'var(--card-elevated)', display: 'grid', placeItems: 'center' }}>{icon}</button>
  )
  return (
    <Sheet title={HABIT_TITLES[kind]} onClose={onClose}
      trailing={logged ? <button className="link-btn" style={{ color: 'var(--destructive)' }} onClick={() => { store.clearHabit(kind); onClose() }}>Clear</button> : undefined}>
      <div className="stack lg" style={{ padding: '12px 0' }}>
        {kind === 'water' && (
          <>
            <div className="center"><div className="metric lg accent">{fmt.liters(water)}</div><div className="sub">of {fmt.liters(goals.waterGoalLiters)} today</div></div>
            <div className="row" style={{ justifyContent: 'center' }}>
              {stepBtn(<Minus />, 'Decrease', () => setWater(Math.max(0, +(water - 0.25).toFixed(2))))}
              <button className="chip" onClick={() => setWater(+(water + 0.25).toFixed(2))}>+250 ml</button>
              <button className="chip" onClick={() => setWater(+(water + 0.5).toFixed(2))}>+500 ml</button>
              {stepBtn(<Plus />, 'Increase', () => setWater(+(water + 0.25).toFixed(2)))}
            </div>
          </>
        )}
        {kind === 'sleep' && (
          <>
            <div className="center"><div className="metric lg accent">{fmt.hours(sleep)}</div><div className="sub">Last night</div></div>
            <div className="row" style={{ justifyContent: 'center' }}>
              {stepBtn(<Minus />, 'Decrease', () => setSleep(Math.max(0, sleep - 0.5)))}
              {stepBtn(<Plus />, 'Increase', () => setSleep(Math.min(14, sleep + 0.5)))}
            </div>
          </>
        )}
        {kind === 'salt' && (
          <>
            <span className="headline">How salty was last evening's meal?</span>
            <Segmented options={SALT_LEVELS.map(capitalize)} value={capitalize(salt)} onChange={(v) => setSalt(v.toLowerCase() as typeof salt)} />
          </>
        )}
        {kind === 'alcohol' && (
          <>
            <span className="headline">Any drinks last evening?</span>
            <Segmented options={ALCOHOL_LEVELS.map((a) => ALCOHOL_TITLES[a])} value={ALCOHOL_TITLES[alcohol]}
              onChange={(v) => setAlcohol(ALCOHOL_LEVELS.find((a) => ALCOHOL_TITLES[a] === v)!)} />
          </>
        )}
        <button className="btn primary" onClick={save}>Save</button>
      </div>
    </Sheet>
  )
}
