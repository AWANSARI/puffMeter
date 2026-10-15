# PuffyMeter: iOS Implementation Prompt for Claude

> Paste everything below the line into Claude Code, run from an empty folder where the Xcode project should live. The design mockups are in `/Users/abdulwahedansari/Downloads/puffyMeter (1)/` (PNG) and `/Users/abdulwahedansari/Downloads/puffyMeter/` (PDF). Give Claude access to that folder so it can open each screen while it builds.

---

## 0. Your Role and How to Use This Document

You are a senior iOS engineer. Build **PuffyMeter**, a production-quality native iPhone app written in **Swift and SwiftUI**. It lets people take one face photo each morning, estimates a cosmetic **Puffiness Score**, saves the photo to a Google Drive folder the user picks, and motivates them with Apple Fitness–style rings, charts, goals, challenges and awards.

There are 33 design mockups (listed in section 3). **Treat them as statements of intent, not pixel-perfect specs.** They were produced quickly and contain:
- **Alignment and layout problems:** text running past card and screen edges, stray `\n` characters, clipped controls, uneven grid heights, broken ring artwork.
- **Template placeholders:** "Title", "Subtitle", "Play", "Label", "Tab 1", "Value", and a generic "A Short Title Is Best" alert.
- **Missing screens and states.**

Section 4 lists every defect I found and gives the correct behavior. Section 5 lists what's missing and specifies it. **Wherever a mockup conflicts with this document, this document wins.** Wherever both are silent, follow Apple's Human Interface Guidelines and match how the Apple Fitness and Apple Health apps behave.

Before writing code, open every PNG in the design folder and look at it. Then work through the milestones in section 15, in order. After each milestone, build the app, run it in the iOS Simulator, take screenshots of the screens you changed, and compare them against the mockups and the corrections in section 4.

---

## 1. Product Summary

- **Name:** PuffyMeter. **Positioning:** "Cosmetic wellness tracking. Not a medical diagnosis." This disclaimer appears on several screens and must stay. Never use medical language such as "diagnose", "edema", "condition" or "treatment".
- **Core loop:** morning reminder → guided face scan → on-device analysis → score and zone breakdown → photo and JSON saved to the user's Google Drive folder → rings, streaks and awards update → trends and habit correlations grow over time.
- **The three rings** (Apple Fitness style, from outside to inside):
  1. **De-Puff** (pink): closes when today's Puffiness Score is at or below the user's goal (default ≤ 35).
  2. **Scan** (lime green): closes when today's scan count reaches the goal (default 1).
  3. **Habits** (cyan): closes when the day's habit check-ins reach the goal (default 4: water, sleep, salt, alcohol).
- **Privacy promise:**
  - Photos are stored only in the single Drive folder the user picks, plus a local cache on the device.
  - Face analysis runs on-device.
  - There is no backend server, and faces are never used for advertising.
  - No face photo ever appears on the Lock Screen.

---

## 2. Technical Stack and Project Setup

| Area | Choice |
|---|---|
| Language | Swift 6 (strict concurrency on) |
| UI | SwiftUI. Use UIKit only where SwiftUI can't do the job (camera preview layer, AR view) |
| Minimum OS | iOS 18.0. Build with the Xcode 26 / iOS 26 SDK so iOS 26 users get Liquid Glass automatically (floating tab bar, glass back buttons, as the mockups show). Gate any iOS 26-only API with `if #available(iOS 26, *)` |
| Devices | iPhone only, portrait only. Must work on iPhone SE (3rd gen) through Pro Max |
| State | `@Observable` models, `@Environment` injection, async/await, actors for services |
| Persistence | SwiftData (local source of truth). The App Group container is shared with the widget |
| Charts | Swift Charts |
| Auth | Google Sign-In for iOS (`GoogleSignIn-iOS` via SPM) plus Sign in with Apple (`AuthenticationServices`) |
| Drive | Google Drive REST API v3 called directly with `URLSession` (no heavy SDK). Uploads use a background `URLSession` |
| Face analysis | ARKit `ARFaceTrackingConfiguration` on TrueDepth devices, with a Vision (`VNDetectFaceLandmarksRequest`, `VNDetectFaceCaptureQualityRequest`) fallback |
| Health | HealthKit (read sleep, water and menstrual flow) |
| Widgets | WidgetKit (Home Screen small and medium, Lock Screen circular and rectangular) |
| Security | LocalAuthentication (Face ID lock), Keychain for tokens, Data Protection `.complete` on photo files |
| Notifications | UserNotifications (local only) |
| Video | AVFoundation (`AVAssetWriter`) for time-lapse export |
| Tests | Swift Testing for unit tests, XCUITest for the main flows, snapshot tests optional |

**Targets:** `PuffyMeter` (app), `PuffyMeterWidgets` (widget extension), `PuffyMeterTests`, `PuffyMeterUITests`. Shared code lives in a local Swift package `PuffyKit` (models, scoring, design system, Drive client) so the widget can use it too.

**Capabilities / Info.plist:**
- `NSCameraUsageDescription`: "PuffyMeter uses the front camera to capture your daily face scan for a cosmetic puffiness estimate. Photos are saved only to your device and the Google Drive folder you choose."
- `NSFaceIDUsageDescription`: "Use Face ID to keep PuffyMeter private."
- `NSHealthShareUsageDescription`: "PuffyMeter reads sleep, water and cycle data to show personal patterns alongside your scores. It never writes to Health."
- HealthKit capability, Sign in with Apple, App Groups (`group.com.puffymeter.shared`), Background Modes (background fetch, background processing), Keychain sharing.
- Google URL scheme (reversed client ID). Put the `GIDClientID` in an `xcconfig` that is **not committed**. Provide `Secrets.example.xcconfig`.

**Folder layout:**
```
PuffyMeter/
  App/            PuffyMeterApp.swift, AppRouter.swift, RootView.swift, AppLockView.swift
  Features/
    Onboarding/   Welcome, SignIn, DriveSetup (LimitedAccess, FolderPicker, NewFolder, Connected), Permissions, Baseline
    Summary/      SummaryView + cards (RingsCard, ScoreCard, FaceZonesCard, WeekChartCard, StreakCard, InsightCards, QuickLog)
    Scan/         ScanCameraView, ScanViewModel, AnalyzingView, ScanResultView, ComparisonSlider, UploadStatusCard
    Trends/       TrendsView, PhotoTimeline, TimeLapsePlayer, CalendarCorrelationsView, MetricDetailView
    Goals/        GoalsEditorView, ChallengesView
    Awards/       AwardsView, AwardDetailView, AwardUnlockSheet
    Profile/      ProfileView + subpages
    Celebration/  AllRingsClosedView
  Services/       AuthService, DriveService, UploadQueue, FaceAnalyzer, ScoringEngine, HealthService, NotificationService, AwardEngine, ChallengeEngine, InsightEngine, ExportService, AppLockService
  Resources/      Assets.xcassets (app icon, colors, award badge images), Localizable.xcstrings
PuffyKit/         Models, DesignSystem, Scoring, DriveClient, Shared (App Group)
PuffyMeterWidgets/
```

---

## 3. Design Inventory (what each mockup shows)

Every mockup frame is iPhone 16 Pro sized (402 × 874 pt). Screens marked "Dark + Light" have both variants; the rest are dark only, and you must produce the light variant yourself (section 6).

