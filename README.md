# Dissolve

A personal iPhone + Mac app for habits, a consistency grid, countdowns, life in weeks, a journal and stats.
Built for one person with a **free Apple account**: no CloudKit, no push notifications, no TestFlight.
`CLAUDE.md` is the full spec.

```
App/          app entry, root view, app-only services (sync folder, file IO)
Engine/       pure-Swift Swift package + Swift Testing tests (dates, streaks, sync merge)
Features/     one folder per screen
Models/       SwiftData @Model types (shared with widgets)
Shared/       code compiled into both the app and the widgets
Widgets/      the widget extension
Config/       entitlements, widget Info.plist, xcconfig
scripts/      setup-mac.sh, check.sh
project.yml   XcodeGen spec → Dissolve.xcodeproj (generated, not committed)
```

## First-time setup on the Mac

1. Install **Xcode 27** from the App Store, open it once and let it install its components.
2. Xcode → **Settings… → Accounts → +** → Apple ID → sign in.
3. In Terminal:
   ```sh
   git clone https://github.com/lohithmallikarjun/dissolve.git
   cd dissolve
   scripts/setup-mac.sh --open
   ```
   This installs XcodeGen (via Homebrew), generates `Dissolve.xcodeproj` and opens it.
4. Signing (only if the script said “No Apple Development certificate found”):
   1. In Xcode's left sidebar, click the blue **Dissolve** project.
   2. Under TARGETS, click **Dissolve** → **Signing & Capabilities** → **Team** → *Your Name (Personal Team)*.
   3. Click **DissolveWidgets** → same **Team**.
   4. Build once (⌘B), then run `scripts/setup-mac.sh` again so the team is remembered.

After every `git pull`, run `scripts/setup-mac.sh` again (it regenerates the project).
`scripts/check.sh` compile-checks everything without signing.

## Running on the iPhone

1. Plug the iPhone in with a cable (first time only; later it works over Wi-Fi).
2. iPhone: **Settings → Privacy & Security → Developer Mode → On**, restart, confirm.
3. Xcode toolbar: pick your iPhone as the run destination, press **▶︎ Run**.
4. First launch fails with “Untrusted Developer”. On the iPhone: **Settings → General → VPN & Device Management →
   Apple Development: <your email> → Trust**. Run again.

Free-account builds **expire after 7 days**. Reinstalling over the old app keeps all data
(a weekly auto-reinstall script arrives in Milestone 1).

## Running on the Mac

Xcode toolbar: pick **My Mac** → **▶︎ Run**.

## Milestone 0 checks (go / no-go)

On the **Milestone 0** screen:

| # | Do | Pass when |
|---|---|---|
| 1 | Look at section 1 | Both rows show a green ✓ |
| 2 | Tap **Write test value** a few times | The number rolls up |
| 3 | Add the **Dissolve Test** widget (iPhone: long-press Home Screen → Edit → Add Widget; Mac: right-click desktop → Edit Widgets) | It shows the same number, ✓ seal, “SwiftData: n” matching |
| 4 | Tap **Write test value** again | The widget updates within a few seconds |
| 5 | **Choose iCloud Drive folder…** → iCloud Drive → create/pick `Dissolve` → Open | Row shows ✓ and the folder name |
| 6 | Force-quit and reopen the app | Folder is still ✓ (bookmark survived) |
| 7 | **Write test file** on the iPhone | A row for the iPhone appears |
| 8 | On the Mac: pick the same folder, **Write test file**, then **Read test files** | Rows for both devices; message says “from another device ✓” |
| 9 | Back on the iPhone: **Read test files** | The Mac's row appears (may take a minute; tap Read again) |

## Milestone 1: try it

| # | Do | Expect |
|---|---|---|
| 1 | Today → **+** → name "Meditate", pick a symbol and colour, Save | A card appears |
| 2 | Tap the card | Checkmark, haptic, streak rolls to 1, ring at the top fills |
| 3 | Add "Water": type **Amount**, goal 8, unit glasses | Each tap adds 1; the ring fills |
| 4 | Long-press a card | Skip (rest day), Edit Day…, Clear, Details, Edit Habit |
| 5 | Tap **‹** next to the date | Yesterday; tap cards to fill in past days |
| 6 | Progress tab | Year grid (scroll left for older weeks); tap a day → popover; tap again → edit it |
| 7 | Tap a habit's mini grid | Detail: streak, best, strength %, year grid, notes |
| 8 | Edit a habit's schedule | "New schedule from" date; older days keep the old schedule |
| 9 | Home Screen → add **Habit**, **Today's Habits**, **Consistency**, **Year Grid** widgets | Tapping a widget's check updates it and the app |
| 10 | Lock Screen → add the circular and rectangular Dissolve widgets | % ring, next habit, last 7 days |
| 11 | Mac: sidebar, ⌘1–4, ⌘← / ⌘→, click a grid day → inspector | |
| 12 | Settings (gear) → Day ends at | Default 3 am |

## Milestone 2: try it (sync + journal)

| # | Do | Expect |
|---|---|---|
| 1 | First launch on each device: **Choose Folder…** → iCloud Drive → the same folder (e.g. `Dissolve`) | ✓ and the folder name. Later: Settings → Sync |
| 2 | iPhone: Journal tab → Face ID | Unlocks. Leave the app and come back: locked again; the app switcher shows it blurred |
| 3 | **New Entry** (✎) | Today's entry: prompt, text, photos, mood |
| 4 | Type a few lines, pick a mood, **Add Photos** (several) | Word count rolls; thumbnails appear |
| 5 | Mac: ⌘N, then drag a photo in from Finder, or copy one and press ⌘V | Photo added |
| 6 | Wait ~1 minute, open Dissolve on the other device (or Settings → **Sync Now**) | The entry, its photos and today's habit checks appear |
| 7 | Edit the same habit on both devices, then sync both | The later edit wins on both |
| 8 | Home Screen: add **Journal** and **On This Day** widgets; Lock Screen: journal streak | Tapping opens today's (or that day's) entry |
| 9 | Progress → **Count journaling** | Journaling counts as one more thing done each day |

