# ios deploy

getting `ios/ClaudeUsage.xcodeproj` onto an iPhone. two routes — which one you can use is
decided entirely by whether your Apple ID is enrolled in the Apple Developer Program.

| | free Apple ID | paid program ($99/yr) |
|---|---|---|
| install from Xcode to your own phone | yes | yes |
| how long the app keeps working | **7 days**, then relaunch from Xcode | 1 year |
| TestFlight | **no** | yes |
| home-screen / lock-screen widget | no (needs app groups) | yes |
| devices | the ones plugged into your Mac | 100 per device type |

> TestFlight has no free tier and no workaround. it is gated on the paid program, full stop
> — anything claiming otherwise is describing sideloading, not TestFlight.

## free apple id — install to your phone today

1. open the project — the `.xcodeproj`, **not** the repo folder:
   ```bash
   open ios/ClaudeUsage.xcodeproj
   ```

   > opening the repo folder in Xcode opens the root `Package.swift` instead (through
   > `.swiftpm/xcode/package.xcworkspace`) — that's the *macOS* menu-bar app. build it with an
   > iPhone destination selected and you get `No such module 'AppKit'`, or
   > `'ClaudeUsageKit-product' requires minimum platform version 17.0 … but this target
   > supports 15.0` — the root package declares no iOS platform, so Xcode floors it at 15.
2. **Xcode → Settings → Accounts → +** → Apple ID → sign in. a "Personal Team" appears.
3. select the **ClaudeUsage** target → *Signing & Capabilities* → tick *Automatically manage
   signing* → pick your Personal Team. repeat for the **ClaudeUsageWidget** target.
4. bundle IDs must be globally unique, and `com.laszlo.ClaudeUsage` may already be taken.
   if Xcode says so, change both:
   - app: `com.<yourname>.ClaudeUsage`
   - widget: `com.<yourname>.ClaudeUsage.widget` — must stay a prefix-match of the app's
5. plug the iPhone in, unlock it, trust the Mac. pick it in the run-destination menu.
6. **⌘R**.
7. first run only: the phone refuses to launch an untrusted developer. on the phone go
   **Settings → General → VPN & Device Management →** your Apple ID **→ Trust**, then ⌘R again.

> the widget target will install but stay empty on a free account — it has no app group to
> read from. if Xcode refuses to sign it at all, select the target in the project navigator
> and delete it; the app builds fine alone.

### the 7-day thing

free provisioning profiles expire after 7 days. the app then refuses to launch until you
plug in and hit ⌘R again. also capped at 3 sideloaded apps per device and 10 new App IDs
per 7 days, so don't churn the bundle ID.

## paid program — testflight

### 1. enrol

[developer.apple.com/programs](https://developer.apple.com/programs/) → enrol as an
individual. $99/yr, approval usually lands within a day or two. do it from the Apple
Developer app on the iPhone if you want the fastest identity check.

### 2. create the app record

App Store Connect → **Apps → +** → New App:

| field | value |
|---|---|
| platform | iOS |
| name | `Claude Usage` (must be unique across the store) |
| bundle ID | the app's — register it under *Certificates, IDs & Profiles* first |
| SKU | anything, e.g. `claude-usage` |

### 3. turn the widget on

now that app groups are available, three edits:

- **build settings** on both targets (or project level — they inherit):
  ```
  APP_GROUP_ID          = group.com.<yourname>.ClaudeUsage
  KEYCHAIN_ACCESS_GROUP = $(AppIdentifierPrefix)com.<yourname>.ClaudeUsage
  ```
- **`ios/Config/App.entitlements` and `Widget.entitlements`** — uncomment the block in each
  and match the values above.
- *Signing & Capabilities* → **+ Capability** → *App Groups* and *Keychain Sharing* on both
  targets, same identifiers.

the app reads both out of `Info.plist` at launch (`AppConfig.bootstrap()`), so nothing in
the code changes. with the keychain group live, the widget fetches usage on its own timeline
instead of showing whatever the app last left behind.

> the two targets must agree on the app group *and* the keychain group, or the widget reads
> an empty keychain and silently falls back to the cached snapshot.

### 4. archive and upload

```bash
./ios/archive.sh                    # -> build/ClaudeUsage.xcarchive + .ipa
./ios/archive.sh --upload           # same, then ships it to app store connect
```

`--upload` needs an App Store Connect API key. *Users and Access → Integrations → App Store
Connect API → +*, download the `.p8` **once**, drop it in `~/.appstoreconnect/private_keys/`,
then:

```bash
export ASC_KEY_ID=XXXXXXXXXX          # the key's ID
export ASC_ISSUER_ID=aaaaaaaa-bbbb-…  # shown above the key list
```

or skip the key entirely and use Xcode: **Product → Archive → Distribute App → TestFlight
Internal Only**.

### 5. install via testflight

1. App Store Connect → your app → **TestFlight**. the build shows *Processing* for 5–15 min.
2. **Internal Testing** → add yourself (any of the up-to-100 users on your team).
   internal builds skip App Review — they're live as soon as processing ends.
3. install **TestFlight** from the App Store on the phone, sign in with the same Apple ID,
   the build is waiting.

> only *external* testing needs App Review. keep it to internal testers and a new build is
> on your phone minutes after upload — which for a personal tool is all you want.

builds expire after 90 days. bump `CURRENT_PROJECT_VERSION` (build number) for every upload;
App Store Connect rejects a duplicate.

## troubleshooting

| symptom | cause |
|---|---|
| `Failed to register bundle identifier` | someone else owns it — change it, both targets |
| `No profiles for '…' were found` | team not selected, or the phone isn't in the account |
| app dies on launch after ~a week | free profile expired — replug, ⌘R |
| `Untrusted Developer` | Settings → General → VPN & Device Management → Trust |
| widget stuck on "Needs an app group" | `APP_GROUP_ID` empty or entitlements still commented |
| widget shows stale numbers | keychain group mismatch — it fell back to the cached snapshot |
| usage rows all say "session expired" | claude.ai session died; re-add the account in the app |
