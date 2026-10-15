# PuffyMeter

A daily face-scan app for iPhone that tracks cosmetic facial puffiness with Apple Fitness–style rings, charts, goals, challenges and awards. Photos and score files go only to a Google Drive folder the user chooses.

> Cosmetic wellness tracking. Not a medical diagnosis.

## Project layout

| Path | What's there |
|---|---|
| `PuffyKit/` | Swift package holding almost everything: models, scoring, rings, streak, challenge, award and insight engines, the Drive REST client, the upload queue (`AppModel`), the design system and every SwiftUI screen. Compiles for iOS 18+ and macOS 15+, so it can be checked with `swift build`. |
| `PuffyMeter/` | The iOS app target: entry point, live services (Google Sign-In, HealthKit, notifications, Face ID, Keychain), the ARKit face camera with an AVFoundation + Vision fallback, assets and the privacy manifest. |
| `PuffyMeterWidgets/` | WidgetKit extension: Home Screen small and medium widgets, Lock Screen circular, rectangular and inline widgets. Widgets never show a face photo. |
| `PuffyMeterUITests/` | XCUITests that run against mocked services. |
| `docs/adr/` | Architecture decisions. Start with `001-drive-scope.md`. |
| `project.yml` | XcodeGen spec. `PuffyMeter.xcodeproj` is generated from it. |

## Getting started

1. Install the tools: Xcode 26 or later, plus `brew install xcodegen`.
2. Generate the project:
   ```bash
   xcodegen generate
   ```
3. Open `PuffyMeter.xcodeproj` and run the **PuffyMeter** scheme on a simulator.

### Launch modes (Scheme → Run → Arguments)
- **`-DemoMode`**: seeded with the design mockup data (Alex Morgan, Oct 2–8 scores, awards, challenges) on a fixed clock of Oct 8, 2026, 8:02 AM. Use it for screenshots and design reviews.
- **`-UITestMode`**: a fresh install with every service mocked, so onboarding runs without a Google account.
- No argument: the real services. The Simulator always uses a simulated camera, since it has no front camera.

## Install on your iPhone

You need a Mac with Xcode, an iPhone on **iOS 18 or later**, and a USB cable. A free Apple ID works; the paid Developer Program isn't required.

1. **Add your Apple ID to Xcode.** In Xcode > Settings > Accounts, click **+**, choose **Apple ID** and sign in. A team called "Your Name (Personal Team)" appears.
2. **Create your local signing file.**
   ```bash
   cp Config/Local.example.xcconfig Config/Local.xcconfig
   ```
   In `Config/Local.xcconfig`:
   - Change `PUFFY_BUNDLE_ID` and `PUFFY_APP_GROUP` to something unique, for example `com.yourname.puffymeter`.
   - Free Apple ID: keep the two "Personal Team" lines, because Sign in with Apple isn't available on free accounts.
   - Delete the `DEVELOPMENT_TEAM` line. You'll pick the team in Xcode in step 4 instead.
3. **Regenerate the project and open it.**
   ```bash
   xcodegen generate
   ```
   ```bash
   open PuffyMeter.xcodeproj
   ```
4. **Choose your team.** In Xcode's left sidebar, click **PuffyMeter** (the blue project icon). For both the **PuffyMeter** and **PuffyMeterWidgets** targets, open **Signing & Capabilities** and set **Team** to your Personal Team. Leave "Automatically manage signing" on.
5. **Prepare the iPhone.**
   - Connect it with the cable, unlock it, and tap **Trust** when asked.
   - Turn on Developer Mode: Settings > Privacy & Security > **Developer Mode**. Turn it on, restart, then confirm.
6. **Run it.** In Xcode's toolbar, choose your iPhone as the run destination and press **Run** (⌘R). The first build takes a few minutes.
7. **Free Apple ID only: trust the app.** The first launch is blocked until you trust it. Go to Settings > General > **VPN & Device Management**, tap your Apple ID and tap **Trust**. Then open PuffyMeter.

