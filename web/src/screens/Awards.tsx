import { Flame, Share2 } from 'lucide-react'
import { useEffect, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { dayKeyOf, fmt } from '../domain/dates'
import { ALL_AWARDS, Awards as AwardEngine, CHALLENGES, Challenges, type AwardDefinition } from '../domain/progress'
import { GOAL_RANGES } from '../domain/types'
import { awardByID, store, useApp } from '../store/appStore'
import { Card, Disclaimer, haptic, ProgressBar, Screen, SectionHeader, Sheet } from '../ui/components'
import { AwardBadge } from '../ui/badges'
import { ChallengeCard, Confetti, GoalStepperCard } from '../ui/cards'
import { ActivityRings } from '../ui/rings'

type Filter = 'all' | 'streaks' | 'habits' | 'challenges'

export function Awards() {
  const { d, awardContext, today } = useApp()
  const navigate = useNavigate()
  const [filter, setFilter] = useState<Filter>('all')
  const earned = (id: string) => d.earnedAwards.find((e) => e.awardID === id)
  const latest = [...d.earnedAwards].sort((a, b) => b.earnedAt.localeCompare(a.earnedAt))[0]
  const latestDef = latest && awardByID(latest.awardID)
  const month = today.slice(0, 7)
  const visible = ALL_AWARDS.filter((a) => {
    if (filter !== 'all' && a.category !== filter) return false
    if (a.metric.kind === 'challenge') {
      const id = a.metric.id
      const c = CHALLENGES.find((x) => x.id === id)
      if (c && c.month !== month && !earned(a.id)) return false
    }
    return true
  }).sort((a, b) => {
    const ea = earned(a.id), eb = earned(b.id)
    if (ea && eb) return ea.earnedAt.localeCompare(eb.earnedAt)
    if (ea) return -1
    if (eb) return 1
    return AwardEngine.progress(b, awardContext).fraction - AwardEngine.progress(a, awardContext).fraction
  })
  return (
    <Screen title="Awards" subtitle="Small wins. Lasting routines.">
      {latestDef && (
        <Card>
          <div className="row" style={{ gap: 16 }}>
            <AwardBadge award={latestDef} locked={false} size={92} />
            <div className="stack" style={{ gap: 4 }}>
              <span className="eyebrow">Just earned</span>
              <span style={{ fontSize: 22, fontWeight: 700 }}>{latestDef.title}</span>
              <span className="body sub">{latestDef.id.startsWith('streak') ? "You showed up every morning. That's worth celebrating." : latestDef.celebration}</span>
            </div>
          </div>
        </Card>
      )}
      <div className="row" style={{ gap: 8, overflowX: 'auto', scrollbarWidth: 'none' }}>
        {(['all', 'streaks', 'habits', 'challenges'] as Filter[]).map((f) => (
          <button key={f} className={`chip${filter === f ? ' solid' : ''}`} aria-pressed={filter === f} onClick={() => setFilter(f)}>
            {f === 'all' ? 'All awards' : f[0].toUpperCase() + f.slice(1)}
          </button>
        ))}
      </div>
      <SectionHeader title="Your collection" />
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
        {visible.map((a) => {
          const e = earned(a.id)
          const p = AwardEngine.progress(a, awardContext)
          const sub = e ? (dayKeyOf(new Date(e.earnedAt)) === today ? 'Earned today' : fmt.dateMedium(e.earnedAt))
            : p.current === 0 || a.metric.kind === 'perfectWeek' ? a.requirement : `${p.current} / ${p.target} ${a.unit}`
          return (
            <button key={a.id} className="card" onClick={() => navigate(`/awards/${a.id}`)}
              style={{ minHeight: 196, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8, padding: '16px 8px' }}
              aria-label={`${a.title}, ${e ? 'earned' : 'locked'}. ${sub}`}>
              <AwardBadge award={a} locked={!e} size={84} />
              <span className="headline">{a.title}</span>
              <span className="foot center">{sub}</span>
            </button>
          )
        })}
      </div>
      <Disclaimer center>Earned through consistency, not a perfect score.</Disclaimer>
    </Screen>
  )
}

export function AwardDetail() {
  const { id } = useParams()
  const { d, awardContext } = useApp()
  const [tilt, setTilt] = useState({ x: 0, y: 0 })
  const award = ALL_AWARDS.find((a) => a.id === id)
  if (!award) return <Screen title="Award" back><Card>Not found.</Card></Screen>
  const earned = d.earnedAwards.find((e) => e.awardID === award.id)
  const p = AwardEngine.progress(award, awardContext)
  return (
    <Screen title="" back>
      <div className="stack lg center" style={{ alignItems: 'center' }}>
        <div style={{ transform: `perspective(600px) rotateY(${tilt.x}deg) rotateX(${tilt.y}deg)`, transition: tilt.x === 0 ? 'transform .5s cubic-bezier(.3,1.6,.5,1)' : undefined, touchAction: 'none' }}
          onPointerMove={(e) => { if (!e.buttons) return; const r = e.currentTarget.getBoundingClientRect(); setTilt({ x: ((e.clientX - r.left) / r.width - 0.5) * 60, y: -((e.clientY - r.top) / r.height - 0.5) * 30 }) }}
          onPointerUp={() => setTilt({ x: 0, y: 0 })} onPointerLeave={() => setTilt({ x: 0, y: 0 })}>
          <AwardBadge award={award} locked={!earned} size={200} />
        </div>
        <h1 className="large-title">{award.title}</h1>
        {earned ? (
          <>
            <span className="sub">Earned {fmt.dateLong(earned.earnedAt)}</span>
            <p className="body">{award.celebration}</p>
            <ShareButton text={`I earned the ${award.title} award in PuffyMeter.`} />
          </>
        ) : (
          <>
            <p className="body sub">{award.requirement}</p>
            {award.target > 1 && (
              <div style={{ width: '70%' }} className="stack">
                <ProgressBar value={p.fraction} color="var(--accent)" />
                <span className="foot">{p.current} / {p.target} {award.unit}</span>
              </div>
            )}
          </>
        )}
      </div>
    </Screen>
  )
}

function ShareButton({ text }: { text: string }) {
  const [copied, setCopied] = useState(false)
  const share = async () => {
    try {
      if (navigator.share) await navigator.share({ text, url: location.origin })
      else { await navigator.clipboard.writeText(`${text} ${location.origin}`); setCopied(true) }
    } catch { /* cancelled */ }
  }
  return <button className="btn secondary" onClick={share}><Share2 size={18} />{copied ? 'Copied' : 'Share'}</button>
}

/** "NEW AWARD" sheet; queued awards show one after another. */
export function AwardUnlockSheet({ award }: { award: AwardDefinition }) {
  const { d } = useApp()
  const earned = d.earnedAwards.find((e) => e.awardID === award.id)
  useEffect(() => { haptic([20, 40, 20]) }, [award.id])
  return (
    <Sheet onClose={() => store.dequeueAward()} cancel={null}>
      <div className="stack lg center" style={{ alignItems: 'center', paddingTop: 12 }}>
        <span className="eyebrow">New award</span>
        <div style={{ position: 'relative', overflow: 'hidden', borderRadius: '50%', animation: 'flip .8s cubic-bezier(.2,.9,.3,1.2)' }}>
          <AwardBadge award={award} locked={false} size={128} />
          <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(100deg, transparent 35%, rgba(255,255,255,.55) 50%, transparent 65%)', animation: 'shine 1.1s .8s ease both' }} />
        </div>
        <h2 style={{ fontSize: 28, margin: 0 }}>{award.tagline}</h2>
        <p className="body sub" style={{ margin: 0 }}>{award.celebration}</p>
        {earned && <span className="foot">{award.title} · {fmt.dateLong(earned.earnedAt)}</span>}
        <button className="btn primary" onClick={() => store.dequeueAward()}>Keep it going</button>
      </div>
    </Sheet>
  )
}

/** Full-screen celebration when all three rings close for the first time in a day. */
export function AllRingsClosed() {
  const { todayStats, streak, today } = useApp()
  const navigate = useNavigate()
  const [rings, setRings] = useState({ dePuff: 0, scan: 0, habits: 0 })
  const [celebrate, setCelebrate] = useState(false)
  useEffect(() => {
    const t = todayStats.rings
    const steps = [() => setRings((r) => ({ ...r, dePuff: t.dePuff })), () => setRings((r) => ({ ...r, scan: t.scan })),
      () => setRings((r) => ({ ...r, habits: t.habits })), () => { setCelebrate(true); haptic([30, 50, 30]) }]
    const timers = steps.map((fn, i) => setTimeout(fn, 250 + i * 500))
    return () => timers.forEach(clearTimeout)
  }, []) // eslint-disable-line react-hooks/exhaustive-deps
  const close = () => { store.dismissAllRings(); navigate('/') }
  return (
    <div className="fullscreen" role="dialog" aria-modal="true" aria-label="All rings closed">
      <div className="inner screen no-tabs center" style={{ alignItems: 'center', justifyContent: 'center', minHeight: '100dvh' }}>
        <span className="eyebrow" style={{ color: 'var(--scan)' }}>{fmt.longDay(today)}</span>
        <ActivityRings progress={rings} size="hero" />
        <h1 className="hero-headline">{'All rings.\nAll you.'}</h1>
        <p className="body sub" style={{ margin: 0 }}>You reached your De-Puff goal, scanned, and checked in with all four habits.</p>
        <Card style={{ width: '100%', textAlign: 'left' }}>
          <div className="row"><Flame size={36} color="var(--accent)" />
            <div><div className="headline">{streak} days of showing up</div><div className="foot">A little consistency goes a long way.</div></div></div>
        </Card>
        <button className="btn primary" onClick={close}>Back to Summary</button>
        <ShareButton text={`All three rings closed today in PuffyMeter${todayStats.score != null ? ` · Puffiness Score ${todayStats.score}` : ''}.`} />
        {celebrate && <Confetti />}
      </div>
    </div>
  )
}

// MARK: Goals & challenges

export function Goals() {
  const { goals } = useApp()
  const navigate = useNavigate()
  const [dePuff, setDePuff] = useState(goals.dePuffMax)
  const [scans, setScans] = useState(goals.scansPerDay)
  const [habits, setHabits] = useState(goals.habitsPerDay)
  return (
    <Screen title="Your daily goals" subtitle="PuffyMeter" back tabs={false}>
      <p className="body sub" style={{ margin: 0 }}>Make your rings work for you. Adjust your goals as your routine evolves.</p>
      <GoalStepperCard kind="dePuff" value={dePuff} range={GOAL_RANGES.dePuff} onChange={setDePuff} unit="Score or lower"
        message="Close this ring when your score meets your goal. Lower is better." />
      <GoalStepperCard kind="scan" value={scans} range={GOAL_RANGES.scans} onChange={setScans} unit={scans === 1 ? 'Scan per day' : 'Scans per day'}
        message="One consistent morning scan is enough." />
      <GoalStepperCard kind="habits" value={habits} range={GOAL_RANGES.habits} onChange={setHabits} unit="Check-ins per day"
        message="Water, sleep, salt, and alcohol. Log honestly, not perfectly." />
      <button className="btn primary" onClick={() => { store.updateGoals({ dePuffMax: dePuff, scansPerDay: scans, habitsPerDay: habits, waterGoalLiters: goals.waterGoalLiters }); haptic(15); navigate(-1) }}>Save goals</button>
      <Disclaimer center>Goals support your routine. They are not medical targets.</Disclaimer>
    </Screen>
  )
}

export function ChallengesScreen() {
  const { challengeStatuses, today, history, d } = useApp()
  const [showAll, setShowAll] = useState(false)
  const month = today.slice(0, 7)
  const next = Challenges.forMonth(nextMonth(month))
  const nextJoin = next.find((c) => c.requiresJoin) ?? next[0]
  return (
    <Screen title={`${fmt.monthName(month)} challenges`} subtitle="PuffyMeter" back>
      {!challengeStatuses.length && <Card><span className="sub">New challenges open on the first of each month.</span></Card>}
      {challengeStatuses.map((s, i) => <ChallengeCard key={s.definition.id} status={s} hero={i === 0} onJoin={() => store.joinChallenge(s.definition.id)} />)}
      {nextJoin && (
        <Card>
          <div className="headline">Next month: {nextJoin.title}</div>
          <p className="body sub" style={{ margin: '6px 0 0' }}>{fmt.monthName(nextJoin.month)}'s {nextJoin.title.toLowerCase()} challenge opens on {fmt.shortDay(`${nextJoin.month}-01`)}.</p>
        </Card>
      )}
      <button className="btn secondary" onClick={() => setShowAll(true)}>View all challenges</button>
      {showAll && (
        <Sheet title="All challenges" onClose={() => setShowAll(false)} cancel="Done">
          <div className="list">
            {CHALLENGES.map((c) => {
              const s = Challenges.status(c, history, d.challengeRecords, today)
              return (
                <div key={c.id} className="list-row">
                  <div className="grow"><div>{c.title}</div><div className="foot">{fmt.monthYear(c.month)} · {c.month > month ? `Opens ${fmt.shortDay(`${c.month}-01`)}` : `${s.progress} / ${c.target}${s.complete ? ' · Complete' : ''}`}</div></div>
                </div>
              )
            })}
          </div>
        </Sheet>
      )}
    </Screen>
  )
}

function nextMonth(m: string): string {
  const [y, mm] = m.split('-').map(Number)
  const d = new Date(y, mm, 1)
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`
}
