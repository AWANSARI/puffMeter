# PuffyMeter — Figma Design Prompt

> Copy everything below the line into Figma Make / Figma AI (or hand it to a designer). It works as one long prompt. If the tool gives better results with shorter prompts, paste one numbered section at a time.

---

## Prompt

Design a complete, high-fidelity **iOS app called "PuffyMeter"** for iPhone 16 Pro (393 × 852 pt frames). Use native iOS 18 patterns and make it look like a first-party Apple app. **Base the visual language on Apple Fitness (dark, rings, bold numbers) and Apple Health (grouped lists, category colors, clean charts).**

**What the app does:** Users take one face photo a day with a guided face scan. The photo is uploaded to a Google Drive folder they choose. The app gives each photo a **Puffiness Score (0–100, lower is better)** and tracks it over time with rings, charts, goals, streaks, and awards, much like Apple Fitness. It also logs lifestyle factors (sleep, water, salt, alcohol, cycle phase) and shows how each one relates to puffiness.

---

### 1. Design System (build this first as a separate page with components and variables)

**Typography (SF Pro):**
- Large Title: SF Pro Display Bold 34/41
- Title 1: SF Pro Display Bold 28/34
- Title 2: SF Pro Display Bold 22/28
- Headline: SF Pro Text Semibold 17/22
- Body: SF Pro Text Regular 17/22
- Subheadline: SF Pro Text Regular 15/20
- Footnote: SF Pro Text Regular 13/18
- Caption: SF Pro Text Regular 12/16
- **Metric numbers:** SF Pro Rounded Bold / Heavy (like the Fitness ring numbers), 48–64 pt for hero numbers, with small-caps unit labels such as "PTS", "DAYS", "%"
- Use SF Symbols for every icon

**Color: dark mode first (Fitness style), light mode second (Health style)**
- Background: `#000000`; Card / grouped cell: `#1C1C1E`; Elevated: `#2C2C2E`; Separator: `#38383A`
- Light mode: Background `#F2F2F7`, Card `#FFFFFF`
- Label primary `#FFFFFF` / secondary `#EBEBF5 @ 60%` / tertiary `@ 30%`
- **Ring and metric colors (Fitness palette):**
  - **De-Puff ring (score improvement):** Pink-red `#FA114F` → `#FF3A6E` gradient
  - **Scan ring (daily photo captured):** Neon green `#92E82A` → `#B6FF3B`
  - **Habits ring (water, sleep, low salt):** Cyan `#1EEAEF` → `#00C7FF`
- Category accents (Health style): Sleep `#5E5CE6` (indigo), Hydration `#0A84FF` (blue), Nutrition/Salt `#FF9F0A` (orange), Alcohol `#BF5AF2` (purple), Cycle `#FF375F` (pink), Mindfulness `#64D2FF` (teal)
- Status colors: Good `#30D158`, Neutral `#FFD60A`, High puffiness `#FF453A`
- Award medals: metallic gradients in gold, silver, and bronze, plus colored 3D badges

