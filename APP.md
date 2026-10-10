# Reading Log — iOS app

The website (`index.html` at the repo root) is still the real app and keeps working as before.
The iOS app is a Capacitor wrapper around that same file, so every change to the site ships
to the app with one command.

- Bundle ID: `com.matthewsb419.readinglog`
- Xcode project: `ios/App/App.xcodeproj` (Swift Package Manager, no CocoaPods)
- iPhone only, portrait, dark

## One-time setup

1. Install **Xcode** from the Mac App Store, open it once, then run:
   `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
2. Join the **Apple Developer Program** (developer.apple.com/programs, $99/year) with your Apple ID.
3. `npm install`
4. `npm run open` → in Xcode select the **App** target → **Signing & Capabilities** →
   tick *Automatically manage signing* and pick your team.

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

- Data lives in the app's own storage, separate from Safari's copy of the site. Paste your GitHub
  sync token in the app once (Sync panel) and it pulls everything down from `dailybiblereading-data`.
- iOS can clear web storage when the phone is very low on space; GitHub sync is the backup, so keep
  the token current (it expires on the date in `TOKEN_EXPIRES` in `index.html`).
