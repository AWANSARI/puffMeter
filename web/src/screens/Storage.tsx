import { Archive, Download, FolderOpen, HardDrive, Info, Share2, ShieldCheck, Smartphone, Upload } from 'lucide-react'
import { useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { fmt } from '../domain/dates'
import { backupFileName, folderSupported, pickFolder, type StateFile } from '../services/dataFolder'
import { store, useApp } from '../store/appStore'
import { Card, Disclaimer, ProgressBar, Screen, Sheet, Toast } from '../ui/components'
import { ActivityRings } from '../ui/rings'

export const isIOS = () => /iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)
export const isStandalone = () =>
  matchMedia('(display-mode: standalone)').matches || (navigator as Navigator & { standalone?: boolean }).standalone === true

type Progress = { label: string; done: number; total: number }

function ProgressCard({ p }: { p: Progress }) {
  return (
    <Card>
      <div className="headline" style={{ marginBottom: 8 }}>{p.label}</div>
      <ProgressBar value={p.total ? p.done / p.total : 0.1} color="var(--accent)" />
      <div className="foot" style={{ marginTop: 6 }}>{p.total ? `${p.done} of ${p.total}` : 'Working…'}</div>
    </Card>
  )
}

/**
 * Pick a folder, look inside, and either restore what's there or save this browser's data into it.
 * Returns true once the folder is in use.
 */
function useFolderSetup(onDone: (restored: boolean) => void) {
  const { d } = useApp()
  const [found, setFound] = useState<{ handle: FileSystemDirectoryHandle; file: StateFile }>()
  const [progress, setProgress] = useState<Progress>()
  const [error, setError] = useState<string>()

  const start = async () => {
    setError(undefined)
    let handle: FileSystemDirectoryHandle
    try {
      handle = await pickFolder()
    } catch {
      return // cancelled
    }
    const file = await store.inspectFolder(handle)
    if (file) { setFound({ handle, file }); return }
    await use(handle, 'save')
  }

  const use = async (handle: FileSystemDirectoryHandle, mode: 'restore' | 'save') => {
    setFound(undefined)
    setProgress({ label: mode === 'restore' ? 'Loading your data…' : 'Saving to your folder…', done: 0, total: 0 })
    try {
      await store.useFolder(handle, mode, (done, total) => setProgress({ label: 'Saving photos to your folder…', done, total }))
      onDone(mode === 'restore')
    } catch {
      setError("PuffyMeter couldn't write to that folder. Choose a folder in Documents or your home folder.")
    } finally {
      setProgress(undefined)
    }
  }

  const sheet = found && (
    <Sheet title="PuffyMeter data found" onClose={() => setFound(undefined)}>
      <div className="stack lg">
        <p className="body sub" style={{ margin: 0 }}>
          “{found.handle.name}” has {fmt.plural(found.file.state.scans.length, 'scan')}, last saved {fmt.dateMedium(found.file.savedAt)} at {fmt.time(found.file.savedAt)}.
        </p>
        <button className="btn primary" onClick={() => use(found.handle, 'restore')}>Use the data in this folder</button>
        {d.scans.length > 0 && (
          <button className="btn secondary pink" onClick={() => use(found.handle, 'save')}>Replace it with this browser's data ({fmt.plural(d.scans.length, 'scan')})</button>
        )}
      </div>
    </Sheet>
  )
  return { start, sheet, progress, error }
}

