// PuffyMeter service worker: caches the app shell so it opens offline. Scan data lives in
// IndexedDB/localStorage, never in this cache. Google and model requests always go to the network.
const CACHE = 'puffymeter-v2'
const SHELL = ['/', '/index.html', '/manifest.webmanifest', '/icons/icon-192.png', '/icons/icon-512.png']

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()))
})

self.addEventListener('activate', (event) => {
  event.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim()))
})

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url)
  // Never touch sign-in or Drive proxy requests.
  if (event.request.method !== 'GET' || url.origin !== location.origin || url.pathname.startsWith('/api/')) return
  // App navigations: network first, fall back to the cached shell when offline.
  if (event.request.mode === 'navigate') {
    event.respondWith(fetch(event.request).catch(() => caches.match('/index.html')))
    return
  }
  // Hashed assets and the MediaPipe runtime: cache first.
  if (url.pathname.startsWith('/assets/') || url.pathname.startsWith('/mediapipe/') || url.pathname.startsWith('/icons/')) {
    event.respondWith(caches.match(event.request).then((hit) => hit || fetch(event.request).then((res) => {
      const copy = res.clone()
      caches.open(CACHE).then((c) => c.put(event.request, copy))
      return res
    })))
  }
})

self.addEventListener('notificationclick', (event) => {
  event.notification.close()
  event.waitUntil(self.clients.matchAll({ type: 'window' }).then((list) => (list[0] ? list[0].focus() : self.clients.openWindow('/scan'))))
})