| # | File | What it shows |
|---|---|---|
| 1 | Welcome · Daily clarity | Onboarding page 1. Header: small ring logo, "PuffyMeter", pink "Skip". Large rounded portrait photo, overlapped at its lower left by a dark card: "32" (pink), "Looking ahead", "↓ 8 from yesterday" (green), "Puffiness Score". Eyebrow "MEET PUFFYMETER" (pink caps), headline "A fresh perspective. Every morning.", body "One quick scan. A clearer picture of your face's everyday changes." Page dots (1 of 3), pink primary button, disclaimer footer |
| 2 | Welcome · Close your rings | Page 2. Large triple rings. "MAKE IT A DAILY RITUAL", "Small habits. Visible progress.", "Scan, check in with your habits, and work toward your personal De-Puff goal." |
| 3 | Welcome · Private by design | Page 3. Pink outlined folder-with-lock icon. Card: "PuffyMeter Daily", "My Drive / PuffyMeter Daily", green "Only this folder is connected". "PRIVATE BY DESIGN", "Your face. Your folder.", "Keep your daily photos in a Google Drive folder you choose. You stay in control." |
| 4 | Sign in | Rings logo, "PuffyMeter", "Your daily check-in, all in one place.", subtitle about saving progress and connecting a private photo folder. Two buttons: pink primary and dark secondary with blue label. Privacy card with green shield: "Your privacy comes first", "Photos stay in the Drive folder you choose. Your face is never used for advertising." Terms footer |
| 5 | Google Drive · Limited access | Blue folder-lock icon. "One folder. Nothing else." "PuffyMeter can create and save photos only in the folder you select, and does not browse the rest of your Drive." Table: Daily scan photos → JPG, Scores and notes → JSON, Your other files → No access. Footnote about disconnecting in Profile and that deleting the app won't delete Drive photos. Primary button |
| 6 | Google Drive · Folder picker | Account card (Alex Morgan, alex.morgan@gmail.com). "My Drive" breadcrumb with blue "New Folder". Search field. Folder list: PuffyMeter Daily (checkmark), Personal, Photos, Wellness (chevrons). "Selected: My Drive / PuffyMeter Daily. Only this folder will be accessible to PuffyMeter." Primary button |
| 7 | Google Drive · New folder | Blue folder-plus icon. "Create a dedicated home for your daily photos and scan notes." FOLDER NAME text field. Location card: Location → My Drive, path preview, green "Limited to files saved by PuffyMeter". Primary and secondary buttons |
| 8 | Google Drive · Connected | Green check circle. "Your daily photos have a home." "New scans will be backed up automatically when you're online." Card: folder name, path, email, green "Connected · Access to this folder only". Primary and secondary buttons |
| 9 | Permissions setup | Intro line. Three cards: **Camera** (pink "Required" pill, description, pink "Allow" button); **Notifications** (toggle, "A gentle nudge to scan at the same time each day.", "Morning reminder 8:00 AM"); **Apple Health** (cyan "Optional" pill, "Read sleep and water to show personal patterns…", blue text button). Primary button. "You can continue without notifications or Health." |
| 10 | Baseline · First scan | Camera card with "FRONT CAMERA" chip, lime oval face guide, cyan face-mesh wireframe, round dark countdown bubble near the chin. "Let's set your baseline". Checklist: Centered, Good lighting, Neutral face (green check circles). "Face the camera at eye level in even light. Your first score is a starting point, not a verdict." Primary button |
| 11 | Scan · Countdown (Dark) / Scan · Light | Same camera layout with countdown "3". "Hold still. You're ready." "Auto-capture in 3 seconds. Yesterday's photo is faintly overlaid for alignment." Tab bar visible |
| 12 | Scan · Analyzing | Photo with a cyan horizontal scan line. "A moment for you." "Comparing today's face zones with your recent scans." Step list: ✓ Photo quality checked (green), Estimating face zones… (cyan, in progress), Preparing your comparison (gray, pending). "Your score is a cosmetic estimate, not a diagnosis." |
| 13–16 | Scan result · uploading / saved / failed / offline | Score card: "32 / 100 · Lower is better", "↓ 8 points from yesterday's 40". "Yesterday · 40 / Today · 32" before/after split image with a round ↔ handle, plus a slider below it. Three zone tiles: Under-eyes 38, Cheeks 29, Jawline 26. "Notes & tags" text field. Tag chips: 8h sleep, Low salt, No alcohol (cyan). Upload card variants: **uploading** (cyan cloud-up, "Uploading to Google Drive", "Daily photo and notes · 68%", cyan progress bar); **saved** (green cloud-check, "Saved to Google Drive", "My Drive / PuffyMeter Daily", "2026-10-08_0802.jpg · Synced just now"); **failed** (pink cloud-x, "Upload failed", "Your scan is safe on this iPhone.", plus a template alert); **offline** (gray cloud-slash, "Offline · Upload queued", "Will sync when you're back online.", "Saved locally · 1 item waiting to sync"). Primary button. "Lighting and expression can affect your score." |
| 17 | Activity · All rings closed | Green date eyebrow "THURSDAY, OCTOBER 8", large rings, "All rings. All you.", "You reached your De-Puff goal, scanned, and checked in with all four habits." Streak card: pink flame, "7 days of showing up", "A little consistency goes a long way." Primary button |
| 18 | Summary (Dark + Light) | Pink "Edit" in the navigation bar. **Rings card** with legend De-Puff 32 / ≤35, Scan 1 / 1, Habits 3 / 4 and the caption "One more habit check-in to close all three rings." **Puffiness Score card**: 32, ↓ 8 vs yesterday, 0–100 · Lower is better, Scanned at 8:02 AM, photo thumbnail on the right, green cloud "Saved in PuffyMeter Daily". **Face zones** list: Under-eyes 38 ↓10, Cheeks 29 ↓7, Jawline 26 ↓5. **Last 7 days** section with pink "Trends ›": "40 average · ↓ 6 from last week", bars F–T (48, 44, 41, 39, 36, 40, 32) with today bright pink and the others dim, "Oct 2–8 · Lower is better". **7-day scan streak** card: flame, 7 mini rings, "Your morning routine is taking shape." **Daily insights**: moon icon "A well-rested pattern" ("Your scores tended to be lower after 7+ hours of sleep over the last 2 weeks." / "Personal association · Not proof of cause") and "Same light. Clearer comparisons." ("You've scanned within 15 minutes of 8 AM all week. Keep your routine steady."). **Quick log** chips: + Water · 1.5 / 2 L, Sleep · 8h, Salt · Low, Alcohol · None. Disclaimer footer. Floating tab bar |
| 19 | Trends (Dark + Light) | Segmented control D / W / M / 6M / Y. Score card: "40 weekly average", "↓ 6 points vs previous week", bar chart with a horizontal goal line, "Oct 2–8 · Lower is better · Goal ≤35", pink "Goal: 35 or lower · Edit goal ›". **Photo timeline** with "See all ›": three thumbnails captioned Oct 3 · 44, Oct 7 · 40, Oct 8 · 32. Time-lapse play button. Card "Your days, connected" ("Explore your calendar and the habits that show up alongside changes.") with "Calendar & correlations ›". Footer "Compare trends, not single numbers. Facial appearance naturally varies day to day." |
| 20 | Trends · Time-lapse | Large photo. "Oct 8 · 8:02 AM" with pink "Score 32" on the right. Pink progress scrubber. Controls: "1×" speed pill, previous, pause, next, "7 / 7" counter. "Same framing · Original photos · No smoothing". Secondary button |
| 21 | Trends · Calendar and correlations | "October 2026" month grid (Mon-first) with ‹ › arrows. Days with scans are tinted pink by score (brighter = lower = better), today is bright pink, future days are gray. Legend "Lower score ▮▮▮▮ Higher". Selected-day line "Oct 8 · Score 32 · 8h sleep · 1.5 L water". **Habit correlations** ("Patterns in your last 30 days. Associations don't establish what caused a change."): Sleep (cyan "−7 points", "Average score after 7+ hours vs less than 7 hours.", "22 paired days · Moderate association"); Water ("−4 points", "Average score on days with 2 L logged vs less.", "19 paired days · Small association"); Salt (pink "+6 points", "Average score after 'high salt' evenings vs 'low salt'.", "16 paired days · Personal tags"); Cycle (dashed icon, "More data needed", "Log cycle days in Apple Health to explore your own pattern.", "8 paired days · No conclusion yet"). Disclaimer footer |
| 22 | Goals · Fitness-style editor | "Make your rings work for you. Adjust your goals as your routine evolves." Three cards: De-Puff (pink) 35 "Score or lower" ("Close this ring when your score meets your goal. Lower is better."); Scan (green) 1 "Scan per day" ("One consistent morning scan is enough."); Habits (cyan) 4 "Check-ins per day" ("Water, sleep, salt, and alcohol. Log honestly, not perfectly."). Each card has a − / + capsule stepper. Primary button. "Goals support your routine. They are not medical targets." |
| 23 | Goals · Monthly challenges | **Morning momentum** (pink sunrise icon, "Scan on 20 different mornings this month. Consistency earns the October Star.", "8 / 20 days scanned", pink progress bar, "23 days left · You're on pace"). **Hydration check-in** (cyan, "Log your water on 15 days. No perfect amount required, just a check-in.", "6 / 15", cyan bar, pill "Joined · Ends Oct 31", "Earn the October Water badge"). **Next month: A little wind-down** ("November's sleep check-in challenge opens on Nov 1."). Secondary button |
| 24 | Awards (Dark + Light) | "JUST EARNED" hero card: pink flame medal, "7-day streak", "You showed up every morning. That's how routines are built." Filter chips: All awards (selected, pink), Streaks, Habits, Challenges. "Your collection" 2-column grid: First scan (lime hexagon camera badge, Sep 9, 2026), 7-day streak (pink flame coin, Earned today), Habit starter (cyan water-drop coin, Sep 12, 2026), 30 scans (locked dark shield, 18 / 30 scans), Perfect week (locked dark rings coin, "Close all rings for 7 days"), October star (locked dark star, 8 / 20 mornings). Footer "Earned through consistency, not a perfect score." |
| 25 | Awards · Unlock modal | Bottom sheet over a dimmed Awards screen: "NEW AWARD" (pink), large flame medal, "A week of showing up.", "You scanned for 7 days in a row. Here's to the routine you're building.", "7-day streak · October 8, 2026", primary button |
| 26 | Profile (Dark + Light) | Account card: pink "AM" initials avatar, Alex Morgan, email, "Connected with Google". **PHOTO STORAGE**: Google Drive row → "Connected ›", "My Drive / PuffyMeter Daily", "Last sync: Today at 8:02 AM · All scans saved". **YOUR DAILY ROUTINE**: Morning reminders toggle, reminder time 8:00 AM ›, plus two unlabeled rows (Goals, Challenges). **HEALTH & PRIVACY**: Apple Health sync toggle ("Read sleep, water, and cycle data"), Face ID lock toggle ("Require Face ID when opening PuffyMeter"). **YOUR DATA**: two blue rows and one red row (unlabeled). Footer "PuffyMeter 1.0 · Cosmetic wellness, not diagnosis. Your photos are never used for advertising." |
| 27 | Widgets (Dark + Light) | Medium widget: rings plus "PuffyMeter · Today", 32, ↓ 8 vs yesterday, "1 scan · 3 / 4 habits". Small widget: "Puffiness Score", 32, ↓ 8 points, 7-day streak. "Updates after a scan or habit check-in. Tap to open Summary." Lock Screen preview (still template content). "Privacy first: no face photo on your Lock Screen." |

---

## 4. Design Defects You Must Correct

### 4.1 Global defects (they appear on almost every screen)

