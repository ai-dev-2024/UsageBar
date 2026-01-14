# Changelog

All notable changes to UsageBar will be documented in this file.

## [1.5.0] - 2026-01-15

### ✨ New Features
- **Unit Testing** – Added Vitest with 12 tests for utilities
- **Code Quality** – Prettier code formatting with consistent style
- **TypeScript Types** – Shared interfaces in `src/types.ts`

### 🔧 Infrastructure
- **CI/CD Pipeline** – Enhanced GitHub Actions (lint, build, test, coverage)
- **Auto-Release** – Windows installer builds automatically on version tags
- **Dependabot** – Weekly dependency vulnerability scanning
- **Circuit Breaker** – Resilience pattern for API failures
- **Retry Utility** – Exponential backoff for API retries
- **Structured Logger** – JSON-formatted logging with levels

### 📦 Developer Experience
- **AGENTS.md** – Claude AI development guide
- **VS Code Config** – Recommended extensions and settings
- **Test Coverage** – v8 coverage reporting with 80%+ target

### 🐛 Bug Fixes
- Fixed TypeScript strict mode compliance
- Excluded test files from main build

---

## [1.4.0] - 2025-12-29

### ✨ New Features
- **Gradient Glassmorphism Theme** – Beautiful purple/blue gradient background for Settings window
- **Transparency Slider** – User-controlled popup opacity (10-80%) in tray menu
- **Hotkey Customization** – Configure global hotkey (default: Ctrl+Shift+U) in Settings
- **Click-to-Update** – Version badge changes to "Update Available" and allows one-click download/install
- **Rounded Sidebar** – Settings sidebar now has matching rounded corners

### 🎨 UI Improvements
- Frosted glass effect on system tray popup
- Consistent dark theme across all windows
- Removed theme toggle (single unified theme)
- Settings window with floating card design

### 🔧 Technical
- Auto-update system checks for updates on launch
- Update progress displayed in version badge
- Settings persisted for popup opacity
- Improved window transparency handling

---

## [1.3.0] - 2025-12-28

### ✨ New Features
- **Glassmorphism UI** – Modern frosted glass design
- **Dynamic Tray Icon** – Real-time usage meter in system tray
- **Quota Alerts** – Windows notifications when usage exceeds 80%
- **Provider Tabs** – Quick switching between enabled providers

### 🔧 Improvements
- Faster refresh with configurable intervals
- Better error handling for API failures
- Improved session detection for Antigravity

---

## [1.2.0] - 2025-12-27

### ✨ New Features
- **Multi-Provider Support** – Monitor Cursor, Claude, Copilot, and more
- **Settings Window** – Configure providers and preferences
- **Auto-Refresh** – Configurable refresh intervals

### 🔧 Improvements
- Persistent window bounds
- Better provider authentication flows

---

## [1.1.0] - 2025-12-26

### ✨ New Features
- **Resizable Window** – Drag to resize the popup
- **Session Tracking** – Daily session reset option
- **Quick Links** – Jump to dashboards and status pages

---

## [1.0.0] - 2025-12-25

### 🎉 Initial Release
- System tray integration for Windows
- Antigravity (Windsurf) usage monitoring
- Global hotkey (Ctrl+Shift+U)
- Real-time usage meters
- Reset countdown timers
