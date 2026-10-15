# PuffyMeter Web

PuffyMeter as an installable web app (PWA), built with Vite, React and TypeScript, and ready for Netlify. It has the same screens, scoring, rings, awards and Drive format as the iOS app.

| | iOS app | Web app |
|---|---|---|
| Face analysis | ARKit / Vision, on device | MediaPipe Face Landmarker, in the browser |
| Photo storage | App sandbox and your Drive folder | This browser (IndexedDB) and your Drive folder |
| Sign-in | Google, Sign in with Apple | Google, or no account |
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
- **Tests:** `npm test` runs the domain tests, which use the same numbers as the iOS PuffyKit tests.

The camera works on `localhost` and on HTTPS sites only. Netlify sites are HTTPS by default.

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

## Turn on Google sign-in and Drive (optional)

Without this, the site still works fully with **Use without an account**.

1. In Google Cloud Console, create a project and **enable the Google Drive API**.
2. Configure the **OAuth consent screen**:
   - Scopes: `openid`, `email`, `profile` and `.../auth/drive.file`. `drive.file` is non-sensitive, so no security review is needed.
   - While the app is in Testing, add yourself as a test user.
3. Create an **OAuth client ID** of type **Web application**. Under **Authorized JavaScript origins**, add your Netlify URL (for example `https://puffymeter.netlify.app`) and `http://localhost:4173`.
4. Give the site the client ID:
   - **Git deploys:** in Netlify, go to Site configuration > Environment variables, add `VITE_GOOGLE_CLIENT_ID`, then trigger a redeploy.
   - **Drag-and-drop deploys:** put `VITE_GOOGLE_CLIENT_ID=...` in `web/.env.local` (git-ignored) before running `npm run build`.

Google access tokens are kept only in the browser tab's session storage and last about an hour. When one expires, PuffyMeter shows **Reconnect**.

## Privacy

- Camera frames are analyzed in the browser and never uploaded.
- The face model runtime is served from the site itself. The model weights load from Google's MediaPipe storage.
- Photos and scores stay in this browser and, if you connect it, in the single Drive folder you choose.
- There are no analytics, ads or servers.
- The privacy page is `public/privacy.html`.
