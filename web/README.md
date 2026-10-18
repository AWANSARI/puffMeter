# PuffyMeter Web

PuffyMeter as an installable web app (PWA), built with Vite, React and TypeScript, and ready for Netlify. It has the same screens, scoring, rings, awards and Drive format as the iOS app.

| | iOS app | Web app |
|---|---|---|
| Face analysis | ARKit / Vision, on device | MediaPipe Face Landmarker, in the browser |
| Photo storage | App sandbox and your Drive folder | This browser, plus optionally a folder on your device, a backup .zip and/or your Drive folder |
| Sign-in | Google, Sign in with Apple | Google (server-side, Netlify Functions), or no account |
| Apple Health, Face ID lock, widgets | Yes | Not available on the web |
| Reminders | Scheduled notifications | Shown when the app is opened after the reminder time |

## Run locally

```bash
cd web
npm install
npm run dev
```

The dev server runs at <http://localhost:5173>.

- **Demo mode:** open `/?demo` for the mockup data (Oct 8, 2026) and a simulated camera. Nothing is saved.
- **Production preview:** `npm run build && npm run preview` serves the site at <http://localhost:4173> with the same security headers Netlify uses.
- **Tests:** `npm test` runs the domain tests, which use the same numbers as the iOS PuffyKit tests, and the sign-in and Drive proxy function tests.

The camera works on `localhost` and on HTTPS sites only. Netlify sites are HTTPS by default.

## Where your data lives

PuffyMeter has no database. Data is always cached in this browser (localStorage and IndexedDB). You choose where else it goes:

| Option | Works on | How it behaves |
|---|---|---|
| **A folder on this device** | Desktop Chrome and Edge, Chrome on Android 132+ | Everything is saved as plain files in a folder you pick (File System Access API). On every launch PuffyMeter reads that folder first and uses it if it's newer, so clearing the browser loses nothing. After a browser restart you tap **Open "folder"** once to let it back in. |
| **Backup file** | Every browser, including iPhone | One `.zip` with the same layout as the folder. Use **Save to Files** on iPhone, or a download elsewhere. Restore it from the first screen ("Already use PuffyMeter? Restore your data") or from Profile › Data storage. |
| **Google Drive** | Everywhere, once Google sign-in is set up | Each scan's photo and scores file is uploaded to your Drive folder. |

PuffyMeter also asks the browser for persistent storage (`navigator.storage.persist()`). If your data lives only in this browser and hasn't been backed up for a week, Summary shows a reminder.

Folder and backup layout:

```
puffymeter.json              scans, habits, goals, awards, settings
photos/2026-10-08_0802.jpg   daily photos
scores/2026-10-08_0802.json  one scores file per scan (same format as Drive)
README.txt
```

**Why data can disappear on iPhone:** Safari can clear website data after a period without visits. The Home Screen app and Safari also keep **separate** storage, so opening PuffyMeter one way and then the other looks like a fresh start. Every Netlify deploy preview URL is a different site with its own empty storage too. Use the Home Screen icon and your main site URL, and save a backup now and then.

## Deploy to Netlify

### Option A: connect the Git repo (recommended)
1. Push this repository to GitHub, GitLab or Bitbucket.
2. In Netlify, choose **Add new site > Import an existing project** and pick the repo. The settings come from `netlify.toml` in the repo root (base `web`, command `npm ci && npm run build`, publish `dist`), so leave them as they are.
3. Deploy. Every push redeploys the site.

### Option B: drag and drop
1. Build the site:
   ```bash
   cd web && npm ci && npm run build
   ```
2. Go to <https://app.netlify.com/drop> and drag in the `web/dist` folder.

`_redirects` (single-page app routing) and `_headers` (security headers and camera permission) are in `public/`, so both options use them.

## Turn on Google sign-in and Drive

Sign-in follows the same pattern as [Atomic Tracker](https://github.com/AWANSARI/atomicTracker):
- **Flow:** a full-page redirect to Google using the authorization-code flow with the client secret, `access_type=offline` and PKCE.
- **Session:** the refresh token is stored in an encrypted HttpOnly cookie, with no database. Sessions last about 180 days instead of one hour.
- **Drive calls:** they go through a Netlify Function proxy (`/api/google/*`) that adds the token on the server. Google tokens never reach the browser.
- **Consent:** one consent screen covers sign-in and `drive.file`. PuffyMeter then finds or creates its own **PuffyMeter Daily** folder.

The server code is in `netlify/functions/auth.ts` (`/api/auth/*`) and `netlify/functions/google.ts` (`/api/google/*`), with shared helpers in `netlify/lib/session.ts`.

Without this setup the site still works fully with **Use without an account**.

1. **Google Cloud Console** (you can reuse the Atomic Tracker project):
   - APIs & Services > Library: **enable the Google Drive API**.
   - OAuth consent screen: scopes `openid`, `email`, `profile` and `.../auth/drive.file`. While the app is in Testing, add your Google account as a **test user**.
   - Credentials > Create credentials > **OAuth client ID** > **Web application**. Under **Authorized redirect URIs**, add:
     - `https://<your-site>.netlify.app/api/auth/callback/google`
     - `http://localhost:4173/api/auth/callback/google` (optional, for local testing)

   You can add these redirect URIs to Atomic Tracker's existing client instead. Google's consent screen would then show Atomic Tracker's app name.
2. **Netlify > Site configuration > Environment variables**, add:

   | Key | Value |
   |---|---|
   | `AUTH_GOOGLE_ID` | the client ID |
   | `AUTH_GOOGLE_SECRET` | the client secret |
   | `AUTH_SECRET` | output of `openssl rand -base64 32` |
3. **Redeploy:** Deploys > Trigger deploy. Functions read these at runtime, so no code change is needed.

**Local testing:** put the same three values in `web/.env.local`, then run `npm run build && npm run preview` and open <http://localhost:4173>. The functions run inside Vite's server.

## Privacy

- Camera frames are analyzed in the browser and never uploaded.
- The face model runtime is served from the site itself. The model weights load from Google's MediaPipe storage.
- Photos and scores stay in this browser and, if you choose, in a folder on your device, a backup file, or the single Drive folder you connect.
- There are no analytics, ads or databases. Sign-in runs in stateless Netlify Functions: the Google refresh token lives only in an encrypted cookie in your browser, and Drive requests are passed straight through to Google.
- The privacy page is `public/privacy.html`.