On the sign-in screen, choose **Use without an account** to keep scans on the iPhone. "Continue with Google" only works once the Google steps below are done.

**Limits on a free Apple ID:**
- The app stops opening after **7 days**. Reconnect the phone and press Run in Xcode to reinstall. Your data is kept.
- You can have at most 3 apps installed this way.

**Troubleshooting:**
- **"Failed to register bundle identifier":** change `PUFFY_BUNDLE_ID` to something more unique, then run `xcodegen generate` again.
- **HealthKit signing error on a free account:** in `PuffyMeter/PuffyMeter-PersonalTeam.entitlements`, delete the two `com.apple.developer.healthkit` entries and rebuild. Health sync will be off.
- **iPhone not listed in Xcode:** check that it's unlocked, trusted and has Developer Mode on. Window > Devices and Simulators shows its status.

## Google Sign-In and Drive setup (needed for real accounts)

1. In Google Cloud Console, create a project and **enable the Google Drive API**.
2. Set up the **OAuth consent screen**. Add the scopes `openid`, `email`, `profile` and `https://www.googleapis.com/auth/drive.file`. `drive.file` is non-sensitive, so no security assessment is needed.
3. Create an **OAuth client ID** of type iOS, using the bundle ID `com.puffymeter.app` (or your own bundle ID).
4. Copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig` (it's git-ignored) and fill in:
   ```
   GOOGLE_CLIENT_ID = <client-id>.apps.googleusercontent.com
   GOOGLE_REVERSED_CLIENT_ID = com.googleusercontent.apps.<client-id>
   ```
5. Run `xcodegen generate` again, then build.

To run on a device you need a development team with these capabilities: App Groups (`group.com.puffymeter.shared`), HealthKit, Sign in with Apple and Keychain Sharing.

## Web app (Netlify)

`web/` contains the same app as an installable website (Vite, React and TypeScript, with MediaPipe for on-device face analysis). Netlify is configured by `netlify.toml` in the repo root. Setup, demo mode (`/?demo`) and the deploy steps are in [web/README.md](web/README.md).

## Tests

```bash
cd PuffyKit
swift test
```

```bash
cd PuffyKit
swift run PuffyKitSelfTest
```

The first command runs the Swift Testing suite and needs Xcode. The second runs a dependency-free assertion runner, so it also works with only the Command Line Tools installed.

```bash
xcodebuild test -project PuffyMeter.xcodeproj -scheme PuffyMeter -destination 'platform=iOS Simulator,name=iPhone 17'
```

This runs the UI tests.

## How the score works

`FaceAnalyzer` measures IPD-normalized metrics for the under-eyes, cheeks and jawline. It uses the ARKit face mesh on TrueDepth devices, and Vision landmarks elsewhere. `ScoringEngine` (`PuffyKit/Sources/PuffyKit/Domain/ScoringEngine.swift`) compares those metrics with the user's own reference: the baseline scan at first, then the 20th percentile of the last 30 scans.
- Each zone scores `30 + 15 × z`, clamped to the range 0–100. Lower is better.
- The overall score is a weighted average: under-eyes 0.4, cheeks 0.3, jawline 0.3.
- Low-quality captures are flagged and left out of the correlation statistics.

## Known follow-ups
- **Google Picker:** hosting the Picker so users can grant access to an *existing* Drive folder (see ADR 001). Today the in-app list shows the folders PuffyMeter can see, and "New Folder" is the main path.
- **Google "G" mark:** `GoogleMark` is a stand-in. Replace it with the official asset from Google's branding guidelines.
- **Calibration:** tune the ARKit region bounds in `FaceGeometryMetrics` and the minimum spreads in `ScoringEngine` against real captures on a device. Also check the orientation of saved front-camera photos (`ARFaceCamera.capture`).
- **Background uploads:** move the upload queue onto a background `URLSession` and a `BGProcessingTask` so uploads keep going after the app is suspended. They currently run while the app is active and resume on the next launch.
- **Privacy Policy and Terms:** the URLs (`puffymeter.app/…`) are placeholders.