**Components (make these reusable, with variants):**
- Activity Rings: triple concentric rings, 3 sizes (hero 240pt, card 88pt, mini 32pt for calendar days), with states for 0%, partial, 100%, and over-100% (a second lap with a shadow at the ring's end cap)
- Metric card (Fitness "Summary" style): title in the accent color, big rounded number, sparkline
- Health-style list cell: icon chip, title, value, chevron
- Charts: bar chart (D/W/M/6M/Y segmented control), line chart with a goal line, range bands, heatmap calendar
- Buttons: Filled large (capsule, 50pt), Tinted, Plain, a "Continue with Google" button that follows Google's branding guidelines, destructive
- Segmented control, toggle, stepper, sheet grabber, tab bar, navigation bar (large title + inline), toast/banner, empty states
- Award badge (locked = grayscale silhouette, unlocked = full color + shine)

**Layout:** 16pt side margins, 12pt card corner radius (continuous/squircle), 8pt spacing grid, safe areas respected, Dynamic Island shown on frames.

---

### 2. Onboarding and Authentication

**2.1 Splash:** black screen with the PuffyMeter app icon in the center. Icon idea: a soft rounded face outline drawn inside a triple ring in pink, green, and cyan.

**2.2 Welcome carousel (3 pages, page dots):**
1. "Track your puffiness, daily." Shows an animated face mesh illustration.
2. "Close your rings." Shows the three rings, each with a label.
3. "Your photos stay yours." Shows a Google Drive + lock illustration, with the line "Photos live in your own Google Drive folder."

**2.3 Sign In:**
- App icon, "Welcome to PuffyMeter" (Large Title), short subtitle
- Primary: **"Continue with Google"** (white button, Google "G" logo)
- Secondary: "Sign in with Apple" (black, Apple-style), shown for App Store compliance
- Footnote with links to Terms and Privacy Policy
- Also design the Google account picker sheet state and a loading state

**2.4 Connect Google Drive:**
- Large Drive illustration. Title: "Connect Google Drive"
- Explainer list with SF Symbol bullets:
  - "PuffyMeter only accesses the one folder you choose"
  - "Photos are saved as `PuffyMeter_YYYY-MM-DD.jpg`"
  - "You can disconnect anytime"
- Button: "Choose Folder"
- **Folder picker screen:** Drive-style folder browser (breadcrumbs, folder list, search). Include a "+ New Folder" option that suggests the name "PuffyMeter Daily". The selected folder shows a checkmark. Sticky bottom button: "Use This Folder"
- Success state: green checkmark animation, the folder path, and "Connected as name@gmail.com"

**2.5 Permissions:** Camera, Notifications (daily reminder), and optional Apple Health (sleep, water, cycle). Each one gets an Apple-style pre-permission card that explains why it's needed.

**2.6 Personalize and Baseline:**
- Name, age range, and reasons for tracking (multi-select chips: Morning puffiness, Allergies, Diet/Salt, Sleep, Skincare, Menstrual cycle, Post-procedure recovery)
- Preferred scan time (time wheel, default 7:30 AM). Tip: "Scan right after waking for best consistency"
- **Baseline scan:** "Let's take your first scan to set your baseline." This leads into the Scan flow.

---

### 3. Main App: Tab Bar (5 tabs)
`Summary` (circle.circle) · `Trends` (chart.xyaxis.line) · **`Scan`** (center, prominent face.viewfinder) · `Awards` (rosette) · `Profile` (person.crop.circle)

---

### 4. Summary Tab (Apple Fitness "Summary" clone)

- Large title "Summary", today's date above it in secondary text, and the user's avatar at top right
- **Hero card: Activity Rings** (240pt) with three rows of stats beside or below them:
  - **De-Puff** (pink): "Score 32 / Goal ≤ 35 PTS"
  - **Scan** (green): "1 / 1 TODAY"
  - **Habits** (cyan): "3 / 4 HABITS"
- **Today's Scan card:** thumbnail of today's photo (rounded), Puffiness Score as a big rounded number with a colored status pill ("Low puffiness"), a delta vs yesterday ("▼ 6 from yesterday"), and a Drive sync badge ("Saved to Drive ✓")
- **Face Zone breakdown card:** a small face diagram with heat-colored zones (Under-eyes, Cheeks, Jawline, Forehead) and a score for each zone
- **Trend card:** 7-day bar chart in pink, with a dashed line for the weekly average
- **Streak card:** flame icon, "12-day scan streak", and a row of mini rings, one per weekday (like Fitness's weekly rings)
- **Insights card** (Health "Highlights" style): "You're 18% less puffy on days you sleep 7+ hours." Show 2–3 stacked highlight cards, each with a tiny chart
- **Habits quick-log row:** tappable chips for 💧 Water (+1 glass), 🧂 Salty meal, 🍷 Alcohol, 😴 Sleep (auto from Health), 🧊 Ice roller / Gua sha
- Empty state for a day without a scan: dim ring and the CTA "Take today's scan"

---

### 5. Scan Flow (core feature)

**5.1 Scan Camera (full screen, front camera, black UI):**
- Live camera view with an **oval face guide** overlay. The guide turns green when the face is aligned
- **Face mesh dots/wireframe** overlay (TrueDepth-style), animated as it scans
- Live checklist chips at the top that tick off one by one: ✓ Face centered · ✓ Good lighting · ✓ Neutral expression · ✓ Hair off face · ✓ Same distance as baseline
- A **ghost overlay of yesterday's photo** at 20% opacity (toggleable) for consistent framing
- Tilt/level indicator, lighting meter
- Large white shutter button, an auto-capture countdown "3…2…1", flash/front-light toggle (screen flash), and a close button
- Variants: misaligned (orange guidance "Move closer"), too dark (warning), aligned/capturing

**5.2 Optional profile angles:** quick prompts to "Turn left" and "Turn right" for side-cheek captures, shown as a small 3-step progress indicator.

**5.3 Analyzing:** the photo with a scanning light sweep and mesh animation. Text: "Analyzing puffiness…", with these sub-steps listed: Detecting landmarks → Measuring under-eye volume → Comparing to baseline.

**5.4 Result:**
- Large Puffiness Score number (SF Rounded Heavy 72pt) with a colored status label
- A ring that animates as it closes for De-Puff
- Comparison slider: **Before (baseline) ↔ Today**, with a draggable divider
- Zone breakdown with bars for each zone
- "How do you feel?" emoji mood row, plus a notes field
- Context tags: Woke up time, Slept on side/back, Allergies, Period, Workout
- Upload status: progress bar "Uploading to Google Drive / PuffyMeter Daily…" → "Saved ✓". Design these states: uploading, success, failed with Retry, offline/queued
- Buttons: "Done" (primary) and "Retake" (plain)
- **Ring-closed celebration:** confetti and ring spark animation, with the line "Scan ring closed! 🎉"

---

### 6. Trends Tab (Apple Health charts style)

- Segmented control at the top: **D · W · M · 6M · Y**
- **Puffiness Score chart:** interactive line or bar chart with a goal line and a shaded "healthy range" band. Scrubbing shows a tooltip with the date, score, and photo thumbnail
- Stat summary row: Average, Lowest, Highest, Change %
- **Photo Timeline / Time-lapse:** horizontal filmstrip of daily photos, plus a "Play time-lapse" button that opens a full-screen player with a scrubber and an export/share action
- **Calendar heatmap:** month grid where each day shows a mini ring or a color-coded dot
- **Correlations (Health "Trends" style):** cards titled "Sleep vs Puffiness", "Water vs Puffiness", "Salt vs Puffiness", and "Cycle phase vs Puffiness", each with a scatter or dual-axis chart and a one-line takeaway
- **Time-of-day insight:** "Your puffiness drops ~22% by noon" (requires an optional second scan)
- Detail page for each metric with "About Puffiness Score" explainer text, "Show All Data", and "Add Data"

---

### 7. Goals

- **Change Goals sheet** (like Fitness "Change Move Goal"): a big number in the middle with − / + circular buttons, e.g. "Puffiness target: ≤ 35", "Habits per day: 4"
- **Goal types:** Daily target score, Weekly average, Scan streak, Hydration (glasses), Sleep hours, Low-sodium days
- **Goal progress cards** with ring and bar progress
- **Challenges** (like Fitness monthly challenges): "October De-Puff Challenge: average below 30 for 20 days". Show the challenge card, its progress, and the badge preview

---

### 8. Awards Tab (Apple Fitness Awards clone)

- Grid of 3D badges on black, grouped into sections:
  - **Streaks:** 7-Day, 30-Day, 100-Day, 365-Day Scanner
  - **Milestones:** First Scan, 50 Scans, Personal Best Score, Perfect Week (all rings closed 7 days)
  - **Habits:** Hydration Hero, Sleep Champion, Salt Slayer
  - **Monthly Challenges:** one unique badge per month
  - **Limited Edition:** New Year Reset, Summer Glow
- Locked badges appear as dim silhouettes with progress text ("4 of 7 days")
- **Award detail:** a large badge that rotates in 3D (show a tilted state), the date earned, its description, and a Share button
- **Unlock moment:** full-screen modal with the badge flipping in, shine, and confetti

---

### 9. Profile and Settings (iOS grouped list)

- Header: avatar, name, Google email, and member-since date
- **Google Drive section:** connected folder (path and file count), "Change Folder", "Sync now", last synced time, storage used, Upload quality (Original / High / Compressed), "Disconnect Drive" (destructive)
- **Reminders:** daily scan time, smart reminders ("Remind me if I haven't scanned by 9 AM"), streak-saver notification
- **Apple Health:** read/write toggles for Sleep, Water, Cycle Tracking, Mindful Minutes
- **Goals:** link to the Change Goals sheet
- **Privacy:** Face ID app lock, blur thumbnails in app switcher, "Analysis runs on-device", Delete all data
- **Share and Export:** export a CSV of scores, export the time-lapse video, share a progress card
- **Appearance:** Dark / Light / System
- Units, Help, About, Sign Out

---

### 10. Extra Surfaces

- **Lock Screen and Home Screen widgets:** small widget (rings and today's score), medium widget (rings, a 7-day sparkline, and the streak), Lock Screen circular widget (mini ring)
- **Live Activity / Dynamic Island:** "Scan reminder: tap to scan" plus an upload progress state
- **Push notifications:** "Good morning! Time for your PuffyMeter scan ☀️", "🔥 Don't break your 12-day streak", "🏅 You earned Hydration Hero"
- **Apple Watch** (optional): ring-glance face and a habit quick-log
- **Shareable progress card:** a square image with the rings, score delta, and a before/after split, styled like the Fitness share card

---

### 11. States to Include on Every Main Screen
Loading skeletons, empty states (first day, no data), error (Drive auth expired → "Reconnect Google Drive" banner), offline queued uploads, and both dark and light mode versions of Summary, Scan Result, and Trends.

---

### 12. Deliverables / Figma Organization
- Page 1 **Cover**
- Page 2 **Design System** (color and text variables, components with variants, SF Symbols used)
- Page 3 **Onboarding and Auth**
- Page 4 **Main Tabs** (Summary, Trends, Awards, Profile)
- Page 5 **Scan Flow**
- Page 6 **Goals and Challenges**
- Page 7 **Widgets, Notifications, Watch**
- Page 8 **Prototype**: wire the main flow Welcome → Google Sign-In → Connect Drive → Pick Folder → Baseline Scan → Result → Summary, with Smart Animate on ring closing and sheet transitions

Use auto layout everywhere and name layers semantically. Keep the overall feel premium, motivating, and calm: big rounded numbers, glowing rings on pure black, and generous spacing, just like Apple Fitness.
