# claude usage widget

A tiny native macOS menu-bar app that tracks Claude usage limits across **multiple
accounts** at once — plan, session (5-hour) and weekly (7-day) limits, with how much
is left and when each window resets.

- **menu bar only** — no dock icon (`LSUIElement`), one gauge glyph + optional "% left"
- **multi-account** — sign in to as many Claude accounts as you like; each gets a card
- **google sign-in** — the login window is Claude's real login page, so "continue with
  Google" works exactly as it does in a browser
- **low footprint** — plain SwiftUI + URLSession, polls on an interval you set, no webview
  kept alive after login
- **sessions in your keychain** — nothing is sent anywhere except claude.ai
<img width="345" height="445" alt="image" src="https://github.com/user-attachments/assets/420206e7-75cd-4a23-8b2f-4f3b93892a88" />

Keep in mind, this is 100% vibe-coded slop, but it works well for me.

## build

needs the Xcode toolchain (Xcode 15+ / macOS 14+). first time only, accept the license:

```bash
sudo xcodebuild -license accept
```

then:

```bash
./build.sh            # -> ClaudeUsage.app
open ClaudeUsage.app
```

or build + drop it into `/Applications` and launch in one shot:

```bash
./build.sh --install  # -> /Applications/ClaudeUsage.app, then opens it
```

> Gotcha: `--install` quits a running copy first (can't overwrite a live bundle), so a
> rebuild-and-reinstall is a single command. config still works alongside it —
> `./build.sh debug --install`.

> Gotcha: the Command Line Tools toolchain alone can't build this — SwiftUI's `@State` /
> `@Observable` macro plugins ship only with full Xcode. `build.sh` uses whatever
> `xcode-select -p` points at.

## use

1. click the menu-bar gauge → **Add account**
2. sign in (Google, email, whatever) in the window that opens
3. the window closes itself once the session is captured; the account appears as a card
4. repeat for more accounts

each card shows the plan badge, then a bar per limit window:

| window | meaning |
|---|---|
| **Session** | rolling 5-hour limit |
| **Weekly** | 7-day limit across all models |
| **Weekly Opus** | 7-day Opus-only limit (Max plans) |

gear icon → refresh interval + toggle the menu-bar percentage. right-click a card to
refresh, re-auth, or remove it.

## how it works

Claude's own apps read usage from claude.ai's web API:

```
GET https://claude.ai/api/organizations/{orgId}/usage
  -> { "five_hour": {utilization, resets_at},
       "seven_day": {…}, "seven_day_opus": {…}, … }
```

`utilization` is a 0–100 percent; the app shows `100 − utilization` as "left". auth is the
browser session cookie captured at login (`sessionKey` + Cloudflare's `cf_clearance`),
replayed with a matching user-agent. identity + plan come from `/api/bootstrap` and
`/api/organizations`.

> Gotcha: this is Claude's **internal** web API, not a published one — Anthropic can change
> the shape or the fields at any time. the decoders are written to tolerate missing/renamed
> windows, but a big change could still need a code bump. if a card shows "session expired",
> just re-add the account.

## layout

```
Sources/ClaudeUsage/
  App.swift            @main, MenuBarExtra, the menu-bar label
  Store.swift          @Observable state: accounts, polling, add/remove
  ClaudeAPI.swift      claude.ai web-api client (identity, orgs, usage)
  LoginController.swift  WKWebView login → captures the session cookies
  Keychain.swift       account list + sessions in the login keychain
  Models.swift         Account, UsageWindow, Plan, snapshots
  PanelView.swift      dropdown UI: cards + usage bars
  SettingsView.swift   inline settings tray
```
