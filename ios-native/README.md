# Reading Log — native Swift app

A SwiftUI rewrite of the website (`../index.html`), built so a home-screen widget can be added
later. The Capacitor wrapper in `../ios` is untouched; both apps can be installed side by side.

## Layout

| Folder | What it is |
| --- | --- |
| `ReadingLogCore/` | Swift package with **all** the logic and no UI: plan, scoring and grades, trackers, calendar backfill, steps, the pelvic floor program, habit score, extra credit, daily goal and quote picks, sync merging, backup import, Markdown export, and what the Today card shows. A widget target just adds this package. |
| `ReadingLog/` | The SwiftUI app: screens, iCloud/GitHub sync, Face ID, Apple Health, themes. |
| `ReadingLogUITests/` | Drives the app in the simulator: writes on the Today card, quits, reopens, checks it stuck. |
| `tools/` | Node scripts that run the website's own code (see below). |

## Same answers as the website

`ReadingLogCore` is a line-by-line port, and the parity tests hold it to identical results:
`tools/make-fixtures.mjs` runs `index.html`'s real functions on a made-up log for five dates
(plan, monthly and weekly scores, every tracker, steps stats and charts, the pelvic floor
program, habit score, quote and goal of the day, extra credit, Markdown, edits, sync merges and
saving the Today card) and the Swift tests must match every value.

```
node tools/make-fixtures.mjs          # after changing scoring in index.html
node tools/export-content.mjs         # after changing quotes, questions, themes or the Next list
cd ReadingLogCore && swift test       # logic, on the Mac, in under a second
```

To check against your real log without committing it:
`node tools/make-fixtures.mjs ~/code/dailybiblereading-data/data.json --out /tmp/real.json`,
copy it over `Tests/ReadingLogCoreTests/Fixtures/fixtures.json`, run `swift test`, then put the
made-up file back with `git checkout`.

## Private profiles

Same scheme as the wrapper app, and the **same iCloud record**, so the two apps share one log:

- Face ID (or the passcode) on launch and after a minute in the background; the app switcher
  shows a blank screen. Skipped in the simulator.
- Each person's log is one encrypted record in their own iCloud private database
  (`iCloud.com.matthewsb419.readinglog`), readable only by their Apple ID. The copy on the phone
  is a file per iCloud account in the App Group container (`group.com.matthewsb419.readinglog`),
  which is where a widget will read it.
- GitHub sync with the website is optional; the token is kept in the Keychain.
- Steps can be filled from Apple Health (read-only).

## Setup in Xcode

1. Open `ReadingLog.xcodeproj`. Pick an iPhone simulator and press ▶ — no account needed.
2. To run on a phone: **ReadingLog** target → Signing & Capabilities → pick your team. Xcode
   registers the bundle ID `com.matthewsb419.readinglog.swift`, the iCloud container, HealthKit and
   the App Group (all listed in `ReadingLog.entitlements`). If the container shows red, press
   the refresh button under it.
3. CloudKit schema: if you already deployed it for the wrapper app, nothing to do (same container
   and record type). Otherwise run once from Xcode, make an entry, then deploy schema changes to
   Production at icloud.developer.apple.com.

To make this app *replace* the wrapper on the App Store later, change the bundle ID to
`com.matthewsb419.readinglog` before the first upload.
