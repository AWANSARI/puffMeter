import { Bell, Camera, Check, ChevronLeft, ChevronRight, FileText, Folder, FolderCheck, FolderLock, FolderPlus, HardDrive, Image, Lock, Search, ShieldCheck } from 'lucide-react'
import { useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { fmt } from '../domain/dates'
import { DriveNaming } from '../domain/export'
import type { DriveFolderRef } from '../domain/types'
import type { DriveFolder } from '../services/drive'
import { cameraPermission, cameraSupported, preloadFaceModel, requestCamera } from '../services/faceCamera'
import { AuthError, GoogleAuth } from '../services/googleAuth'
import { drawSampleFace } from '../services/sampleFace'
import { store, useApp } from '../store/appStore'
import { Card, Delta, Disclaimer, Screen, Sheet, Toggle } from '../ui/components'
import { ActivityRings } from '../ui/rings'

const LOGO_RINGS = { dePuff: 1, scan: 1, habits: 0.75 }

// MARK: Welcome

const PAGES = [
  { eyebrow: 'Meet PuffyMeter', headline: 'A fresh perspective.\nEvery morning.', body: "One quick scan. A clearer picture of your face's everyday changes." },
  { eyebrow: 'Make it a daily ritual', headline: 'Small habits.\nVisible progress.', body: 'Scan, check in with your habits, and work toward your personal De-Puff goal.' },
  { eyebrow: 'Private by design', headline: 'Your face.\nYour folder.', body: 'Keep your daily photos in a Google Drive folder you choose. You stay in control.' },
]

export function Welcome() {
  const navigate = useNavigate()
  const [page, setPage] = useState(0)
  const touch = useRef(0)
  const finish = () => { store.setOnboardingStep('signIn'); navigate('/signin') }
  const p = PAGES[page]
  return (
    <main className="screen no-tabs" style={{ minHeight: '100dvh' }}
      onTouchStart={(e) => { touch.current = e.touches[0].clientX }}
      onTouchEnd={(e) => {
        const dx = e.changedTouches[0].clientX - touch.current
        if (dx < -50 && page < 2) setPage(page + 1)
        if (dx > 50 && page > 0) setPage(page - 1)
      }}>
      <div className="row">
        <ActivityRings progress={LOGO_RINGS} size="logo" animate={false} />
        <span style={{ fontSize: 20, fontWeight: 600 }} className="grow">PuffyMeter</span>
        <button className="link-btn" style={{ color: 'var(--accent)' }} onClick={finish}>Skip</button>
      </div>
      <div style={{ flex: 1, display: 'grid', placeItems: 'center', minHeight: 340 }} key={page}>
        {page === 0 && <WelcomeScoreArt />}
        {page === 1 && <ActivityRings progress={LOGO_RINGS} size="hero" />}
        {page === 2 && (
          <div className="stack lg" style={{ alignItems: 'center', width: '100%' }}>
            <FolderLock size={84} strokeWidth={1} color="var(--accent)" />
            <Card style={{ width: '80%' }}>
              <div className="headline">PuffyMeter Daily</div>
              <div className="foot">My Drive / PuffyMeter Daily</div>
              <div className="foot good">Only this folder is connected</div>
            </Card>
          </div>
        )}
      </div>
      <div className="eyebrow">{p.eyebrow}</div>
      <h1 className="hero-headline">{p.headline}</h1>
      <p className="body sub" style={{ fontSize: 20, margin: 0 }}>{p.body}</p>
      <div className="row" style={{ justifyContent: 'center', gap: 8, margin: '12px 0' }} aria-label={`Page ${page + 1} of 3`}>
        {PAGES.map((_, i) => <span key={i} style={{ width: 8, height: 8, borderRadius: 4, background: i === page ? 'var(--accent)' : 'var(--label-3)' }} />)}
      </div>
      <button className="btn primary" onClick={() => (page < 2 ? setPage(page + 1) : finish())}>{page < 2 ? 'Continue' : 'Get started'}</button>
      <Disclaimer center>Cosmetic wellness tracking. Not a medical diagnosis.</Disclaimer>
    </main>
  )
}

function WelcomeScoreArt() {
  const ref = useRef<HTMLCanvasElement>(null)
  useEffect(() => {
    const c = ref.current!
    c.width = 540
    c.height = 590
    drawSampleFace(c.getContext('2d')!, 540, 590, 0.25)
  }, [])
  return (
    <div style={{ position: 'relative', width: '100%', display: 'flex', justifyContent: 'center', paddingBottom: 40 }}
      role="img" aria-label="Example: Puffiness Score 32, down 8 from yesterday">
      <canvas ref={ref} style={{ width: '72%', aspectRatio: '0.92', borderRadius: 20 }} />
      <div className="card row" style={{ position: 'absolute', bottom: 0, left: '12%', padding: '12px 18px' }}>
        <span className="metric lg accent">32</span>
        <div className="stack" style={{ gap: 2 }}>
          <span className="headline">Looking ahead</span>
          <Delta value={-8} suffix="from yesterday" />
          <span className="foot">Puffiness Score</span>
        </div>
      </div>
    </div>
  )
}

// MARK: Sign in

export function SignIn() {
  const navigate = useNavigate()
  const [error, setError] = useState<string>()
  const [busy, setBusy] = useState(false)
  const google = async () => {
    setBusy(true)
    setError(undefined)
    try {
      const profile = await GoogleAuth.signIn()
      store.signedIn(profile)
      navigate('/drive')
    } catch (e) {
      setError(e instanceof AuthError ? e.userMessage : 'Sign-in didn’t complete. Please try again.')
    } finally {
      setBusy(false)
    }
  }
  const local = () => { store.useLocally(); navigate('/permissions') }
  const demo = store.getSnapshot().demo
  return (
    <main className="screen no-tabs center" style={{ alignItems: 'center', paddingTop: 'calc(env(safe-area-inset-top) + 48px)' }}>
      <ActivityRings progress={LOGO_RINGS} size="card" />
      <h1 style={{ fontSize: 34, margin: '12px 0 0' }}>PuffyMeter</h1>
      <h2 style={{ fontSize: 22, margin: 0 }}>Your daily check-in,<br />all in one place.</h2>
      <p className="sub" style={{ fontSize: 17, margin: 0 }}>Sign in to save your progress and connect your private photo folder.</p>
      {error && <p className="foot accent" role="alert">{error}</p>}
      <div className="stack lg" style={{ width: '100%', marginTop: 12 }}>
        {(GoogleAuth.configured || demo) && (
          <button className="btn primary" disabled={busy} onClick={demo ? () => { store.signedIn({ displayName: 'Alex Morgan', email: 'alex.morgan@gmail.com', provider: 'google' }); navigate('/drive') } : google}>
            <span style={{ width: 22, height: 22, borderRadius: 11, background: '#fff', color: '#4285F4', display: 'grid', placeItems: 'center', fontWeight: 800, fontSize: 14 }}>G</span>
            {busy ? 'Signing in…' : 'Continue with Google'}
          </button>
        )}
        <button className={`btn ${GoogleAuth.configured || demo ? 'secondary' : 'primary'}`} onClick={local}>Use without an account</button>
        {!GoogleAuth.configured && !demo && <p className="foot">Scans stay in this browser. You can connect Google Drive later in Profile once it's set up.</p>}
      </div>
      <Card style={{ textAlign: 'left', width: '100%' }}>
        <div className="row"><ShieldCheck size={22} color="var(--scan)" /><span className="headline">Your privacy comes first</span></div>
        <p className="foot" style={{ margin: '6px 0 0' }}>Photos stay in the Drive folder you choose. Your face is never used for advertising, and analysis runs in your browser.</p>
      </Card>
      <p className="foot">By continuing, you agree to our <a href="/privacy.html">Terms of Service</a><br />and <a href="/privacy.html">Privacy Policy</a>.</p>
    </main>
  )
}

// MARK: Connect Google Drive

export function ConnectDrive() {
  const navigate = useNavigate()
  const { settings } = useApp()
  const [error, setError] = useState<string>()
  const [confirmSkip, setConfirmSkip] = useState(false)
  const demo = store.getSnapshot().demo
  const connect = async () => {
    setError(undefined)
    try {
      if (!demo) await GoogleAuth.requestDriveAccess(settings.profile?.email)
      store.setOnboardingStep('driveFolderPicker')
      navigate('/drive/folders')
    } catch (e) {
      setError(e instanceof AuthError ? e.userMessage : "Couldn't connect to Google Drive. Please try again.")
    }
  }
  const rows: [React.ReactNode, string, string][] = [
    [<Image size={20} color="var(--accent)" />, 'Daily scan photos', 'JPG'],
    [<FileText size={20} color="var(--accent)" />, 'Scores and notes', 'JSON'],
    [<Lock size={20} color="var(--label-2)" />, 'Your other files', 'No access'],
  ]
  return (
    <Screen title="Connect Google Drive" subtitle="PuffyMeter" back="/signin" tabs={false}>
      <div className="center" style={{ padding: '16px 0' }}><FolderLock size={72} strokeWidth={1} color="var(--link)" /></div>
      <h2 className="hero-headline">{'One folder.\nNothing else.'}</h2>
      <p className="body sub" style={{ margin: 0 }}>PuffyMeter can create and save photos only in the folder you select. It can't browse the rest of your Drive.</p>
      <div className="list">
        {rows.map(([icon, title, value]) => (
          <div className="list-row" key={title}><span className="icon">{icon}</span>{title}<span className="value">{value}</span></div>
        ))}
      </div>
      <Disclaimer>You can disconnect or change folders anytime in Profile. Deleting PuffyMeter won't delete your Drive photos.</Disclaimer>
      {error && <p className="foot accent" role="alert">{error}</p>}
      <button className="btn primary" onClick={connect}>Choose Drive folder</button>
      <button className="link-btn foot" style={{ alignSelf: 'center' }} onClick={() => setConfirmSkip(true)}>Not now</button>
      {confirmSkip && (
        <Sheet title="Continue without Drive?" onClose={() => setConfirmSkip(false)}>
          <p className="body sub">Without Drive, scans are stored only in this browser. You can connect later in Profile.</p>
          <button className="btn primary" onClick={() => { store.skipDrive(); store.setOnboardingStep('permissions'); navigate('/permissions') }}>Keep scans on this device</button>
        </Sheet>
      )}
    </Screen>
  )
}

// MARK: Folder picker (also used from Profile)

export function FolderPicker({ onChoose, back = '/drive' }: { onChoose: (f: DriveFolderRef) => void; back?: string }) {
  const { settings } = useApp()
  const [trail, setTrail] = useState<DriveFolder[]>([])
  const [folders, setFolders] = useState<DriveFolder[]>([])
  const [selected, setSelected] = useState<DriveFolder>()
  const [query, setQuery] = useState('')
  const [state, setState] = useState<'loading' | 'loaded' | 'failed'>('loading')
  const [creating, setCreating] = useState(false)
  const parentID = trail[trail.length - 1]?.id
  const prefix = ['My Drive', ...trail.map((t) => t.name)].join(' / ')

  useEffect(() => {
    let alive = true
    setState((s) => (s === 'loaded' ? s : 'loading'))
    const t = setTimeout(() => {
      store.drive.listFolders(parentID, query).then((list) => {
        if (!alive) return
        setFolders(list)
        setState('loaded')
        setSelected((cur) => cur ?? list.find((f) => f.id === (settings.drive.kind === 'connected' ? settings.drive.folder.id : '')) ??
          (trail.length === 0 ? list.find((f) => f.name === DriveNaming.defaultFolderName) : undefined))
      }).catch(() => alive && setState('failed'))
    }, query ? 250 : 0)
    return () => { alive = false; clearTimeout(t) }
  }, [parentID, query]) // eslint-disable-line react-hooks/exhaustive-deps

  return (
    <Screen title="Choose a folder" subtitle="PuffyMeter" back={back} tabs={false}>
      {settings.profile && (
        <Card><div className="headline">{settings.profile.displayName}</div>{settings.profile.email && <div className="foot">{settings.profile.email}</div>}</Card>
      )}
      <div className="row">
        <button className="row grow" style={{ gap: 8 }} disabled={!trail.length} onClick={() => { setTrail(trail.slice(0, -1)); setSelected(undefined) }}>
          {trail.length ? <ChevronLeft size={20} color="var(--link)" /> : <HardDrive size={20} color="var(--link)" />}
          <span className="headline">{trail[trail.length - 1]?.name ?? 'My Drive'}</span>
        </button>
        <button className="link-btn" onClick={() => setCreating(true)}>New Folder</button>
      </div>
      <label className="row field elevated" style={{ gap: 8 }}>
        <Search size={18} color="var(--label-2)" />
        <input className="grow" style={{ border: 0, background: 'none', outline: 'none', fontSize: 17 }} placeholder="Search folders"
          value={query} onChange={(e) => setQuery(e.target.value)} aria-label="Search folders" />
      </label>
      {state === 'loading' && <div className="list">{[0, 1, 2, 3].map((i) => <div key={i} className="list-row"><span style={{ height: 14, width: 160, borderRadius: 4, background: 'var(--card-elevated)' }} /></div>)}</div>}
      {state === 'failed' && <Card><div className="headline">Couldn't load folders.</div><button className="text-btn" onClick={() => setQuery((q) => q + '')}>Retry</button></Card>}
      {state === 'loaded' && (folders.length === 0
        ? <Card><span className="sub">{query ? `No folders match “${query}”.` : 'No folders here. Create one with New Folder.'}</span></Card>
        : (
          <div className="list">
            {folders.map((f) => (
              <div key={f.id} className="list-row" style={{ paddingRight: 6 }}>
                <button className="row grow" style={{ textAlign: 'left' }} onClick={() => setSelected(f)} aria-pressed={selected?.id === f.id}>
                  <Folder size={22} color="var(--accent)" /><span className="body">{f.name}</span>
                </button>
                {selected?.id === f.id
                  ? <Check size={20} color="var(--accent)" style={{ margin: '0 12px' }} />
                  : <button aria-label={`Open ${f.name}`} onClick={() => { setTrail([...trail, f]); setSelected(undefined) }} style={{ width: 44, height: 44, display: 'grid', placeItems: 'center', color: 'var(--label-3)' }}><ChevronRight size={18} /></button>}
              </div>
            ))}
          </div>
        ))}
      {selected && <Disclaimer>Selected: {prefix} / {selected.name}<br />Only this folder will be accessible to PuffyMeter.</Disclaimer>}
      <button className="btn primary" disabled={!selected} onClick={() => selected && onChoose({ id: selected.id, name: selected.name, path: `${prefix} / ${selected.name}` })}>Use this folder</button>
      {creating && (
        <NewFolderSheet parentID={parentID} prefix={prefix} onClose={() => setCreating(false)}
          onCreated={(f) => { setCreating(false); setFolders((l) => [...l, f].sort((a, b) => a.name.localeCompare(b.name))); setSelected(f) }} />
      )}
    </Screen>
  )
}

function NewFolderSheet({ parentID, prefix, onClose, onCreated }: { parentID?: string; prefix: string; onClose: () => void; onCreated: (f: DriveFolder) => void }) {
  const [name, setName] = useState(DriveNaming.defaultFolderName)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string>()
  const trimmed = name.trim()
  const create = async () => {
    if (!trimmed) return
    setBusy(true)
    try {
      onCreated(await store.drive.createFolder(trimmed, parentID))
    } catch {
      setError("Couldn't create the folder. Check your connection and try again.")
    } finally {
      setBusy(false)
    }
  }
  return (
    <Sheet title="New Folder" onClose={onClose}>
      <div className="stack lg">
        <FolderPlus size={48} strokeWidth={1.2} color="var(--link)" />
        <p className="body sub" style={{ margin: 0 }}>Create a dedicated home for your daily photos and scan notes.</p>
        <span className="foot" style={{ textTransform: 'uppercase' }}>Folder name</span>
        <input className="field elevated" autoFocus value={name} onChange={(e) => setName(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && create()} aria-label="Folder name" />
        <Card style={{ background: 'var(--card-elevated)' }}>
          <div className="row"><Folder size={20} color="var(--accent)" /><span className="grow">Location</span><span className="sub">{prefix.split(' / ').pop()}</span></div>
          <div className="foot" style={{ marginTop: 8 }}>{prefix} / {trimmed || '…'}</div>
          <div className="foot good">Limited to files saved by PuffyMeter</div>
        </Card>
        {error && <p className="foot accent">{error}</p>}
        <button className="btn primary" disabled={!trimmed || busy} onClick={create}>{busy ? 'Creating…' : 'Create folder'}</button>
        <button className="btn secondary" onClick={onClose}>Cancel</button>
      </div>
    </Sheet>
  )
}

export function OnboardingFolderPicker() {
  const navigate = useNavigate()
  return (
    <FolderPicker onChoose={(folder) => {
      store.connectDrive(folder)
      store.setOnboardingStep('driveConnected')
      navigate('/drive/connected')
    }} />
  )
}

export function DriveConnected() {
  const navigate = useNavigate()
  const { folder, settings } = useApp()
  return (
    <Screen title="Drive connected" subtitle="PuffyMeter" back="/drive/folders" tabs={false}>
      <div className="center" style={{ padding: '20px 0' }}>
        <div style={{ width: 78, height: 78, borderRadius: '50%', border: '2.5px solid var(--scan)', display: 'inline-grid', placeItems: 'center' }}>
          <Check size={34} color="var(--scan)" />
        </div>
      </div>
      <h2 className="hero-headline center">{'Your daily photos\nhave a home.'}</h2>
      <p className="body sub center" style={{ margin: 0 }}>New scans will be backed up automatically when you're online.</p>
      <Card>
        <div className="row"><FolderCheck size={20} color="var(--accent)" /><span className="headline">{folder?.name}</span></div>
        <div className="foot" style={{ marginTop: 8 }}>{folder?.path}</div>
        {settings.profile?.email && <div className="foot">{settings.profile.email}</div>}
        <div className="foot good">Connected · Access to this folder only</div>
      </Card>
      <button className="btn primary" onClick={() => { store.setOnboardingStep('permissions'); navigate('/permissions') }}>Continue</button>
      <button className="btn secondary" onClick={() => navigate('/drive/folders')}>Change folder</button>
    </Screen>
  )
}

// MARK: Permissions

export function Permissions() {
  const navigate = useNavigate()
  const { settings } = useApp()
  const [camera, setCamera] = useState<'granted' | 'denied' | 'prompt'>('prompt')
  const demo = store.getSnapshot().demo
  useEffect(() => {
    preloadFaceModel()
    if (demo || !cameraSupported()) setCamera('granted')
    else void cameraPermission().then(setCamera)
  }, [demo])
  const notificationsSupported = typeof Notification !== 'undefined'
  return (
    <Screen title="Make it yours" subtitle="PuffyMeter" back tabs={false}>
      <p className="body sub" style={{ margin: 0 }}>A few permissions make your morning routine effortless. You can change them anytime.</p>
      <Card>
        <div className="row"><Camera size={22} color="var(--accent)" /><span className="headline grow">Camera</span><span className="pill accent">Required</span></div>
        <p className="body sub">Capture your face for a cosmetic puffiness estimate. Photos are analyzed in your browser and aren't added to your photo library.</p>
        {camera === 'granted' ? <div className="headline good center" style={{ padding: 10 }}>✓ Allowed</div>
          : camera === 'denied' ? <p className="foot accent">Camera access is off. Allow it in your browser's site settings, then reload.</p>
          : <button className="btn primary" onClick={async () => setCamera((await requestCamera()) ? 'granted' : 'denied')}>Allow camera</button>}
      </Card>
      <Card>
        <div className="row"><Bell size={22} color="var(--accent)" /><span className="headline grow">Reminders</span>
          <Toggle label="Morning reminders" checked={settings.reminderEnabled} onChange={async (v) => {
            if (v && notificationsSupported && Notification.permission === 'default') await Notification.requestPermission()
            store.setSettings({ reminderEnabled: v })
          }} />
        </div>
        <p className="body sub">A gentle nudge to scan at the same time each day. On the web this shows when PuffyMeter is open; add it to your Home Screen for the best experience.</p>
        <label className="row" style={{ justifyContent: 'space-between' }}>
          <span>Morning reminder</span>
          <input type="time" className="field elevated" style={{ width: 130, minHeight: 36, padding: '6px 10px' }}
            value={`${String(settings.reminderTime.hour).padStart(2, '0')}:${String(settings.reminderTime.minute).padStart(2, '0')}`}
            onChange={(e) => { const [h, m] = e.target.value.split(':').map(Number); store.setSettings({ reminderTime: { hour: h, minute: m } }) }} />
        </label>
      </Card>
      <button className="btn primary" disabled={camera !== 'granted'} onClick={() => { store.setOnboardingStep('baselineScan'); navigate('/baseline') }}>Start my first scan</button>
      <Disclaimer center>You can continue without reminders. Reminder time: {fmt.reminder(settings.reminderTime)}.</Disclaimer>
    </Screen>
  )
}