/** Save/restore a single backup .zip — the option that works on every device, including iPhone. */
function BackupActions({ onRestored }: { onRestored?: (count: number) => void }) {
  const { d, settings } = useApp()
  const input = useRef<HTMLInputElement>(null)
  const [ready, setReady] = useState<File>()
  const [progress, setProgress] = useState<Progress>()
  const [toast, setToast] = useState<string>()

  const create = async () => {
    setProgress({ label: 'Preparing backup…', done: 0, total: d.scans.length })
    try {
      const blob = await store.exportBackup((done, total) => setProgress({ label: 'Adding photos…', done, total }))
      setReady(new File([blob], backupFileName(), { type: 'application/zip' }))
    } finally {
      setProgress(undefined)
    }
  }

  // Sharing needs a fresh tap, so it's a second button once the file is ready.
  const save = async (file: File) => {
    try {
      if (navigator.canShare?.({ files: [file] })) {
        await navigator.share({ files: [file], title: 'PuffyMeter backup' })
      } else {
        const url = URL.createObjectURL(file)
        const a = document.createElement('a')
        a.href = url
        a.download = file.name
        a.click()
        setTimeout(() => URL.revokeObjectURL(url), 2000)
      }
      setReady(undefined)
      setToast('Backup saved')
    } catch { /* share sheet dismissed */ }
  }

  const restore = async (file: File) => {
    setProgress({ label: 'Restoring…', done: 0, total: 0 })
    try {
      const count = await store.restoreBackup(file, (done, total) => setProgress({ label: 'Restoring photos…', done, total }))
      setToast(`Restored ${fmt.plural(count, 'scan')}`)
      onRestored?.(count)
    } catch {
      setToast("That file isn't a PuffyMeter backup.")
    } finally {
      setProgress(undefined)
    }
  }

  return (
    <>
      {progress && <ProgressCard p={progress} />}
      <div className="list">
        {ready ? (
          <button className="list-row" onClick={() => save(ready)}>
            <span className="icon">{isIOS() ? <Share2 size={20} /> : <Download size={20} />}</span>
            <span className="grow">{isIOS() ? 'Save to Files…' : 'Download backup'} ({(ready.size / 1_048_576).toFixed(1)} MB)</span>
          </button>
        ) : (
          <button className="list-row" disabled={!!progress || d.scans.length === 0} onClick={create}>
            <span className="icon"><Archive size={20} /></span>
            <span className="grow">Save backup file</span>
            {settings.lastBackupAt && <span className="value">{fmt.dateMedium(settings.lastBackupAt)}</span>}
          </button>
        )}
        <button className="list-row" disabled={!!progress} onClick={() => input.current?.click()}>
          <span className="icon"><Upload size={20} /></span>
          <span className="grow">Restore from backup file</span>
        </button>
      </div>
      <input ref={input} type="file" accept=".zip,application/zip" hidden aria-hidden
        onChange={(e) => { const f = e.target.files?.[0]; e.target.value = ''; if (f) void restore(f) }} />
      {toast && <Toast message={toast} onDone={() => setToast(undefined)} />}
    </>
  )
}

// MARK: Onboarding: where should data live?

export function StorageChoice() {
  const navigate = useNavigate()
  const next = (restored: boolean) => {
    if (restored && store.getSnapshot().data.scans.length) {
      store.setOnboardingStep('complete')
      navigate('/')
    } else {
      store.setOnboardingStep('permissions')
      navigate('/permissions')
    }
  }
  const folder = useFolderSetup(next)
  const supported = folderSupported()
  return (
    <Screen title="Where to keep your data" subtitle="PuffyMeter" back="/signin" tabs={false}>
      <p className="body sub" style={{ margin: 0 }}>PuffyMeter has no servers. Choose where your photos and scores live.</p>
      {folder.progress && <ProgressCard p={folder.progress} />}
      {supported && (
        <Card>
          <div className="row"><FolderOpen size={22} color="var(--accent)" /><span className="headline grow">A folder on this device</span><span className="pill accent">Recommended</span></div>
          <p className="body sub">Photos and scores are saved as ordinary files in a folder you choose, such as Documents/PuffyMeter. PuffyMeter reads it every time it opens, so clearing the browser doesn't lose anything.</p>
          <button className="btn primary" onClick={folder.start}>Choose a folder</button>
        </Card>
      )}
      <Card>
        <div className="row"><Smartphone size={22} color="var(--accent)" /><span className="headline grow">This browser</span></div>
        <p className="body sub">Quickest to start. {isIOS()
          ? 'iPhone browsers can clear website data, so open PuffyMeter from your Home Screen icon and save a backup file to the Files app now and then. You can do that from Profile.'
          : 'Save a backup file now and then from Profile, just in case.'}</p>
        <button className={`btn ${supported ? 'secondary' : 'primary'}`} onClick={() => next(false)}>Keep data in this browser</button>
      </Card>
      {folder.error && <p className="foot accent" role="alert">{folder.error}</p>}
      <button className="link-btn" style={{ alignSelf: 'center' }} onClick={() => navigate('/restore')}>Already have PuffyMeter data? Restore it</button>
      {folder.sheet}
    </Screen>
  )
}

