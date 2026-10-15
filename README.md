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

## Engine tests

```sh
swift test --package-path Engine
```
