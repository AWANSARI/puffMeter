import { Bell, ChevronRight, Clock, Cpu, Download, EyeOff, Folder, Hand, HardDrive, LogOut, Moon, ShieldCheck, Sunrise, Table, Target, Trash2 } from 'lucide-react'
import { useEffect, useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { fmt } from '../domain/dates'
import { History } from '../domain/engine'
import { toCSV } from '../domain/export'
import { driveFolder, FAILURE_MESSAGE, type Settings } from '../domain/types'
import { DriveError } from '../services/drive'
import { AuthError, authErrorMessage, GoogleAuth } from '../services/googleAuth'
import { store, useApp } from '../store/appStore'
import { Alert, Card, Screen, Sheet, Toast, Toggle } from '../ui/components'
import { FolderPicker } from './Onboarding'

function Row({ icon, label, value, onClick, danger, children }: {
  icon?: React.ReactNode; label: string; value?: string; onClick?: () => void; danger?: boolean; children?: React.ReactNode
}) {
  const content = (
    <>
      {icon && <span className="icon" style={danger ? { color: 'var(--destructive)' } : undefined}>{icon}</span>}
      <span className="grow">{label}</span>
      {value && <span className="value">{value}</span>}
      {children}
      {onClick && !children && <ChevronRight size={18} className="chev" />}
    </>
  )
  return onClick
    ? <button className={`list-row${danger ? ' danger' : ''}`} onClick={onClick}>{content}</button>
    : <div className="list-row">{content}</div>
}

export function Profile() {
  const { settings, folder, d, snap } = useApp()
  const navigate = useNavigate()
  const [signOut, setSignOut] = useState(false)
  const profile = settings.profile
  const initials = (profile?.displayName ?? '?').split(' ').slice(0, 2).map((p) => p[0]).join('').toUpperCase()
  const pending = store.pendingUploadCount()
  const lastSync = settings.lastSyncAt
    ? `Last sync: ${fmt.time(settings.lastSyncAt)} · ${pending ? `${fmt.plural(pending, 'scan')} waiting` : 'All scans saved'}`
    : 'Not synced yet'
  return (
    <Screen title="Profile" subtitle="Your routine, your privacy">
      <Card>
        <div className="row" style={{ gap: 14 }}>
          <span style={{ width: 56, height: 56, borderRadius: 28, background: 'var(--accent-fill)', color: 'var(--accent)', display: 'grid', placeItems: 'center', fontSize: 22, fontWeight: 700 }}>{initials}</span>
          <div>
            <div style={{ fontSize: 20, fontWeight: 600 }}>{profile?.displayName ?? 'Guest'}</div>
            {profile?.email && <div className="foot">{profile.email}</div>}
            <div className="foot">{profile?.provider === 'google' ? 'Connected with Google' : 'Using PuffyMeter on this device'}</div>
          </div>
        </div>
      </Card>

      <div className="list-header">Photo storage</div>
      <div className="list">
        <Row icon={<HardDrive size={20} color="var(--link)" />} label="Google Drive folder"
          value={settings.drive.kind === 'connected' ? 'Connected' : settings.drive.kind === 'needsReconnect' ? 'Reconnect' : 'Not connected'}
          onClick={() => navigate('/profile/drive')} />
        {folder && <div className="list-row foot" style={{ flexDirection: 'column', alignItems: 'flex-start', gap: 2 }}><span>{folder.path}</span><span>{lastSync}</span></div>}
      </div>

      <div className="list-header">Your daily routine</div>
      <div className="list">
        <Row icon={<Bell size={20} />} label="Morning reminders">
          <Toggle label="Morning reminders" checked={settings.reminderEnabled} onChange={async (v) => {
            if (v && typeof Notification !== 'undefined' && Notification.permission === 'default') await Notification.requestPermission()
            store.setSettings({ reminderEnabled: v })
          }} />
        </Row>
        <Row icon={<Clock size={20} />} label="Reminder time">
          <input type="time" aria-label="Reminder time" disabled={!settings.reminderEnabled} className="field elevated" style={{ width: 120, minHeight: 34, padding: '4px 8px' }}
            value={`${String(settings.reminderTime.hour).padStart(2, '0')}:${String(settings.reminderTime.minute).padStart(2, '0')}`}
            onChange={(e) => { const [h, m] = e.target.value.split(':').map(Number); store.setSettings({ reminderTime: { hour: h, minute: m } }) }} />
        </Row>
        <Row icon={<Target size={20} />} label="Change daily goals" onClick={() => navigate('/goals')} />
        <Row icon={<Sunrise size={20} />} label="Monthly challenges" onClick={() => navigate('/challenges')} />
      </div>

      <div className="list-header">Appearance</div>
      <div className="list">
        <Row icon={<Moon size={20} />} label="Theme">
          <select aria-label="Theme" className="field elevated" style={{ width: 120, minHeight: 34, padding: '4px 8px' }} value={settings.theme}
            onChange={(e) => store.setSettings({ theme: e.target.value as Settings['theme'] })}>
            <option value="system">System</option><option value="dark">Dark</option><option value="light">Light</option>
          </select>
        </Row>
      </div>

      <div className="list-header">Your data</div>
      <div className="list">
        <Row icon={<HardDrive size={20} color="var(--link)" />} label="Data storage"
          value={snap.folder.kind === 'connected' ? 'Folder' : 'This browser'} onClick={() => navigate('/profile/storage')} />
        <Row icon={<Download size={20} color="var(--link)" />} label="Export my data" onClick={() => navigate('/profile/export')} />
        <Row icon={<Hand size={20} color="var(--link)" />} label="Privacy & permissions" onClick={() => navigate('/profile/privacy')} />
        <Row icon={<LogOut size={20} />} label="Sign out" danger onClick={() => setSignOut(true)} />
      </div>
      <p className="foot center" style={{ marginTop: 12 }}>PuffyMeter 1.0 (web) · Cosmetic wellness, not diagnosis.<br />Your photos are never used for advertising.</p>
      {d.scans.length === 0 && <p className="foot center">Tip: add PuffyMeter to your Home Screen from the browser's Share menu.</p>}
      {signOut && (
        <Sheet title="Sign out of PuffyMeter?" onClose={() => setSignOut(false)}>
          <div className="stack lg">
            <p className="sub center" style={{ margin: 0 }}>Your photos stay in Google Drive.</p>
            <button className="btn danger" onClick={async () => { await store.signOut(false); navigate('/signin') }}>Sign out</button>
            <button className="btn danger" onClick={async () => { await store.signOut(true); navigate('/') }}>Sign out & delete local data</button>
          </div>
        </Sheet>
      )}
    </Screen>
  )
}

export function DriveSettings() {
  const { settings, folder, snap } = useApp()
  const [params, setParams] = useSearchParams()
  const [count, setCount] = useState<number>()
  const [choosing, setChoosing] = useState(false)
  const [disconnect, setDisconnect] = useState(false)
  const [toast, setToast] = useState<string | undefined>(authErrorMessage(params.get('error')))
  const [busy, setBusy] = useState(false)
  const demo = snap.demo
  useEffect(() => {
    if (folder && settings.drive.kind === 'connected') store.drive.fileCount(folder.id).then(setCount).catch(() => undefined)
  }, [folder?.id, settings.drive.kind]) // eslint-disable-line react-hooks/exhaustive-deps

  /** Signs in with Google (redirect) when needed, then connects the default "PuffyMeter Daily" folder. */
  const connect = async () => {
    if (!snap.googleEnabled) { setToast(authErrorMessage('notConfigured')); return }
    setBusy(true)
    try {
      if (!demo) {
        const session = await GoogleAuth.session()
        if (!session || !session.drive) {
          GoogleAuth.signIn('/auth/complete?next=/profile/drive?connect=1', settings.profile?.email)
          return
        }
        if (settings.profile?.provider !== 'google') store.setSettings({ profile: GoogleAuth.profile(session) })
      }
      await store.connectDefaultFolder()
      setToast('Google Drive connected')
    } catch (e) {
      // Google session expired or was revoked: go back through Google sign-in.
      if (e instanceof DriveError && e.failure === 'authExpired' && !snap.demo) {
        GoogleAuth.signIn('/auth/complete?next=/profile/drive?connect=1', settings.profile?.email)
        return
      }
      setToast(e instanceof AuthError ? e.userMessage : e instanceof DriveError ? FAILURE_MESSAGE[e.failure] : "Couldn't connect to Google Drive. Please try again.")
    } finally {
      setBusy(false)
    }
  }
  // Back from Google's consent screen with ?connect=1: finish connecting.
  useEffect(() => {
    if (params.get('connect') === '1') {
      setParams({}, { replace: true })
      void connect()
    }
  }, []) // eslint-disable-line react-hooks/exhaustive-deps
  const reconnect = () => GoogleAuth.signIn('/auth/complete?next=/profile/drive', settings.profile?.email)

  if (choosing) {
    return <FolderPicker back="/profile/drive" onChoose={(f) => { store.connectDrive(f); setChoosing(false); setToast('Google Drive connected') }} />
  }

  return (
    <Screen title="Google Drive" back="/profile">
      {folder ? (
        <div className="list">
          <Row label="Account" value={settings.profile?.email ?? 'Google'} />
          <Row label="Folder" value={folder.path} />
          <Row label="Files" value={count != null ? String(count) : '…'} />
          <Row label="Last sync" value={settings.lastSyncAt ? `${fmt.dateMedium(settings.lastSyncAt)} ${fmt.time(settings.lastSyncAt)}` : 'Never'} />
        </div>
      ) : (
        <Card><p className="sub" style={{ margin: 0 }}>Scans are kept on this device only. Connect Google Drive to back them up to a folder you choose.</p></Card>
      )}
      {settings.drive.kind === 'needsReconnect' && (
        <button className="btn primary" onClick={reconnect}>Reconnect Google Drive</button>
      )}
      {folder ? (
        <div className="list">
          <Row icon={<Folder size={20} />} label="Sync now" onClick={() => { store.retryUploads(); setToast('Syncing…') }} />
          <Row icon={<HardDrive size={20} />} label="Change folder" onClick={() => setChoosing(true)} />
          <Row icon={<Download size={20} />} label={busy ? 'Restoring…' : 'Restore history from Drive'} onClick={async () => {
            setBusy(true)
            try {
              const n = await store.restoreFromDrive()
              setToast(n ? `Restored ${fmt.plural(n, 'scan')}` : 'Everything is already here.')
            } catch { setToast("Couldn't restore right now.") } finally { setBusy(false) }
          }} />
        </div>
      ) : (
        <button className="btn primary" disabled={busy} onClick={connect}>{busy ? 'Connecting…' : 'Connect Google Drive'}</button>
      )}
      <div className="list-header">Upload quality</div>
      <div className="list">
        {(['original', 'high', 'compact'] as const).map((q) => (
          <button key={q} className="list-row" onClick={() => store.setSettings({ uploadQuality: q })} aria-pressed={settings.uploadQuality === q}>
            <span className="grow">{q === 'original' ? 'Original' : q === 'high' ? 'High (default)' : 'Compact'}</span>
            {settings.uploadQuality === q && <span className="accent">✓</span>}
          </button>
        ))}
      </div>
      {folder && <button className="btn danger" onClick={() => setDisconnect(true)}>Disconnect Google Drive</button>}
      {!snap.googleEnabled && <p className="foot">Google Drive isn't set up on this site yet. The site owner needs to add the Google OAuth settings in Netlify.</p>}
      {disconnect && (
        <Alert title="Disconnect Google Drive?" message="Your photos stay in Google Drive. New scans will be kept on this device until you reconnect."
          buttons={[{ label: 'Cancel', onClick: () => setDisconnect(false) }, { label: 'Disconnect', destructive: true, onClick: () => { store.disconnectDrive(); setDisconnect(false) } }]} />
      )}
      {toast && <Toast message={toast} onDone={() => setToast(undefined)} />}
    </Screen>
  )
}

export function ExportData() {
  const { d } = useApp()
  const download = () => {
    const csv = toCSV(new History(d.scans, d.habitLogs, d.goals))
    const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv' }))
    const a = document.createElement('a')
    a.href = url
    a.download = 'PuffyMeter-scores.csv'
    a.click()
    setTimeout(() => URL.revokeObjectURL(url), 1000)
  }
  const navigate = useNavigate()
  return (
    <Screen title="Export my data" back="/profile">
      <div className="list">
        <Row icon={<Table size={20} color="var(--link)" />} label="Export scores (CSV)" onClick={download} />
        <Row icon={<Download size={20} color="var(--link)" />} label="Export time-lapse video" onClick={() => navigate('/trends/time-lapse')} />
      </div>
      <p className="list-footer">Date, time, scores, face zones, habits, notes and tags for every scan.</p>
    </Screen>
  )
}

export function Privacy() {
  const navigate = useNavigate()
  const [trashDrive, setTrashDrive] = useState(false)
  const [step, setStep] = useState(0)
  const { settings } = useApp()
  return (
    <Screen title="Privacy & permissions" back="/profile">
      <div className="list-header">How PuffyMeter handles your face</div>
      <div className="list">
        <Row icon={<Cpu size={20} />} label="Analysis runs in your browser" />
        <Row icon={<Folder size={20} />} label="Photos go only to your chosen Drive folder" />
        <Row icon={<ShieldCheck size={20} />} label="No ads, no trackers, no PuffyMeter database" />
        <Row icon={<EyeOff size={20} />} label="Photos are stored on this device, not in the cloud" />
      </div>
      <p className="list-footer">Camera access is managed in your browser's site settings. <a href="/privacy.html">Privacy Policy</a></p>
      <div className="list-header">Delete</div>
      <div className="list">
        {driveFolder(settings.drive) && (
          <Row label="Also move Drive files to Trash"><Toggle label="Also move Drive files to Trash" checked={trashDrive} onChange={setTrashDrive} /></Row>
        )}
        <Row icon={<Trash2 size={20} />} label="Delete all data" danger onClick={() => setStep(1)} />
      </div>
      <p className="list-footer">Removes scans, photos, habits, awards and settings from this device.{trashDrive ? ' Drive files must be moved to Trash in Google Drive.' : ''}</p>
      {step === 1 && (
        <Alert title="Delete all PuffyMeter data?" message="Local data will be erased. Your Drive photos stay."
          buttons={[{ label: 'Cancel', onClick: () => setStep(0) }, { label: 'Continue', destructive: true, onClick: () => setStep(2) }]} />
      )}
      {step === 2 && (
        <Alert title="This can't be undone" message="Everything on this device will be erased."
          buttons={[{ label: 'Cancel', onClick: () => setStep(0) },
            { label: 'Delete everything', destructive: true, onClick: async () => { await store.deleteAllData(); navigate('/') } }]} />
      )}
    </Screen>
  )
}
