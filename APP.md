# Reading Log — iOS app

The website (`index.html` at the repo root) is still the real app and keeps working as before.
The iOS app is a Capacitor wrapper around that same file, so every change to the site ships
to the app with one command.

- Bundle ID: `com.matthewsb419.readinglog`
- Xcode project: `ios/App/App.xcodeproj` (Swift Package Manager, no CocoaPods)
- iPhone only, portrait, dark

## Private profiles (app only)

The website keeps its password and GitHub sync exactly as before. Inside the app:

- **Face ID / passcode** opens the app (instead of the website password), and it locks again after a
  minute in the background. The app-switcher preview is blanked.
- **Each person's log lives in their own iCloud account**: one encrypted record in the app's CloudKit
  *private* database (`iCloud.com.matthewsb419.readinglog`). Only that Apple ID can read it — not
  you, not other users, not the developer. On the phone, storage is also namespaced by iCloud account.
- No iCloud signed in → the log stays on that phone only (the Sync panel says so).
- **GitHub sync is optional in the app**: paste your token in Sync settings only if you want the website
  to stay in step with the app. Other people leave it blank. Your first GitHub sync also pulls your
  existing history into the app (and from there into your iCloud).
- Native code: `ios/App/App/ProfilePlugin.swift` (Face ID, iCloud, share sheet for backups).

## One-time setup

1. Install **Xcode** from the Mac App Store, open it once, then run:
   `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
2. Join the **Apple Developer Program** (developer.apple.com/programs, $99/year) with your Apple ID.
3. `npm install`
4. `npm run open` → in Xcode select the **App** target → **Signing & Capabilities** →
   tick *Automatically manage signing* and pick your team. The **iCloud** capability (CloudKit, container
   `iCloud.com.matthewsb419.readinglog`) is already in `App.entitlements`; if Xcode shows the container
   in red, press the refresh button under it so it gets registered to your team.
5. Run it once on your iPhone from Xcode (▶) and make one entry, so CloudKit creates the `Log` record
   type in the *Development* environment. Then open
   [icloud.developer.apple.com](https://icloud.developer.apple.com) → CloudKit Database → your
   container → **Deploy Schema Changes** to Production. TestFlight and App Store builds use Production;
   skip this and sync fails there.

## After changing the website

```
npm run sync     # copies index.html + icons into the iOS project
```

Then in Xcode, bump **Build** (General tab), and choose **Product → Archive → Distribute App**.

## Getting it on your phone

- **TestFlight (recommended for a personal app):** distribute the archive to App Store Connect,
  add yourself as an internal tester, install via the TestFlight app. No App Review needed.
- **Public App Store:** needs screenshots, a privacy policy URL, and App Review.

## Notes

- Data lives in the app's own storage, separate from Safari's copy of the site, and is backed up to
  the person's iCloud. To bring your existing history over, paste your GitHub sync token in the app once.
- iOS can clear web storage when the phone is very low on space; iCloud is the backup.
- **Inviting people:** TestFlight → External Testing → add their email (needs a quick Beta App Review,
  usually a day). Up to 10,000 testers; builds expire after 90 days, so upload a fresh one now and then.
  Everyone sees the same trackers you do, but each person's answers stay in their own iCloud.