1. **Placeholder navigation titles.** Every "Title / Subtitle" header is a placeholder. Use the real titles in the table in section 4.3. Use a standard large-title navigation bar. Show the subtitle (secondary, 15 pt) under the large title only where section 4.3 specifies one.
2. **Placeholder button labels.** Every "Play" and "▶ Play" button is a placeholder. Use the labels in section 4.3. No button in the app shows a play icon except the time-lapse play control.
3. **Placeholder tab bar.** "Label", "Tab 1…Tab 5", stars, diamonds and shapes are placeholders. Implement a standard `TabView` with five tabs, SF Symbols and labels: **Summary** (`circle.circle`), **Trends** (`chart.bar.xaxis`), **Scan** (`faceid`, center position), **Awards** (`medal.fill` or `rosette`), **Profile** (`person.crop.circle`). Selected tint is the app pink. On iOS 26 the system draws the floating Liquid Glass bar shown in the mockups. Do not build a custom floating bar.
4. **Literal `\n` in strings.** For example "Your daily check-in,\nall in one place.", "One folder.\nNothing else.", "Your daily photos\nhave a home.", "All rings.\nAll you.", "Selected: …\nOnly this folder…", and the Profile footer. Render each as a real line break, or as two separate text styles.
5. **Text overflowing its container.** Many body lines are single unwrapped lines that run off the card or the screen: welcome bodies, sign-in subtitle, privacy card, limited-access paragraphs, permission descriptions, insights, footers, the goal description, challenge descriptions, the "Just earned" description, the all-rings body and the Profile footer. **All body text must wrap** (`.fixedSize(horizontal: false, vertical: true)` and `.multilineTextAlignment`) within 16 pt side margins and 16 pt card padding. Nothing may be clipped at any Dynamic Type size up to AX3.
6. **Inconsistent frame widths and offsets.** Some mockups are wider than the device, and "Scan result · failed" and Profile are shifted horizontally. Lay everything out against the safe area with consistent 16 pt horizontal margins.
7. **Inconsistent back navigation.** Some screens show a circular glass back button and others a pink "‹ Back" text button. Use the system navigation back button everywhere; iOS 26 renders it as glass. **Root tab screens (Summary, Trends, Awards, Profile) must not have a back button.** The mockups wrongly show one.
8. **Broken ring artwork.** The ring renders show dark track circles with a clipped lime/cyan semicircle stuck to the top, which is an export bug. Implement proper Activity Rings (section 6.4): three concentric rings with dim tracks, a gradient progress arc starting at 12 o'clock and running clockwise, round end caps, and a shadowed cap with a second lap when progress exceeds 100%. This applies to Welcome 2, Sign in, the Summary rings card, the streak mini rings, All rings closed and the widgets.
9. **Hero numbers are too small.** Scores such as "32" in the score cards, widgets and result screen are drawn at body size in pink. Use the hero metric style (SF Pro Rounded, Bold or Heavy, 34–56 pt depending on context; see section 6.2). Zone values on Summary are already large (good). Match that weight elsewhere.
10. **Unlabeled text fields.** Text fields show "Value" with no container. Give each one a proper rounded field (secondary-grouped background, 10 pt corners, 44 pt minimum height) with a real placeholder.
11. **Light mode isn't treated consistently.** In light mode the secondary buttons are near-black fills (Trends play button), while dark mode uses a gray fill. Use a semantic secondary fill (`tertiarySystemFill`) so both modes look correct.

### 4.2 Screen-by-screen defects

- **Welcome (all 3 pages):**
  - The header crams the logo, the name and "Skip" together on the left. Logo and name go leading; **Skip goes trailing** (pink, 17 pt, regular weight).
  - The body text is cut off on pages 2 and 3.
  - The button label should be "Continue" on pages 1–2 and "Get Started" on page 3.
  - Swiping between pages must work. Use a `TabView` with `.page` style and custom pink dots.
  - On page 1 the overlapping score card should sit 16 pt in from the photo's leading edge and overlap its bottom by about 56 pt. Give the score a hero numeral.
- **Sign in:**
  - "PuffyMeter" is tiny. Make it Title 1 Bold.
  - Fix the `\n` in the tagline.
  - Use the full subtitle: "Sign in to save your progress and connect your private photo folder."
  - Primary button: **"Continue with Google"** with the official multi-color Google "G" mark on a white circle at the leading edge.
  - Secondary button: the system `SignInWithAppleButton` (white style in dark mode, black in light mode), required by App Store Guideline 4.8.
  - The privacy card text must wrap.
  - Footer: "By continuing, you agree to our Terms of Service and Privacy Policy." Both terms are links.
- **Limited access:**
  - Title "Google Drive", subtitle "Limited access".
  - The third table row has no icon. Add `lock.fill` in secondary color.
  - The paragraphs overflow; make them wrap.
  - Button: **"Choose Folder"**.
- **Folder picker:**
  - Title "Choose a Folder".
  - "My Drive" and "New Folder" sit on different baselines. Put them in one `HStack` with `.firstTextBaseline` alignment.
  - The divider under them is inset incorrectly. Remove it.
  - "Value" becomes a `.searchable` field with the placeholder "Search folders".
  - Rows navigate into subfolders and push a breadcrumb.
  - The selected row shows a pink `checkmark` and the others show a chevron. Tapping a row's leading area selects it; tapping the chevron opens it.
  - Footer: "Selected: My Drive / PuffyMeter Daily", then on a new line "Only this folder will be accessible to PuffyMeter."
  - Button: **"Use This Folder"**, disabled until a folder is selected.
- **New folder:**
  - Present it as a sheet with the title "New Folder".
  - The text field has no container and an orphan cursor. Use a proper field, pre-filled with **"PuffyMeter Daily"** and auto-focused.
  - The Location card's path preview must update live as the name is typed.
  - Buttons: **"Create Folder"** (primary, disabled when the name is empty or only whitespace) and **"Cancel"** (secondary).
- **Connected:**
  - Title "Connected".
  - Primary button **"Continue"**, secondary **"Change Folder"**.
  - Animate the green checkmark drawing in (trim from 0 to 1 with a spring).
- **Permissions:**
  - Title "Permissions", subtitle "Set up your morning".
  - The Camera card button reads **"Allow Camera"**. Once granted, it turns into a green "Allowed ✓" label.
  - Health button: **"Connect Apple Health"**. Once connected, it shows "Connected".
  - Bottom button: **"Continue"**, disabled until the camera is granted.
  - Tapping the reminder time opens a wheel time picker.
  - Descriptions are clipped; make them wrap.
- **Baseline / Scan camera:**
  - Baseline title is "Baseline" with subtitle "Your first scan". The daily scan title is "Scan" with subtitle "Daily check-in".
  - The countdown bubble overlaps the chin and the bottom of the oval, and shows "•" before it starts. Move it **below the oval, centered, inside the camera card**. Hide it until the countdown starts, then show 3 → 2 → 1 in SF Pro Rounded Heavy 40 pt with a scale-and-fade animation.
  - Primary button: **"Capture Baseline"** or **"Capture Now"**. It is a manual fallback, since auto-capture fires when all checks pass.
  - The camera card keeps a 3:4 aspect ratio, at 20 pt corners, full width.
  - The "FRONT CAMERA" chip sits top-leading at a 12 pt inset.
  - The checklist items turn from gray outline to green filled as each check passes, live.
- **Analyzing:**
  - Title "Analyzing".
  - The scan line should sweep top to bottom and back (1.6 s, ease-in-out, repeating).
  - Step states animate from pending to active to done.
  - There are no buttons. Navigate to the result automatically when analysis finishes, with a minimum display time of 1.5 s so it never flashes.
- **Scan result:**
  - Title "Today's Scan", subtitle "Thursday, Oct 8 · 8:02 AM".
  - The score card shows "32" as a tiny pink number. Make it a hero numeral (56 pt rounded) with "/ 100 · Lower is better" beside it.
  - The before/after slider below the image duplicates the on-image handle and is blue. **Remove the separate slider.** Make the on-image ↔ handle draggable, with haptics at 0%, 50% and 100%.
  - Zone tiles: put the label at the top and the value 28 pt rounded below it, with equal heights.
  - "Notes & tags" label plus a field with the placeholder "Add a note" (multi-line, 3-line max visible).
  - Tag chips are toggleable and auto-filled from today's quick log; add a "+ Tag" chip.
  - The primary button reads **"Done"**.
  - **Failed state:** replace the template alert ("A Short Title Is Best" with "Value" fields) with an inline upload card. It shows the pink cloud-x, "Upload failed", "Your scan is safe on this iPhone.", and a trailing **"Retry"** text button. Show a short error reason in secondary text, for example "Google Drive session expired" or "Folder not found". For auth errors, the action reads **"Reconnect"** and starts the Google sign-in flow again.
- **All rings closed:**
  - Body text is cut off; make it wrap and center it.
  - Primary button **"Done"**, plus a secondary **"Share"** that renders a share card image (section 5).
  - The rings animate closing in sequence (outer → middle → inner, 0.6 s each), with a success haptic and confetti built with a `Canvas` particle system or `SpriteView`.
- **Summary:**
  - Title "Summary", subtitle is today's date ("Thursday, October 8"). Remove the back button.
  - "Edit" opens Goals.
  - The rings in the rings card are clipped at the top; give the ring a fixed 168 pt size with 16 pt padding.
  - The Puffiness Score card leaves a large empty gap under the text. Lay it out as a 2-column `HStack`: text column on the left (hero score), 112 × 140 pt photo on the right with 12 pt corners, and the "Saved in PuffyMeter Daily" status pinned at the bottom.
  - The insight bodies are cut off; make them wrap.
  - The Quick log chips wrap with a flow layout. Each opens a log sheet (section 5).
  - Footer text wraps.
- **Trends:**
  - Title "Trends", no back button.
  - Play button: **"Play Time-lapse"** with `play.fill`, pink tinted. Use a secondary fill in both modes; never black in light mode.
  - Footer wraps.
  - The goal line is a dashed `RuleMark` with a trailing "Goal 35" annotation.
  - Implement the D, M, 6M and Y variants (section 7.3).
- **Time-lapse:**
  - Title "Time-lapse", subtitle "Oct 2–8 · 7 scans" (the active range).
  - Bottom button: **"Export Video"**, which opens the share sheet.
  - The "1×" pill cycles 0.5× → 1× → 2×.
  - The counter shows the current frame / total.
- **Calendar and correlations:**
  - Title "Calendar", subtitle "Habits & correlations".
  - Mon-first week matches the mockup, but **respect the user's locale** first weekday.
  - Tapping a day selects it (pink outline) and updates the detail line.
  - Use a fully rounded 8 pt cell with a 44 pt minimum tap target. Empty leading and trailing cells are invisible, not gray boxes.
  - The intro line wraps.