How sync works: each device appends its own changes to `changes/<device>/<yyyy-MM>.jsonl` in the chosen
folder and reads the others' files; per record the newest edit wins and deletes are remembered.
Photos go to `photos/`. Nothing needs a paid account or CloudKit. iCloud itself can take a minute or two
to move files between devices.

## Milestone 3: try it (countdowns + life)

| # | Do | Expect |
|---|---|---|
| 1 | Life tab → **+** → **Birth Date & Eras** → set your birth date (lifespan 80) | Header rolls up to your "% remaining"; weeks grid fills |
| 2 | Add an era (e.g. University, purple, with dates) | That band of the grid turns purple |
| 3 | **+** → **New Countdown** → "Marathon", a date ~6 weeks away | A tile appears: days to go, progress ring |
| 4 | Tap the tile | It zooms to a full-screen clock: days · hours · minutes · seconds ticking |
| 5 | Make one for today with a time an hour away | On arrival: a celebration; it's archived the next day |
| 6 | A birthday with **Repeats every year**; a "days since" with **Up from a date** | Rolls over each year / counts up |
| 7 | Home Screen: **Countdown** (small; long-press → Edit to pick one), **Upcoming** (medium), **Life** (small, large) | In the last 24 h a timed countdown shows a live timer |
| 8 | Lock Screen: countdown inline + circular, life gauge | |
| 9 | Scroll the Life screen quickly | Stays smooth (the grid is one Canvas drawing) |

## Milestone 4: try it (reminders, Siri, Control Center)

| # | Do | Expect |
|---|---|---|
| 1 | Settings (gear) → **Allow Notifications** | "Notifications on" |
| 2 | Edit a habit → **Remind me** → a time 2 minutes from now → Save | A notification arrives; long-press it → **Done** checks the habit off |
| 3 | Check the habit off before its time on another day | No reminder that day |
| 4 | Settings → **Evening journal nudge** → a time 2 minutes away | "How was today?" → tap opens today's entry |
| 5 | iPhone: Control Center → edit (+) → **Add a Control** → search Dissolve → **Log Habit** → pick a habit | Tapping it logs the habit; the icon turns to ✓ |
| 6 | Also add **New Journal Entry** | Opens today's entry |
| 7 | Say "Hey Siri, log Meditate in Dissolve" | "Logged Meditate … N-day streak" |
| 8 | "Hey Siri, how am I doing in Dissolve?" | "3 of 5 habits done today. Next up: …" |
| 9 | Shortcuts app → Dissolve | Log Habit, Today's Habits, Habit Streak, Add to Journal, New Journal Entry, Days Until |
| 10 | Action button (iPhone 15 Pro and later): Settings → Action Button → Controls → Log Habit | One press logs it |

Notifications are local (scheduled on the device a week ahead), so they need no paid account and no server.
They're refreshed every time you open Dissolve.

## Milestone 5: try it (statistics)

| # | Do | Expect |
|---|---|---|
| 1 | Progress → **Stats** | Five cards, each starting with one sentence about your data |
| 2 | Strength: switch 30 days / 90 days / 1 year; drag across the chart | Insight updates; a readout follows your finger |
| 3 | Completion: Weeks / Months; tap a bar | That period's % and done/scheduled |
| 4 | Streaks, By weekday, Journal | Current vs best; strongest and weakest weekday; journaling streak, words, mood |
| 5 | Home Screen → **Stats** widget: small and medium | Strength with a 30-day sparkline; this week vs last week |

Insights need a few days of data; until then the cards say so.

## Weekly reinstall (free account: apps expire after 7 days)

`scripts/reinstall-iphone.sh` pulls, builds and reinstalls Dissolve on your iPhone over Wi-Fi.
Reinstalling keeps all data. One-time setup:

1. In Xcode: **Window → Devices and Simulators** → select your iPhone → tick **Connect via network**.
2. In Terminal, find the iPhone's identifier:
   ```sh
   xcrun devicectl list devices
   ```
3. Save it (replace the ID):
   ```sh
   cd ~/dissolve
   echo 'DEVICE_ID=00008110-001234567890801E' > scripts/device.local
   ```
4. Try it once (iPhone unlocked, same Wi-Fi as the Mac):
   ```sh
   scripts/reinstall-iphone.sh
   ```
5. Run it every Sunday at 10:00 automatically:
   ```sh
   cp scripts/com.lohith.dissolve.reinstall.plist ~/Library/LaunchAgents/
   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.lohith.dissolve.reinstall.plist
   ```
   The Mac must be awake and logged in at that time. Log: `/tmp/dissolve-reinstall.log`.
   To stop: `launchctl bootout gui/$(id -u)/com.lohith.dissolve.reinstall`.

The job assumes the repo is at `~/dissolve`; edit the plist if it lives elsewhere.

## Engine tests

```sh
swift test --package-path Engine
```

## CI screenshots

Every push to `main` runs `.github/workflows/build.yml` on a GitHub macOS runner: Engine tests, macOS + iOS builds,
then the app is launched in the iOS Simulator (light + dark) and screenshots are force-pushed to the
[`screenshots`](../../tree/screenshots) branch.
