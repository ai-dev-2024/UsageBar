# Changelog

## 0.1.2 — 2025-11-16
- Animated loading icon (dual bars sweep until usage arrives); always uses rendered template icon.
- Sparkle embedding/signing fixed with deep+timestamp; notarization pipeline solid.
- Icon conversion scripted via ictool with docs.
- Menu: settings submenu, no GitHub item; About link clickable.

## 0.1.1 — 2025-11-16
- Launch-at-login toggle (SMAppService) and saved preference applied at startup.
- Sparkle auto-update wiring (SUFeedURL to GitHub, SUPublicEDKey set); Settings submenu with auto-update toggle + Check for Updates.
- Menu cleanup: settings grouped, GitHub menu removed, About link clickable.
- Usage parser scans newest session logs until it finds `token_count` events.
- Icon pipeline fixed: regenerated `.icns` via ictool with proper transparency (docs in docs/icon.md).
- Added lint/format configs, Swift Testing, strict concurrency, and usage parser tests.
- Notarized release build "CodexBar-0.1.0.zip" remains current artifact; app version 0.1.1.

## 0.1.0 — 2025-11-16
- Initial CodexBar release: macOS 15+ menu bar app, no Dock icon.
- Reads latest Codex CLI `token_count` events from session logs (5h + weekly usage, reset times); no extra login or browser scraping.
- Shows account email/plan decoded locally from `auth.json`.
- Horizontal dual-bar icon (top = 5h, bottom = weekly); dims on errors.
- Configurable refresh cadence, manual refresh, and About links.
- Async off-main log parsing for responsiveness; strict-concurrency build flags enabled.
- Packaging + signing/notarization scripts (arm64); build scripts convert `.icon` bundle to `.icns`.