- **Goals editor:**
  - Title "Goals", subtitle "Change your daily goals".
  - The −/+ capsule steppers are clipped at the bottom. Draw the full capsule (96 × 36 pt, separator in the middle) and vertically center it against the goal value.
  - Make the goal value a hero numeral (34 pt rounded, in the ring color).
  - Description text wraps.
  - Button: **"Save"**.
  - Ranges: De-Puff 10–90 in steps of 1; Scan 1–3; Habits 1–4.
- **Monthly challenges:**
  - Title "Challenges", subtitle "October 2026".
  - Descriptions wrap.
  - Unjoined challenges show a pink **"Join Challenge"** button; joined challenges show the "Joined · Ends Oct 31" pill.
  - Bottom secondary button: **"Past Challenges"**.
- **Awards:**
  - Title "Awards", no back button.
  - The grid cards have unequal heights (Habit starter is shorter). Use a `LazyVGrid` with 2 flexible columns and a **fixed card height of 192 pt**, with the badge 88 pt.
  - The "Just earned" description wraps.
  - Chips filter the grid with animation.
  - Tapping a badge opens Award detail (section 5).
- **Unlock modal:**
  - "A week of showing up." is right-aligned while everything else is centered. Center it and make it Title 3.
  - Sheet: `.presentationDetents([.medium, .large])`, grabber visible.
  - Buttons: primary **"Done"** and secondary **"Share"**.
  - The badge does a 3D Y-axis flip-in with a specular shine sweep.
- **Profile:**
  - Title "Profile", no back button.
  - Fill in every unlabeled row:
    - PHOTO STORAGE: `externaldrive` icon, **"Google Drive"** → "Connected ›" (opens Drive settings).
    - YOUR DAILY ROUTINE: Morning reminders toggle; **"Reminder time"** → 8:00 AM; **"Goals"** ›; **"Challenges"** ›.
    - YOUR DATA: **"Export scores (CSV)"** ›; **"Export time-lapse"** ›; **"Delete All Data"** (red).
    - Add a final section with **"Sign Out"** (red) and a **"Privacy Policy"** link.
  - Each row has a leading SF Symbol in the pink accent, a 44 pt minimum height and inset separators. Use a `List` with `.insetGrouped` style.
  - Fix the footer `\n` and overflow.
  - Remove the horizontal offset.
- **Widgets:**
  - "Widget Name" labels and dashed placeholder boxes are design-tool artifacts. Do not render them.
  - The Lock Screen preview still shows a template calendar event. Implement the real Lock Screen widgets (section 9).
  - In light mode the score text runs over the dashed box. Lay out the widgets with proper padding (`.containerBackground`).

### 4.3 Final titles and button labels

| Screen | Large title | Subtitle | Primary button | Secondary |
|---|---|---|---|---|
| Welcome 1–3 | (none; custom header) | n/a | Continue / Continue / Get Started | Skip (nav) |
| Sign in | (none; centered hero) | n/a | Continue with Google | Sign in with Apple |
| Limited access | Google Drive | Limited access | Choose Folder | n/a |
| Folder picker | Choose a Folder | Google Drive | Use This Folder | New Folder (nav) |
| New folder (sheet) | New Folder | n/a | Create Folder | Cancel |
| Connected | Connected | Google Drive | Continue | Change Folder |
| Permissions | Permissions | Set up your morning | Continue | Allow Camera / Connect Apple Health (in cards) |
| Baseline | Baseline | Your first scan | Capture Baseline | n/a |
| Scan | Scan | Daily check-in | Capture Now | n/a |
| Analyzing | Analyzing | n/a | n/a | n/a |
| Scan result | Today's Scan | {weekday, Mon d · h:mm a} | Done | Retry / Reconnect (in card) |
| All rings closed | (none; centered hero) | n/a | Done | Share |
| Summary | Summary | {Weekday, Month d} | n/a | Edit (nav) |
| Trends | Trends | n/a | Play Time-lapse | n/a |
| Time-lapse | Time-lapse | {range · n scans} | Export Video | n/a |
| Calendar | Calendar | Habits & correlations | n/a | n/a |
| Goals | Goals | Change your daily goals | Save | n/a |
| Challenges | Challenges | {Month yyyy} | n/a | Past Challenges |
| Awards | Awards | n/a | n/a | n/a |
| Award unlock | (sheet) | n/a | Done | Share |
| Profile | Profile | n/a | n/a | n/a |

---

## 5. Missing Screens and States to Design and Build

The mockups don't cover these. Build them in the same visual language.

1. **Launch screen:** black background with the centered ring logo (light mode: `systemGroupedBackground`). It hands off to Welcome on first launch, or to App Lock / Summary on later launches.
2. **Google account flow:** use the system `ASWebAuthenticationSession` presented by GoogleSignIn. Show a loading overlay while the token exchange runs. Error cases: the user cancels (stay on Sign in, no error banner); network failure (inline banner "Couldn't reach Google. Check your connection and try again.").
3. **Sign in with Apple path:** Apple ID covers the app account. The user must **still connect Google Drive** for photo storage, but Google sign-in then happens on the Limited access screen ("Connect Google Drive" button replaces "Choose Folder" until authorized). Store the Apple user ID in the Keychain.
4. **Folder picker states:** loading skeleton rows, an empty folder ("No folders here. Create one with New Folder."), a search with no results, an error with Retry, and pull-to-refresh.
5. **Scan guidance states:** live coaching chips appear above the checklist and replace "Hold still. You're ready." when needed:
   - No face found: "Center your face in the oval"
   - Too far: "Move a little closer"
   - Too close: "Move back slightly"
   - Head tilted (roll or yaw > 8°): "Level your head"
   - Low light: "Find softer, even light"
   - Expression not neutral (smile or mouth open blendshape > 0.3): "Relax your face"
   - More than one face: "Only one face, please"
   The oval turns orange while any check fails and lime when all pass. A **ghost overlay** of the previous scan shows at 18% opacity, with a toggle button (`square.on.square`) at the top-trailing corner of the camera card.
