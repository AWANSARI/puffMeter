import { BarChart3, Camera, Heart, Star, User } from 'lucide-react'
import { useEffect } from 'react'
import { BrowserRouter, NavLink, Navigate, Route, Routes, useLocation, useNavigate } from 'react-router-dom'
import type { OnboardingStep } from './domain/types'
import { AllRingsClosed, AwardDetail, AwardUnlockSheet, Awards, ChallengesScreen, Goals } from './screens/Awards'
import { ConnectDrive, DriveConnected, OnboardingFolderPicker, Permissions, SignIn, Welcome } from './screens/Onboarding'
import { DriveSettings, ExportData, Privacy, Profile } from './screens/Profile'
import { ScanFlow, ScanTab } from './screens/Scan'
import { Summary } from './screens/Summary'
import { PhotoGrid, Patterns, ScanDetail, TimeLapse, Trends } from './screens/Trends'
import { awardByID, store, useApp } from './store/appStore'
import { ActivityRings } from './ui/rings'

const STEP_ROUTE: Record<OnboardingStep, string> = {
  welcome: '/welcome', signIn: '/signin', driveLimitedAccess: '/drive', driveFolderPicker: '/drive/folders',
  driveConnected: '/drive/connected', permissions: '/permissions', baselineScan: '/baseline', complete: '/',
}
const ONBOARDING_PATHS = new Set(Object.values(STEP_ROUTE).filter((p) => p !== '/'))

const TABS = [
  { to: '/', label: 'Summary', icon: Heart, end: true },
  { to: '/trends', label: 'Trends', icon: BarChart3 },
  { to: '/scan', label: 'Scan', icon: Camera },
  { to: '/awards', label: 'Awards', icon: Star },
  { to: '/profile', label: 'Profile', icon: User },
]
const NO_TABS = ['/goals', '/scans/', '/trends/time-lapse', '/awards/', '/profile/']

function TabBar() {
  const { pathname } = useLocation()
  if (NO_TABS.some((p) => pathname.startsWith(p))) return null
  return (
    <nav className="tabbar" aria-label="Main">
      {TABS.map(({ to, label, icon: Icon, end }) => (
        <NavLink key={to} to={to} end={end} className={({ isActive }) => (isActive ? 'active' : '')}>
          <Icon size={26} strokeWidth={1.6} />
          {label}
        </NavLink>
      ))}
    </nav>
  )
}

function Shell() {
  const { snap, settings } = useApp()
  const { pathname } = useLocation()
  const navigate = useNavigate()

  useEffect(() => { void store.load() }, [])
  useEffect(() => {
    if (settings.theme === 'system') document.documentElement.removeAttribute('data-theme')
    else document.documentElement.setAttribute('data-theme', settings.theme)
  }, [settings.theme])

  // Gentle in-app reminder: if it's past the reminder time and today has no scan.
  useEffect(() => {
    if (!snap.loaded || !settings.reminderEnabled || settings.onboardingStep !== 'complete') return
    const now = store.now()
    const due = now.getHours() * 60 + now.getMinutes() >= settings.reminderTime.hour * 60 + settings.reminderTime.minute
    const scanned = snap.data.scans.some((s) => s.dayKey === store.today())
    if (due && !scanned && typeof Notification !== 'undefined' && Notification.permission === 'granted' && document.visibilityState === 'visible'
      && sessionStorage.getItem('pm.reminded') !== store.today()) {
      sessionStorage.setItem('pm.reminded', store.today())
      navigator.serviceWorker?.ready.then((reg) => reg.showNotification('Good morning', { body: 'Time for your PuffyMeter scan.', icon: '/icons/icon-192.png', tag: 'daily' }))
        .catch(() => undefined)
    }
  }, [snap.loaded]) // eslint-disable-line react-hooks/exhaustive-deps

  if (!snap.loaded) {
    return <div style={{ minHeight: '100dvh', display: 'grid', placeItems: 'center' }}><ActivityRings progress={{ dePuff: 1, scan: 1, habits: 0.75 }} size="compact" animate={false} /></div>
  }

  const step = settings.onboardingStep
  if (step !== 'complete' && !ONBOARDING_PATHS.has(pathname)) return <Navigate to={STEP_ROUTE[step]} replace />
  if (step === 'complete' && ONBOARDING_PATHS.has(pathname)) return <Navigate to="/" replace />

  const award = !snap.showAllRingsClosed && snap.awardQueue[0] ? awardByID(snap.awardQueue[0]) : undefined
  return (
    <>
      <Routes>
        <Route path="/welcome" element={<Welcome />} />
        <Route path="/signin" element={<SignIn />} />
        <Route path="/drive" element={<ConnectDrive />} />
        <Route path="/drive/folders" element={<OnboardingFolderPicker />} />
        <Route path="/drive/connected" element={<DriveConnected />} />
        <Route path="/permissions" element={<Permissions />} />
        <Route path="/baseline" element={<ScanFlow isBaseline onDone={() => { store.setOnboardingStep('complete'); navigate('/') }} />} />

        <Route path="/" element={<Summary />} />
        <Route path="/trends" element={<Trends />} />
        <Route path="/trends/time-lapse" element={<TimeLapse />} />
        <Route path="/trends/patterns" element={<Patterns />} />
        <Route path="/scans" element={<PhotoGrid />} />
        <Route path="/scans/:id" element={<ScanDetail />} />
        <Route path="/scan" element={<ScanTab />} />
        <Route path="/awards" element={<Awards />} />
        <Route path="/awards/:id" element={<AwardDetail />} />
        <Route path="/profile" element={<Profile />} />
        <Route path="/profile/drive" element={<DriveSettings />} />
        <Route path="/profile/export" element={<ExportData />} />
        <Route path="/profile/privacy" element={<Privacy />} />
        <Route path="/goals" element={<Goals />} />
        <Route path="/challenges" element={<ChallengesScreen />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
      {step === 'complete' && <TabBar />}
      {award && <AwardUnlockSheet award={award} />}
      {snap.showAllRingsClosed && step === 'complete' && <AllRingsClosed />}
    </>
  )
}

export default function App() {
  return (
    <BrowserRouter>
      <div className="app"><Shell /></div>
    </BrowserRouter>
  )
}