// MARK: Restore (new device, or the browser forgot everything)

export function RestoreData() {
  const navigate = useNavigate()
  const done = () => {
    if (store.getSnapshot().data.scans.length) store.setOnboardingStep('complete')
    navigate('/')
  }
  const folder = useFolderSetup(done)
  return (
    <Screen title="Restore your data" subtitle="Pick up where you left off" back tabs={false}>
      {folder.progress && <ProgressCard p={folder.progress} />}
      {folderSupported() && (
        <Card>
          <div className="row"><FolderOpen size={22} color="var(--accent)" /><span className="headline">From your PuffyMeter folder</span></div>
          <p className="body sub">Choose the folder where PuffyMeter saved your data. It contains a file called puffymeter.json.</p>
          <button className="btn primary" onClick={folder.start}>Open my PuffyMeter folder</button>
        </Card>
      )}
      <Card>
        <div className="row"><Archive size={22} color="var(--accent)" /><span className="headline">From a backup file</span></div>
        <p className="body sub">Pick a PuffyMeter backup (.zip){isIOS() ? ' from the Files app' : ''}.</p>
      </Card>
      <BackupActions onRestored={() => done()} />
      {folder.error && <p className="foot accent" role="alert">{folder.error}</p>}
      <Disclaimer>Signed in with Google before? Sign in again and use Profile › Google Drive › Restore history from Drive.</Disclaimer>
      {folder.sheet}
    </Screen>
  )
}

// MARK: Profile › Data storage

