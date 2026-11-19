> **This repo has moved.** It now lives in [alisamadiii/agency-toolkit](https://github.com/alisamadiii/agency-toolkit/tree/main/apps/clients-browser). This repo is archived.

<p align="center">
  <img src="ClientsBrowser/Resources/Assets.xcassets/AppIcon.appiconset/icon_256.png" width="128" alt="Clients Browser icon">
</p>

<h1 align="center">Clients Browser</h1>

<p align="center">
  A native macOS browser with one isolated profile per client.<br>
  Every client keeps their own logins, cookies and tabs — and everything rolls into an encrypted backup you can restore anywhere.
</p>

<p align="center">
  <img alt="macOS 26+" src="https://img.shields.io/badge/macOS-26%2B-black?logo=apple">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white">
  <img alt="SwiftUI + WebKit" src="https://img.shields.io/badge/UI-SwiftUI%20%2B%20WebKit-2F6BFF">
  <img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-green">
</p>

---

## Why

If you run websites for clients, you end up signed into *their* Netlify, GoDaddy, Cloudflare, Search Console and Google Business accounts — with their email addresses. In a normal browser that means logging out and back in all day, or polluting your personal browser with a profile per client.

Clients Browser is a small, fast browser built for exactly that:

- **One profile per client.** Each client gets its own WebKit data store: cookies, `localStorage`, `sessionStorage`, IndexedDB, cache. Switching clients never logs anyone out.
- **Chrome-simple UI.** Tab strip, address bar, the shortcuts you already know. Nothing to configure.
- **Client workspace page.** The home chip / new tab shows a per-client card: website, contact, email, phone, address (→ Google Maps), notes, quick links, and one-click dashboards (Netlify, GoDaddy, Cloudflare, Search Console, Business Profile, Analytics, Gmail, GitHub) that open *inside that client's session*.
- **Encrypted backup string.** Every login, cookie, storage entry, tab and client note is rolled into one `CB1:…` string, encrypted with your passphrase and auto-saved to iCloud Drive. Delete the app, get a new Mac, paste the string — you're signed back in everywhere.

## How it works

```
┌──────────────────────────────────────────────────────────────────┐
│  Tab strip   [Client ▾] [⌂] [tab] [tab] [tab] [+]                │
│  Toolbar     ‹ › ↻  [ address / search ]                         │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│   WKWebView ── WKWebsiteDataStore(forIdentifier: client.id)      │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
          │ cookies change / storage change / tab change
          ▼
   Store (db.json) ──▶ BackupWriter ──▶ CB1:… ──▶ iCloud Drive
```

- **Isolation** — `WKWebsiteDataStore(forIdentifier:)` gives each client a persistent, separate on-disk jar. All tabs of one client share it; clients never see each other's. Popups (OAuth "Sign in with GitHub/Google") open as a tab in the same jar.
- **Persistence** — tabs save URL, title and WebKit `interactionState` (back/forward history). Relaunch restores everything.
- **Storage mirror** — a small user script mirrors each origin's `localStorage` / `sessionStorage` to the app so it can be included in the backup. Cookies are read straight from WebKit's cookie store.
- **Backup** — `CB1:` + base64( salt ‖ AES-GCM(zlib(JSON)) ), key = PBKDF2-HMAC-SHA256(passphrase, 210k rounds). Written ~5 s after any change and on quit to `iCloud Drive/Clients Browser/backup-latest.txt` (last 10 kept in `history/`). Settings → *Copy Backup String* / *Restore from Backup…*.
- **Not in the backup** — IndexedDB (WebKit can't export it). It still persists on disk; only a from-scratch restore of a site that keeps its session purely in IndexedDB needs a fresh sign-in.

## Shortcuts

| | |
|---|---|
| **Clients** | ⌘⇧P switch · ⌘⇧N new · ⌘⌥↑/↓ previous / next |
| **Tabs** | ⌘T new · ⌘W close · ⌘⇧T reopen · ⌘1–9 jump · ⌘⇧[ ] or Ctrl+Tab / Ctrl+⇧Tab prev/next · ⌘-click link → background tab |
| **Page** | ⌘L address bar · ⌘R reload · ⌘⇧R hard reload · ⌘. stop · ⌘[ ] or ⌘⌥← → back/forward · ⌘+ ⌘− ⌘0 zoom · ⌘F find · ⌘P print |

## Build

Requirements: macOS 26, Xcode 26+, [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
make run       # debug build + open
make install   # release build → /Applications
make icon      # re-render the app icon from tools/make-icon.swift
```

Update `CODE_SIGN_IDENTITY` in `project.yml` to your own Apple Development certificate. A stable identity matters: the backup passphrase lives in the login Keychain and is tied to the signing identity.

## Data locations

| What | Where |
|---|---|
| Profiles, tabs, client info, mirrored storage | `~/Library/Application Support/Clients Browser/db.json` |
| Cookies, IndexedDB, cache (per client) | `~/Library/WebKit/com.alisamadi.clientsbrowser/WebsiteData/<profile-uuid>/` |
| Encrypted backup | `~/Library/Mobile Documents/com~apple~CloudDocs/Clients Browser/` (falls back to `~/Documents`) |
| Backup passphrase | login Keychain, service `com.alisamadi.clientsbrowser` |
| Favicons | `~/Library/Caches/com.alisamadi.clientsbrowser/favicons/` |

## Project layout

```
ClientsBrowser/
  App/        ClientsBrowserApp (window, menus, quit hook), BrowserController (store + live session)
  Models/     Profile, TabState, ClientInfo, DbSchema, backup payload types
  Data/       Store (db.json, debounced atomic writes), Paths, Secrets (Keychain)
  Browser/    ProfileSession (data store per client, script bridge), Tab (WKWebView + delegates),
              Favicons, StorageCapture.js
  Backup/     Crypto, BackupBuilder, BackupWriter (iCloud, debounced), Restore
  Views/      BrowserView (tab strip, toolbar, find), NewTabPage (client workspace),
              ProfileMenu (switcher/editor), BackupView (Settings)
tools/        make-icon.swift
```

## Security notes

- The backup string is *full access to every client account*. Treat it like a password manager export. It is only ever written encrypted; the passphrase never leaves your Keychain.
- No credentials are stored in the client workspace — logins live in cookies, as in any browser.
- The app is not sandboxed (it writes straight to iCloud Drive) and runs with the hardened runtime.

## License

MIT