6. **Camera denied state:** a card with "Camera access is off", a "Open Settings" button (`UIApplication.openSettingsURLString`) and an explanation.
7. **Already scanned today:** when the user opens the Scan tab after today's scan, show today's result summary with the options "Retake today's scan" (it replaces today's photo, with a confirmation; the old Drive file is overwritten or trashed) and "View result".
8. **Summary empty states:**
   - Day 0 (baseline not taken): a card "Take your baseline scan to start tracking" with a Scan button.
   - Today not scanned yet: the score card becomes "Today's scan" with the CTA "Scan now" and yesterday's score shown in secondary text. The rings show the Scan ring at 0.
   - Less than 7 days of data: the chart shows the available days and placeholder slots for the rest.
   - Insights hidden until there are at least 7 paired days, with "Insights appear after a week of scans."
9. **Quick log sheets** (`.presentationDetents([.height(320)])`):
   - **Water:** a large rounded number in liters, +0.25 / −0.25 L buttons and preset chips (250 ml, 500 ml). It optionally reads today's water from Health.
   - **Sleep:** hours stepper in 0.5 h steps. If Health is connected, it auto-fills from last night's `sleepAnalysis` (asleep stages, 6 PM to 12 PM window) and shows "From Apple Health".
   - **Salt:** a segmented Low / Medium / High control for "last evening's meal".
   - **Alcohol:** None / 1 drink / 2+ drinks.
   Each logged habit counts as one check-in toward the Habits ring. The chip shows its logged state (filled cyan background, ✓).
10. **Award detail:** a large badge you can rotate with a drag gesture (`rotation3DEffect`, spring back), the title, the earned date or progress ("18 / 30 scans" with a progress bar), the requirement text, and Share.
11. **Metric detail (from Trends):** tapping a bar scrubs the chart with a `chartXSelection` popover showing the date, the score and the photo thumbnail. There's also "Show All Data" (a list of all scans, swipe to delete with confirmation) and an "About Puffiness Score" explainer.
12. **Drive settings (from Profile):** account, folder path, file count, last sync, "Sync Now", "Change Folder", upload quality (Original / High (default, JPEG 0.85, longest side 2048 px) / Compact (1280 px)) and **"Disconnect Google Drive"** (destructive, confirmation dialog: "Your photos stay in Google Drive. New scans will be kept on this iPhone until you reconnect.").
13. **Drive auth expired banner:** a persistent banner at the top of Summary, "Google Drive needs to reconnect", with a "Reconnect" button whenever a refresh token fails.
14. **App Lock screen:** when Face ID lock is on, a blurred, branded cover shows on launch and when returning to the foreground (after more than 30 s in the background), with an "Unlock PuffyMeter" button. The app switcher snapshot is also blurred. A passcode fallback is allowed (`.deviceOwnerAuthentication`).
15. **Delete All Data:** a two-step confirmation. It removes local SwiftData records, cached photos, Keychain tokens and preferences. It **does not** delete files from Drive; offer a separate optional toggle "Also move PuffyMeter files in Drive to Trash" (default off).
16. **Export:** a CSV with the columns `date,time,score,under_eyes,cheeks,jawline,sleep_h,water_l,salt,alcohol,notes,tags,drive_file_id`, shared through `ShareLink`. Time-lapse export as MP4 (1080 × 1440, 4 fps default, with a date and score overlay toggle).
17. **Share card:** a 1080 × 1350 rendered image (via `ImageRenderer`) with the rings, the score delta and the streak. **No face photo by default**; there's an "Include photos" toggle that adds a before/after split.
18. **Notifications:**
    - Daily reminder at the chosen time: "Good morning. Time for your PuffyMeter scan."
    - Streak saver at 11 AM if there's no scan yet and the streak is at least 3: "Keep your {n}-day streak going. A quick scan takes 20 seconds."
    - Award earned (local, only if the app is in the background).
    - Notification actions: "Scan now" opens straight into the Scan tab.
19. **Dynamic Type, VoiceOver and Reduce Motion variants** for every screen (section 12).
20. **Light mode** for every screen that has only a dark mockup (section 6.1 tokens).

---

## 6. Design System (implement in `PuffyKit/DesignSystem`)

### 6.1 Color tokens
Define these in an asset catalog with "Any / Dark" appearances and expose them as `Color` statics. **Never hardcode hex values in views.**

| Token | Dark | Light | Use |
|---|---|---|---|
| `bg` | #000000 | #F2F2F7 | Screen background |
| `card` | #1C1C1E | #FFFFFF | Cards, grouped cells |
| `cardElevated` | #2C2C2E | #F2F2F7 | Chips, steppers, pills inside cards |
| `separator` | #38383A | #C6C6C8 | |
| `labelPrimary` | #FFFFFF | #000000 | |
| `labelSecondary` | #EBEBF5 @ 60% | #3C3C43 @ 60% | |
| `labelTertiary` | #EBEBF5 @ 30% | #3C3C43 @ 30% | |
| `accent` / `dePuff` | #FF1050 | #FF1050 | Primary buttons, De-Puff ring, pink text, Skip, links |
| `dePuffEnd` | #FF3A6E | #FF3A6E | Ring gradient end |
| `dePuffTrack` | #FF1050 @ 28% | #FF1050 @ 22% | Ring track / dim bars (dark ≈ #4A0D1E, light ≈ #FAC3D2) |
| `scan` | #A3E635 | #5DA80E (darker for contrast on white) | Scan ring, positive deltas, "Connected" text |
| `scanEnd` | #C6FF4A | #7BC91B | |
| `scanTrack` | scan @ 25% | scan @ 22% | |
| `habits` | #1EEAEF | #00A9B5 (darker for contrast) | Habits ring, tags, active steps, correlations |
| `habitsEnd` | #5CF3FF | #22C4D0 | |
| `habitsTrack` | habits @ 25% | habits @ 22% | |
| `link` | #0A84FF | #007AFF | Secondary text buttons ("New Folder") |
| `success` | #30D158 | #34C759 | Toggles (system green) |
| `warning` | #FF9F0A | #FF9500 | Scan guidance oval |
| `destructive` | #FF453A | #FF3B30 | Delete rows |

**Contrast check:** pink and lime text on dark backgrounds must meet WCAG AA at 4.5:1 for body text. Where light-mode lime or cyan fails, use the darker light-mode values above. Ring colors are decorative and exempt.

### 6.2 Typography (SF Pro, Dynamic Type-scaled with `@ScaledMetric` / `.font(.system(...))`)
| Style | Spec |
|---|---|
| largeTitle | 34 Bold (system `.largeTitle.bold()`) |
| title1 | 28 Bold |
| title2 | 22 Bold (section headers: "Last 7 days", "Photo timeline") |
| title3 | 20 Semibold |
| headline | 17 Semibold |
| body | 17 Regular |
| callout | 16 Regular |
| subheadline | 15 Regular (card titles, list labels) |
| footnote | 13 Regular (captions, disclaimers) |
| caption | 12 Regular / 12 Semibold caps with 0.6 tracking for eyebrows ("MEET PUFFYMETER", "JUST EARNED", "PHOTO STORAGE") |
| metricHero | SF Pro Rounded Heavy 56 (result score, widget score) |
| metricLarge | SF Pro Rounded Bold 34 (Summary score, goal values) |
| metricMedium | SF Pro Rounded Bold 28 (zone values) |
| metricSmall | SF Pro Rounded Semibold 17 (ring legend values "32 / ≤35") |

All numbers use `.monospacedDigit()` so they don't shift while animating. Animate number changes with `.contentTransition(.numericText())`.

### 6.3 Spacing, shape and elevation
- 8 pt grid. Screen margins 16. Card padding 16. Spacing between cards 12. Section header to card 8. Space above a section header 24.
- Card corner radius 16, continuous (`RoundedRectangle(cornerRadius: 16, style: .continuous)`). Camera and photo cards 20. Chips: capsule. Buttons: 12 pt radius, 52 pt height, full width.
- No drop shadows in dark mode. In light mode, cards sit flat on `bg` (Health style), except sheets.
- Primary button: `accent` fill, white 17 Semibold label, press state at 0.85 opacity plus a 0.98 scale, disabled at 35% opacity.
- Secondary button: `cardElevated` fill, `link`-colored label (or `accent` where specified).
- Pills: "Required" (`accent` text on `cardElevated`), "Optional" (`habits` text on `cardElevated`).

### 6.4 Components (build these first, each with a SwiftUI `#Preview`)
- `ActivityRings(dePuff: Double, scan: Double, habits: Double, size: RingSize)`. Sizes: `.hero` 240 (lineWidth 28), `.card` 168 (lineWidth 20), `.compact` 88 (lineWidth 11), `.mini` 32 (lineWidth 4.5). The gap between rings equals 0.15 × lineWidth.
  - Draw each ring as a track `Circle().stroke(track)` plus an `AngularGradient` progress arc (`.trim(from: 0, to: min(p, 1))`, rotated −90°, `.round` line cap).
  - When p > 1, draw a second lap and a shadow on the end-cap dot so the overlap shows (the Fitness look).
  - Animate from 0 with `.spring(response: 0.9, dampingFraction: 0.8)` on appear. Skip the animation under Reduce Motion.
  - VoiceOver label: "De-Puff 32 of goal 35 or lower, closed. Scan 1 of 1, closed. Habits 3 of 4."
- `RingLegend`: a vertical stack of name (colored, subheadline) and value (metricSmall, primary).
- `Card { }`: a container with padding, background and radius.
- `MetricDelta(value: Int, unit: String, comparison: String)`: arrow `arrow.down` or `arrow.up`. **Down (improvement) is `scan` green; up is `accent` pink; zero is secondary "No change".** Example: "↓ 8 vs yesterday".
- `ScoreBadge(score:)` and zone rows.
- `WeekBarChart(entries:, goal:)`: Swift Charts `BarMark`. The past days use `dePuffTrack` and today (or the selected day) uses `accent`. Value labels go above the bars, weekday initials below, plus a dashed goal `RuleMark`.
- `StreakRow`: 7 mini rings with weekday initials.
- `InsightCard(icon:, title:, body:, footnote:)`.
- `HabitChip(kind:, state:)` and a `FlowLayout` (a custom `Layout`).
- `ChecklistItem(title:, state: .pending/.passed)`.
- `UploadStatusCard(state:)`: uploading(progress) / saved(fileName, path) / failed(reason) / queued(count).
- `StepList` for analyzing.
- `ComparisonSlider(before:, after:)`.
- `GoalStepperCard`.
- `ChallengeCard`.
- `AwardTile`, `AwardBadgeView` (badge images come from the asset catalog; locked badges render with `.saturation(0)`, 0.55 opacity and a darker tint).
- `HeatmapCalendar`.
- `CorrelationCard`.
- `PrimaryButton`, `SecondaryButton`, `Pill`, `EyebrowText`, `SectionHeader(title:, actionTitle:, action:)`.

### 6.5 Iconography
Use SF Symbols only, except for the Google "G" mark and the award badge artwork. Mapping:
- camera `camera`, notifications `bell`, Health `heart`, sleep `moon`, water `drop`, salt `fork.knife`, alcohol `wineglass`, cycle `circle.dashed`, streak `flame`
- folder `folder`, folder-check `folder.badge.checkmark` (or a custom composite), folder-lock (custom: `folder` with a `lock.fill` overlay), new folder `folder.badge.plus`, Drive `externaldrive`
- uploading `icloud.and.arrow.up`, saved `checkmark.icloud`, failed `exclamationmark.icloud`, offline `icloud.slash`
- Face ID `faceid`, challenge `sunrise`, shield `checkmark.shield`
**Award badge art:** make 3D-looking badges as PDF/PNG assets (@2x and @3x). As a fallback, build them in SwiftUI from layered gradients: a metallic rim (`AngularGradient` of silver tones), a colored face, a symbol in the center, and a specular highlight. The mockup badges are: First scan (lime hexagon, camera), 7-day streak (pink coin, flame), Habit starter (cyan coin, drop), 30 scans (shield, "30"), Perfect week (coin, interlocking rings), October star (star).

### 6.6 Motion and haptics
- Ring fill: spring 0.9 s.
- Numbers: `.numericText()`.
- Scan checklist pass: `.sensoryFeedback(.selection)`.
- Countdown ticks: `.impact(weight: .light)`.
- Capture: `.impact(weight: .medium)` plus a white flash overlay (0.15 s).
- Result appears: `.success`.
- Upload failed: `.error`.
- All rings closed and award unlock: `.success`, plus confetti.
- Honor Reduce Motion: replace the springs and confetti with cross-fades, and stop the scan line from sweeping.

---

## 7. Feature Specifications

### 7.1 Onboarding state machine
`AppRouter` drives the root view based on persisted onboarding state:
```
welcome → signIn → driveLimitedAccess → driveFolderPicker (↔ newFolderSheet) → driveConnected → permissions → baselineScan → analyzing → result(baseline) → main(TabView)
```
- "Skip" on Welcome jumps to signIn.
- Drive connection can be skipped only with a confirmation ("Without Drive, scans are stored only on this iPhone."). Skipping marks Drive as `notConnected`. A Summary banner then offers to connect later.
- Persist each completed step so that killing the app resumes at the right step.
- The baseline result screen uses the copy "Baseline set", subtitle "Future scans compare to this one", hides the delta and shows "This is your starting point, not a verdict."

### 7.2 Authentication
- `AuthService` (actor) exposes `currentUser`, `signInWithGoogle(presenting:)`, `signInWithApple()`, `signOut()`, `restorePreviousSignIn()`, `authorizedDriveToken() async throws -> String` (refreshes when needed).
- Google scopes: `openid email profile https://www.googleapis.com/auth/drive.file`. **Use `drive.file` only.** It is a non-sensitive scope that lets the app create files and folders and access only what it created or what the user explicitly opened with the app. This keeps the "One folder. Nothing else." promise true and avoids Google's restricted-scope security assessment.
- Request the Drive scope incrementally: sign-in asks only for basic profile, and the Drive scope is added on the Limited access screen via `addScopes`.
- Store tokens in the Keychain through GoogleSignIn's built-in storage. Never log tokens.
- On launch, call `restorePreviousSignIn`. If that fails, route to signIn. If only the Drive token is invalid, keep the user signed in and show the reconnect banner.

### 7.3 Google Drive integration
**Important constraint from `drive.file`:** the app cannot list arbitrary existing folders in the user's Drive. Reconcile this with the folder picker mockup as follows:
- The **default path** is to create a new folder (`New Folder` sheet, pre-filled "PuffyMeter Daily") at the My Drive root, or inside a folder previously created by PuffyMeter. This is the primary action, and it works fully with `drive.file`.
- **"Choose an existing folder"** opens the **Google Picker** (web) in a `WKWebView`/`ASWebAuthenticationSession`-hosted page, with `setSelectFolderEnabled(true)` and `DocsView` set to folders. Picking a folder through the Picker grants `drive.file` access to it, so the app can then create files inside it.
- The **in-app folder list** in the mockup shows (a) folders PuffyMeter has created or been granted access to and (b) the account's "My Drive" root. Put a row at the bottom, "Browse Google Drive…", that opens the Picker.
- Write this decision up as an ADR in `docs/adr/001-drive-scope.md`.
- Isolate the `DriveFolderSource` protocol so that a broader `drive.metadata.readonly` implementation could be swapped in later.

`DriveService` (actor) wraps the REST API:
- `createFolder(name:parentID:) async throws -> DriveFolder` → `POST https://www.googleapis.com/drive/v3/files` with `mimeType: application/vnd.google-apps.folder`.
- `listFolders(parentID:query:)` → `GET /drive/v3/files?q='<parent>' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false&fields=files(id,name,modifiedTime)&orderBy=name`.
- `upload(fileURL:name:mimeType:parentID:appProperties:)` → **resumable upload** (`POST /upload/drive/v3/files?uploadType=resumable`, then `PUT` chunks), run on a **background `URLSession`** so uploads finish when the app is suspended. Set `appProperties` on each file: `{ "puffymeter": "1", "scanID": "<uuid>", "kind": "photo|scores" }`.
- `update(fileID:)` for retakes, and `trash(fileID:)`.
- `verifyFolder(id:)` on launch (does it still exist, and is it not trashed?). If it's missing, show "Folder not found" and a "Choose Folder" action.
- `fileCount(folderID:)` and `lastModified` for Profile.

**File naming** (the saved mockup shows `2026-10-08_0802.jpg`):
- Photo: `YYYY-MM-DD_HHmm.jpg` in the user's local time zone. Strip EXIF GPS; keep the orientation and capture date.
- Scores and notes: `YYYY-MM-DD_HHmm.json` with this schema:
```json
{
  "schemaVersion": 1,
  "scanID": "UUID",
  "capturedAt": "2026-10-08T08:02:13-07:00",
  "score": 32,
  "zones": { "underEyes": 38, "cheeks": 29, "jawline": 26 },
  "baselineScanID": "UUID",
  "delta": { "vsYesterday": -8, "vsBaseline": -12 },
  "quality": { "lighting": 0.82, "yawDeg": 2.1, "rollDeg": 0.4, "neutrality": 0.93, "method": "arkit" },
  "habits": { "sleepHours": 8.0, "waterLiters": 1.5, "salt": "low", "alcohol": "none" },
  "tags": ["8h sleep", "Low salt", "No alcohol"],
  "notes": "",
  "appVersion": "1.0 (1)"
}
```

**Upload queue (`UploadQueue`)**
- Each capture creates `UploadJob` records (photo and JSON) in SwiftData with these states: `pending`, `uploading(progress)`, `done(fileID)`, `failed(reason, retryCount)`.
- Use `NWPathMonitor` for connectivity. When offline, the UI shows the **offline** card ("Offline · Upload queued … 1 item waiting to sync").
- Retry with exponential backoff (2 s, 8 s, 30 s, 2 min, then on next foreground or `BGProcessingTask`). Retry only on transient errors: network, 5xx, 429.
- Auth errors (401 after refresh, `invalid_grant`) → failed with reason `.authExpired` → **Reconnect**.
- 404 on parent → `.folderMissing`.
- 403 `storageQuotaExceeded` → "Your Google Drive is full".
- The result screen observes the job for the current scan and switches between the four card states live.
- The local photo copy is kept (it's needed for comparisons and time-lapse) in `Application Support/Scans/` with `.complete` file protection, and is excluded from iCloud backup (`isExcludedFromBackup`).
- **Restore:** on a new device, after the Drive folder is connected, offer "Restore history from Drive". It lists the folder's `*.json` files with `appProperties has { key='puffymeter' and value='1' }`, downloads them, rebuilds SwiftData, and lazily downloads photos.

### 7.4 Scan capture
`ScanCameraView` wraps an `ARSCNView`-free `ARSession` (with ARKit face tracking on TrueDepth devices) or an `AVCaptureSession` (front wide camera, `.photo` preset) as a fallback. In both cases a `UIViewRepresentable` hosts the preview.

Live per-frame checks (throttled to 10 Hz) feed the checklist:
| Check | ARKit source | Vision fallback | Pass threshold |
|---|---|---|---|
| Face present / single | `ARFaceAnchor` count | `VNDetectFaceRectanglesRequest` | exactly 1 |
| Centered | face anchor projected center vs oval center | face bbox center | within 8% of the oval center, face height 55–75% of oval height |
| Distance | `anchor.transform` z | bbox size | 30–45 cm |
| Head pose | anchor euler angles | `VNFaceObservation.yaw/roll/pitch` | abs(yaw), abs(roll), abs(pitch) < 8° |
| Lighting | `ARFrame.lightEstimate.ambientIntensity` + face-region luminance histogram | luminance of the face crop | mean luma 0.35–0.8, left/right half difference < 15% (even light) |
| Neutral face | blendShapes `mouthSmile_L/R`, `jawOpen`, `eyeBlink_L/R`, `browInnerUp` | `VNDetectFaceCaptureQualityRequest` ≥ 0.5 | each < 0.3, eyes open |

- When **all checks pass for 0.8 s continuously**, start the 3-second countdown. If any check fails during the countdown, cancel it and show the matching guidance.
- At 0, capture a full-resolution photo (`AVCapturePhotoOutput`, or `ARFrame.capturedImage` plus a high-res frame via `captureHighResolutionFrame` on iOS 16+). Keep the `ARFaceGeometry` vertices from the same moment.
- The manual "Capture Now" button captures immediately but sets `quality.manual = true`. If checks were failing, it warns: "Score may be less reliable."
- The **ghost overlay** is the previous scan's photo, aligned using its stored face-anchor transform and rendered at 18% opacity.
- The front camera preview is mirrored, but the **saved photo is not mirrored** (true orientation), for consistency.
- Use a **screen flash**: a full-screen white overlay at maximum brightness for 0.3 s during capture when ambient light is low.

### 7.5 Face analysis and Puffiness Score (`FaceAnalyzer` + `ScoringEngine`)
This is a **cosmetic estimate**. Its job is consistency, not clinical accuracy. Implement it as a deterministic, unit-tested pipeline:

1. **Normalize:** align the face using landmarks (eye centers) to a canonical pose. Scale by the interpupillary distance (IPD) so all metrics are size-invariant.
2. **Zone metrics (raw):**
   - **Under-eyes:**
     - With ARKit: the mean forward (z) displacement of the lower-eyelid/infraorbital mesh vertex region (pick vertex indices around the lower orbit; document them in code) relative to the cheekbone plane, normalized by IPD.
     - With the Vision fallback: the infraorbital region's luminance shadow depth (mean luma of the under-eye band vs the cheek band), plus the lower-eyelid contour height from `leftEye/rightEye` landmark points.
   - **Cheeks:**
     - ARKit: the bizygomatic width at mid-cheek vertices divided by IPD, plus the mid-cheek vertex forward projection.
     - Vision: the face contour width at the 55% height level divided by IPD.
   - **Jawline:**
     - ARKit: jaw contour sharpness, measured as the curvature or angle at the gonial points and the submandibular width divided by IPD.
     - Vision: the `faceContour` landmark width at the jaw level divided by IPD, plus the contour angle at the jaw corners.
3. **Personal baseline:** the baseline scan's raw metrics are the reference. As data accrues, maintain a **rolling personal reference**: the 20th percentile of the last 30 scans' raw values. That's the user's "least puffy" typical state.
4. **Map to 0–100 (lower is better):** for each zone, `z = (raw − reference) / spread`, where `spread` is the personal standard deviation (floored at a sensible minimum until 7+ scans exist). Then `zoneScore = clamp(round(30 + 15·z), 0, 100)`. So 30 is roughly your typical good day, and higher numbers mean puffier.
5. **Overall score:** a weighted mean, `0.40·underEyes + 0.30·cheeks + 0.30·jawline`, rounded. This reproduces the mockup: 38/29/26 → 32.
6. **Quality gating:** if the quality composite is below 0.6, still produce a score but mark it `lowConfidence`. Show a "Lower confidence: lighting or angle differed" note, and exclude it from correlation stats.
7. **Determinism:** the same input image and geometry must always give the same score. Put fixture images in tests.
8. **Isolation:** `ScoringEngine` must be a pure struct with no UIKit, so it is fully unit-testable. `FaceAnalyzer` produces the `RawFaceMetrics` struct.

**Analyzing steps** shown to the user (they map to the real pipeline):
1. "Photo quality checked"
2. "Estimating face zones…"
3. "Preparing your comparison"

### 7.6 Rings, goals and day model
- A **day** runs from local midnight to midnight. Count only the **first** scan of the day toward De-Puff unless the user retakes. Retakes replace it.
- **De-Puff progress** = `(100 − score) / (100 − goal)`. For example, score 32 with goal 35 → 68/65 = 1.046, which counts as closed with a small overlap. Score 40 → 0.92. No scan today → 0.
- **Scan progress** = `scansToday / scanGoal`.
- **Habits progress** = `habitsLoggedToday / habitsGoal`. The habits are water, sleep, salt and alcohol, and logging any value counts.
- The legend shows "32 / ≤35", "1 / 1", "3 / 4". The caption under the rings is dynamic:
  - One ring left: "One more habit check-in to close all three rings." / "Scan to close your Scan ring." / "Your De-Puff ring closes at {goal} or lower."
  - All closed: "All three rings closed today."
  - None: "Start with today's scan."
- When all three close for the first time that day, present **All rings closed** full-screen (once per day).
- `Goals` are stored with an effective date. Changing a goal applies from today forward; past days keep the goals they had (the Fitness behavior).

### 7.7 Streaks, challenges, awards
- **Scan streak:** consecutive days with at least one scan, ending today or yesterday (it isn't broken until a full day has passed without a scan). The streak card shows the last 7 days as mini rings.
- **Challenges** (`ChallengeEngine`): monthly, defined in a bundled JSON (`challenges.json`) so new months can ship without code changes.
  - Example "Morning momentum" `{ id, month: "2026-10", kind: "scanDays", target: 20, autoJoined: true, rewardAwardID: "october-star" }`.
  - "Hydration check-in" `{ kind: "habitDays", habit: "water", target: 15, requiresJoin: true, rewardAwardID: "october-water" }`.
  - Pace text: "You're on pace" if `progress / target ≥ dayOfMonth / daysInMonth`; otherwise "{n} more days to stay on pace".
- **Awards** (`AwardEngine`): evaluated after every scan and habit log. The engine is idempotent and stores the earned date. The initial catalog:
  - First scan
  - Streaks: 3-day, 7-day, 30-day, 100-day, 365-day
  - Scan counts: 10, 30, 100
  - Perfect week (all rings closed on 7 consecutive days)
  - Habit starter (first habit logged)
  - Hydration hero (water logged 30 days)
  - Rested (sleep ≥ 7h logged on 14 days)
  - Personal best (lowest score so far, after 7+ scans)
  - Monthly challenge stars
- **New awards** present the unlock sheet after the result or Summary appears, queued one at a time. If several arrive at once, they show sequentially.

### 7.8 Insights and correlations (`InsightEngine`)
- Pair each day's score with that day's habit values. Sleep uses the previous night; salt uses "last evening".
- For each habit, compute the **mean score difference** between groups:
  - sleep ≥ 7h vs < 7h
  - water ≥ 2 L vs < 2 L (use the user's water goal)
  - salt high vs low
  - cycle phase (from HealthKit menstrual flow; compare menstrual or late-luteal days vs others)
- Show a habit only when each group has **at least 5 days and the total is at least 14 paired days**. Otherwise show "More data needed" (as the Cycle card does).
- Association labels by absolute effect and sample size: |Δ| < 2 → "No clear difference"; 2–4 → "Small association"; 4–8 with n ≥ 20 → "Moderate association"; larger → "Strong association". Always add the footnote "Personal association · Not proof of cause". Never claim causation.
- Color: a negative Δ (lower score, better) uses `habits` cyan. A positive Δ uses `accent` pink.
- **Daily insights on Summary:** choose up to 2. The most significant correlation goes first ("A well-rested pattern"), then a consistency insight ("Same light. Clearer comparisons." when all of the last 7 scans fall within ±15 min of the reminder time; otherwise "Try scanning at the same time each day for clearer comparisons.").
- Weekly comparison text: "↓ 6 from last week" compares this week's mean with last week's.

### 7.9 HealthKit
- Read only: `HKCategoryType(.sleepAnalysis)`, `HKQuantityType(.dietaryWater)`, `HKCategoryType(.menstrualFlow)`.
- Request authorization from Permissions or Profile. Respect a partial grant; HealthKit doesn't reveal read denials, so treat empty data as "no data".
- Sleep hours = the sum of asleep samples (core, deep, REM, unspecified) between 6 PM the previous day and 12 PM today. Water = today's sum.
- Health values pre-fill the quick log but never overwrite a value the user entered manually. Show a small `heart.fill` badge on chips sourced from Health.

### 7.10 Trends
- The **segmented control** controls the time range:
  - **D:** today's scan detail (photo, zones, habits, notes) plus each scan of the day if there were retakes.
  - **W:** 7 daily bars (the mockup).
  - **M:** about 30 daily bars, thin, with weekly gridlines.
  - **6M:** weekly average bars.
  - **Y:** monthly average bars.
- The header shows the range average ("40 weekly average", or "monthly average" and so on), the delta vs the previous range, and a "Lower is better · Goal ≤35" caption.
- Swiping horizontally on the chart pages to previous ranges (`chartScrollableAxes(.horizontal)` with `chartScrollPosition`).
- `chartXSelection` shows a popover annotation with the date, the score and the photo thumbnail. A haptic plays on each bar change.
- **Photo timeline:** a horizontal `ScrollView` of 3:4 thumbnails captioned "Oct 7 · 40". "See all" opens a grid of every scan (3 columns, newest first) leading to scan detail.
- **Time-lapse player:**
  - Frames are the scans in the selected range, aligned by the eye landmarks into the same framing ("Same framing · Original photos · No smoothing"). Apply no beautification; only crop and align.
  - Default 2 frames per second at 1×.
  - The scrubber can be dragged.
  - The date and time plus the score update per frame.
  - Export uses `AVAssetWriter`.

### 7.11 Profile and settings
Implement exactly the rows in section 4.2 (Profile), plus these behaviors:
- The reminder toggle schedules or cancels a `UNCalendarNotificationTrigger` (repeats daily). Changing the time reschedules it.
- The Apple Health toggle requests authorization when turned on. When turned off, the app stops reading but cannot revoke access, so explain: "To fully revoke access, open Settings › Health › Data Access."
- The Face ID lock toggle first authenticates (`.deviceOwnerAuthenticationWithBiometrics`) before turning on.
- Sign Out signs out of Google, clears tokens, keeps local data, and returns to the Sign in screen. The confirmation offers "Sign Out" and "Sign Out & Delete Local Data".

---

## 8. Data Model (SwiftData, in the App Group container)

```swift
@Model final class Scan {
  @Attribute(.unique) var id: UUID
  var capturedAt: Date
  var dayKey: String            // "2026-10-08" local
  var score: Int
  var underEyes: Int
  var cheeks: Int
  var jawline: Int
  var rawMetrics: Data          // encoded RawFaceMetrics
  var quality: Data             // encoded ScanQuality
  var lowConfidence: Bool
  var isBaseline: Bool
  var isManualCapture: Bool
  var localPhotoPath: String
  var thumbnailPath: String
  var faceTransform: Data?      // for ghost alignment / time-lapse
  var notes: String
  var tags: [String]
  var drivePhotoFileID: String?
  var driveJSONFileID: String?
  var syncState: SyncState      // enum: local, uploading, synced, failed, queued
}

@Model final class HabitLog { var dayKey: String; var waterLiters: Double?; var sleepHours: Double?; var salt: SaltLevel?; var alcohol: AlcoholLevel?; var sources: [String: String] /* "sleep": "health" */ }
@Model final class GoalSet { var effectiveFrom: Date; var dePuffMax: Int; var scansPerDay: Int; var habitsPerDay: Int; var waterGoalLiters: Double }
@Model final class EarnedAward { var awardID: String; var earnedAt: Date; var seen: Bool }
@Model final class ChallengeProgress { var challengeID: String; var joinedAt: Date?; var completedAt: Date? }
@Model final class UploadJob { var id: UUID; var scanID: UUID; var kind: UploadKind; var state: UploadState; var progress: Double; var retryCount: Int; var lastError: String?; var createdAt: Date }
```
- `UserSettings` is a `Codable` struct in App Group `UserDefaults`. It holds the reminder time, toggles, upload quality, the Drive folder ID, name and path, the Google email, and the onboarding step.
- The widget reads a lightweight `WidgetSnapshot` JSON written to the App Group after every change, not SwiftData directly. That snapshot holds the score, delta, ring progress, scans, habits and streak. Call `WidgetCenter.shared.reloadAllTimelines()` after writing it.

---

## 9. Widgets (WidgetKit)

- **Medium (Home Screen):** rings (compact, 88 pt) on the leading side. Trailing column: "PuffyMeter · Today" (footnote, secondary), the score (metricLarge, accent), the delta ("↓ 8 vs yesterday", green), and "1 scan · 3 / 4 habits" (footnote, secondary).
- **Small (Home Screen):** "Puffiness Score" (footnote), the score (metricHero scaled to fit), "↓ 8 points" (green), "7-day streak" (secondary).
- **Lock Screen `accessoryCircular`:** a mini triple ring (system tinted, with `widgetAccentable` on the progress arcs), or a gauge of the score.
- **Lock Screen `accessoryRectangular`:** the line "PuffyMeter", "Score 32 · ↓8", and a linear gauge for habits "3/4".
- **Lock Screen `accessoryInline`:** "PuffyMeter 32 · 7-day streak".
- **Never show a face photo** in any widget.
- Empty state: "Scan today" with a `faceid` symbol. Tapping deep-links to `puffymeter://scan`; other taps go to `puffymeter://summary`.
- Timeline: refresh at midnight (to reset the day) and on demand after app writes.
- Support dark, light and tinted / clear (iOS 26) appearances. Use `.containerBackground(for: .widget) { Color.card }`.

---

## 10. Navigation and Deep Links
- Root: the `TabView` with five tabs, each holding its own `NavigationStack` with a typed `navigationDestination` route enum.
- The Scan tab presents the camera as the tab's root content. After capture it pushes Analyzing and then Result. "Done" pops to the root and switches to Summary.
- URL scheme `puffymeter://` with the routes `summary`, `scan`, `trends`, `awards`, `award/<id>`, `profile`, `drive`.
- Handle notification actions via the `UNUserNotificationCenterDelegate` and the same router.

---

## 11. Copy Deck (use verbatim and put in `Localizable.xcstrings`)
Use the exact strings from the mockups listed in section 3 wherever they are complete. The corrected and completed strings are:
- Welcome 2 body: "Scan, check in with your habits, and work toward your personal De-Puff goal."
- Welcome 3 body: "Keep your daily photos in a Google Drive folder you choose. You stay in control."
- Sign in subtitle: "Sign in to save your progress and connect your private photo folder."
- Privacy card: "Photos stay in the Drive folder you choose. Your face is never used for advertising."
- Limited access body: "PuffyMeter can create and save photos only in the folder you select. It can't browse the rest of your Drive."
- Limited access footer: "You can disconnect or change folders anytime in Profile. Deleting the app won't delete your Drive photos."
- Permissions intro: "A few permissions make your morning routine effortless. You can change them anytime."
- Camera description: "Capture your face for a cosmetic puffiness estimate. Photos are analyzed on this iPhone."
- Health description: "Read sleep and water to show personal patterns. PuffyMeter doesn't write to Health."
- Insight 1 body: "Your scores tended to be lower after 7+ hours of sleep over the last 2 weeks."
- Insight 2 body: "You've scanned within 15 minutes of 8 AM all week. Keep your routine steady."
- Summary footer: "Cosmetic wellness only. Scores can vary with lighting, expression, and daily changes."
- Trends footer: "Compare trends, not single numbers. Facial appearance naturally varies day to day."
- Trends connected card: "Explore your calendar and the habits that show up alongside changes."
- Correlations intro: "Patterns in your last 30 days. Associations don't establish what caused a change."
- Correlations footer: "These insights are for cosmetic wellness, not health assessment or medical advice."
- Goals De-Puff description: "Close this ring when your score meets your goal. Lower is better."
- Morning momentum: "Scan on 20 different mornings this month. Consistency earns the October Star."
- Hydration check-in: "Log your water on 15 days. No perfect amount required, just a check-in."
- Just earned: "You showed up every morning. That's how routines are built."
- All rings body: "You reached your De-Puff goal, scanned, and checked in with all four habits."
- Profile footer: "PuffyMeter 1.0 · Cosmetic wellness, not diagnosis." on one line, then "Your photos are never used for advertising." on the next.
- Upload failed: "Upload failed" / "Your scan is safe on this iPhone." (+ reason) / "Retry"
- Offline: "Offline · Upload queued" / "Will sync when you're back online." / "Saved locally · {n} item(s) waiting to sync" (use plural rules)

**Tone:** warm, calm and non-judgmental ("a starting point, not a verdict"). Never shame a high score. Use sentence case for everything except the caps eyebrows.

---

## 12. Accessibility (required, not optional)
- Dynamic Type through AX5. Layouts reflow:
  - The rings card stacks the legend under the rings at accessibility sizes.
  - Zone tiles become a vertical list.
  - The score card stacks the photo below the text.
- VoiceOver:
  - Every ring, chart and badge has a meaningful label and value.
  - Charts provide an `AXChartDescriptor` (audio graph).
  - The comparison slider is an adjustable element (`accessibilityAdjustableAction`) that announces "Showing 50% today".
  - Checklist items announce changes (`AccessibilityNotification.Announcement`), for example "Good lighting, passed". The countdown announces each number.
- Don't rely on color alone: deltas always include an arrow and text, and the heatmap has a selected-day text line plus VoiceOver values.
- Minimum tap target 44 × 44 pt. Support Bold Text, Increase Contrast (stronger tracks and separators), Reduce Transparency (opaque tab bar fallback) and Reduce Motion.

---

## 13. Privacy, Security and Compliance
- No analytics SDKs, ad SDKs or third-party trackers. Optionally use Apple's on-device `MetricKit` for crash diagnostics only.
- Provide a privacy manifest (`PrivacyInfo.xcprivacy`) that declares no tracking and lists the required-reason APIs used (UserDefaults, file timestamps).
- App Store privacy label: Photos (face images) are **not collected** by the developer, since they go to the user's own Drive. Email comes from Google sign-in (account identifier, not linked to tracking). Health data is processed on-device only.
- Face images and geometry never leave the device except as the JPEG uploaded to the user's own Drive. Raw ARKit geometry is never uploaded; only derived zone metrics go into the JSON. State this in Profile › Privacy Policy, and comply with Apple's guidelines on face data (Guideline 5.1.2).
- Google API compliance: follow the Google API Services User Data Policy. Use the Limited Use disclosure in the privacy policy.
- The Keychain stores tokens with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- Scan files use `FileProtectionType.complete`. The App Lock covers the UI when the app enters the background.

---

## 14. Testing and Quality Bar
- **Unit tests (Swift Testing):**
  - `ScoringEngine`: fixture metrics → expected scores, including the 38/29/26 → 32 case, clamping and the low-confidence flag.
  - Ring progress math, including the overflow case 1.046.
  - Streak calculation across DST changes and time zones.
  - `ChallengeEngine` pace text.
  - `AwardEngine` idempotence.
  - `InsightEngine` thresholds and labels.
  - Drive file naming.
  - JSON schema encoding.
  - `UploadQueue` state transitions with a mocked `URLProtocol` (success, 401 → authExpired, 404 → folderMissing, offline → queued, retry backoff).
- **UI tests (XCUITest):**
  - Full onboarding with mocked services, behind a launch argument `-UITestMode` that injects fakes for Google, Drive, the camera (a fixture image) and Health.
  - Daily scan → result → Summary updates.
  - Quick log closes the Habits ring → All rings closed appears.
  - Award unlock sheet appears.
  - Offline upload → reconnect → saved.
- **Previews:** every view has a `#Preview` in dark, light and AX3 Dynamic Type, using sample data from a `PreviewData` factory. The sample data reproduces the mockups: Alex Morgan, alex.morgan@gmail.com, scores Oct 2–8 = 48, 44, 41, 39, 36, 40, 32, zones 38/29/26, water 1.5 L, sleep 8 h, salt low, alcohol none, 7-day streak, the awards and dates shown, and challenges at 8/20 and 6/15.
- **Visual verification:** after each milestone, run on the iPhone 16 Pro simulator and compare screenshots side by side with the mockup PNGs. Confirm every item in section 4 is fixed: no clipped text, no placeholders, aligned baselines, equal card heights.
- **Performance:**
  - The camera preview holds 60 fps while analysis runs off the main actor.
  - Analysis takes under 1.5 s on an A15 chip.
  - Cold launch to Summary takes under 1 s with 365 scans.
  - Thumbnails are generated at capture (300 px), so lists never decode full images.
- **No force unwraps** in production code. Every error is surfaced through typed errors and user-facing messages.

---

## 15. Milestones (do them in order and verify each before moving on)

1. **Project skeleton:** targets, `PuffyKit` package, App Group, `xcconfig` secrets, SwiftLint config, folder structure, the empty `TabView` with real tabs.
2. **Design system:** color assets, typography, every component in section 6.4 with previews, especially `ActivityRings` (check the overflow lap visually).
3. **Data layer:** SwiftData models, `PreviewData`, `WidgetSnapshot` writer, and unit tests for the ring, streak and goal math.
4. **Summary, Trends, Calendar, Goals, Challenges, Awards, Profile** UI built against `PreviewData` (no services yet). Screenshot each in dark and light against the mockups and the section 4 fixes.
5. **Onboarding UI:** Welcome, Sign in, the Drive screens, Permissions, with the router state machine and mocked services.
6. **Auth and Drive:** Google Sign-In, Sign in with Apple, `DriveService`, the folder create/list flow with the Google Picker fallback, `UploadQueue` with background sessions, and all four upload states. Write the ADR.
7. **Scan pipeline:** camera, live quality checks and coaching, countdown, capture, ghost overlay, `FaceAnalyzer` (ARKit and Vision), `ScoringEngine`, the Analyzing and Result screens, the baseline flow.
8. **Habits and HealthKit:** quick-log sheets, Health reads, Habits ring.
9. **Engines:** streaks, challenges, awards (with the unlock sheet and the All rings closed celebration), insights and correlations.
10. **Time-lapse and exports:** player, MP4 export, CSV export, share card.
11. **Widgets, notifications, deep links, App Lock.**
12. **Hardening:** the accessibility pass, error states, restore from Drive, performance checks, privacy manifest, App Store assets checklist, and a README with setup steps (creating the Google Cloud OAuth client for iOS, enabling the Drive API, the OAuth consent screen with the `drive.file` scope, filling `Secrets.xcconfig`).

At the end of each milestone, report:
- what was built
- screenshots taken
- the section 4 defects fixed
- anything deferred, and why

Ask me before:
- adding any third-party dependency other than GoogleSignIn
- changing the Drive scope
- making any decision that changes the privacy promise in section 1

---

## 16. Definition of Done
- Every screen in section 3 is implemented with the section 4 corrections, and every item in section 5 exists.
- No placeholder text ("Title", "Play", "Label", "Value", "\n") appears anywhere in the running app.
- Dark and light modes are complete. Dynamic Type works through AX5 without clipping. VoiceOver can complete onboarding, a scan and a habit log.
- A scan taken offline uploads automatically later. An expired Google session shows Reconnect and recovers. Deleting the Drive folder shows "Folder not found" and recovers.
- All unit and UI tests pass. The app builds without warnings under Swift 6 strict concurrency.