export function StorageSettings() {
  const { snap, settings, d } = useApp()
  const [toast, setToast] = useState<string>()
  const folder = useFolderSetup((restored) => setToast(restored ? 'Loaded data from your folder' : 'Saving to your folder'))
  const f = snap.folder
  const where = f.kind === 'connected' ? `Folder “${f.name}” and this browser`
    : f.kind === 'needsPermission' ? `Folder “${f.name}” (needs your OK)`
    : f.kind === 'error' ? `Folder “${f.name}” (can't write)` : 'This browser only'
  return (
    <Screen title="Data storage" back="/profile">
      <div className="list">
        <div className="list-row"><span className="icon"><HardDrive size={20} /></span><span className="grow">Saved in</span><span className="value">{where}</span></div>
        <div className="list-row"><span className="icon"><ShieldCheck size={20} /></span><span className="grow">Protected from automatic clearing</span>
          <span className="value">{snap.persistent ? 'Yes' : 'Not guaranteed'}</span></div>
        {f.kind === 'connected' && f.lastSavedAt && (
          <div className="list-row"><span className="icon" /><span className="grow">Last saved to folder</span><span className="value">{fmt.time(f.lastSavedAt)}</span></div>
        )}
        <div className="list-row"><span className="icon" /><span className="grow">Scans</span><span className="value">{d.scans.length}</span></div>
      </div>

      <div className="list-header">Folder on this device</div>
      {folderSupported() ? (
        <div className="list">
          {f.kind === 'needsPermission' || f.kind === 'error' ? (
            <button className="list-row" onClick={async () => setToast((await store.reconnectFolder()) ? 'Folder reconnected' : 'Access not allowed')}>
              <span className="icon"><FolderOpen size={20} /></span><span className="grow">Allow access to “{f.name}”</span>
            </button>
          ) : null}
          <button className="list-row" onClick={folder.start}>
            <span className="icon"><FolderOpen size={20} /></span>
            <span className="grow">{f.kind === 'none' ? 'Choose a folder…' : 'Change folder…'}</span>
          </button>
          {f.kind !== 'none' && (
            <button className="list-row danger" onClick={async () => { await store.stopUsingFolder(); setToast('Stopped saving to the folder') }}>
              <span className="icon" /><span className="grow">Stop saving to the folder</span>
            </button>
          )}
        </div>
      ) : (
        <Card>
          <div className="row top"><Info size={20} color="var(--label-2)" style={{ flex: 'none' }} />
            <p className="foot" style={{ margin: 0 }}>
              {isIOS()
                ? "iPhone browsers don't let websites save to a folder you choose. Use a backup file instead: it goes to the Files app (On My iPhone or iCloud Drive), and you can restore it anytime."
                : 'This browser can’t save to a folder. Desktop Chrome or Edge, or Chrome on Android, can. Or use a backup file below.'}
            </p>
          </div>
        </Card>
      )}
      {folder.progress && <ProgressCard p={folder.progress} />}
      {folder.error && <p className="foot accent">{folder.error}</p>}

      <div className="list-header">Backup file</div>
      <BackupActions />
      <p className="list-footer">One .zip with everything: puffymeter.json, your photos and a scores file per scan.{settings.lastBackupAt ? ` Last backup ${fmt.dateMedium(settings.lastBackupAt)}.` : ''}</p>

      {isIOS() && (
        <Card>
          <div className="headline" style={{ marginBottom: 6 }}>Why iPhone data can disappear</div>
          <ul className="foot" style={{ margin: 0, paddingLeft: 18 }}>
            <li>The Home Screen app and Safari keep <b>separate</b> data. Always open PuffyMeter the same way.</li>
            <li>Safari clears website data after a while without visits. The Home Screen app is protected much better.</li>
            <li>Private Browsing never keeps data.</li>
          </ul>
          {!isStandalone() && <p className="foot" style={{ margin: '8px 0 0' }}>Tip: tap Share › <b>Add to Home Screen</b>, then use that icon.</p>}
        </Card>
      )}
      {folder.sheet}
      {toast && <Toast message={toast} onDone={() => setToast(undefined)} />}
    </Screen>
  )
}

// MARK: Launch gate: the folder needs a tap to be re-opened

export function FolderGate() {
  const { snap } = useApp()
  const [error, setError] = useState<string>()
  const folder = useFolderSetup(() => setError(undefined))
  const f = snap.folder
  if (f.kind !== 'needsPermission') return null
  return (
    <div className="fullscreen" role="dialog" aria-modal="true" aria-label="Open your PuffyMeter folder">
      <div className="inner screen no-tabs center" style={{ alignItems: 'center', justifyContent: 'center', minHeight: '100dvh' }}>
        <ActivityRings progress={{ dePuff: 1, scan: 1, habits: 0.75 }} size="compact" />
        <h1 className="large-title">Welcome back</h1>
        <p className="body sub" style={{ margin: 0 }}>Your PuffyMeter data is saved in the folder “{f.name}”. Allow PuffyMeter to open it again to load your latest scans.</p>
        <button className="btn primary" onClick={async () => {
          if (!(await store.reconnectFolder())) setError("Access wasn't allowed. Try again, or choose the folder.")
        }}><FolderOpen size={20} />Open “{f.name}”</button>
        <button className="btn secondary" onClick={folder.start}>Choose the folder again</button>
        <button className="link-btn foot" onClick={() => store.skipFolderForNow()}>Not now, use this browser's copy</button>
        {(error || folder.error) && <p className="foot accent" role="alert">{error ?? folder.error}</p>}
        {folder.progress && <ProgressCard p={folder.progress} />}
        {folder.sheet}
      </div>
    </div>
  )
}
