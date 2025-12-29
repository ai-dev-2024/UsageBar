# UsageBar Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.0] - 2024-12-29

### Added
- **Settings persistence**: Window size is saved and restored on launch
- **Dark/Light mode**: Automatic detection via system preference
- **Theme CSS variables**: Supports `data-theme="dark"` or `data-theme="light"`

### Changed
- Window bounds save on resize for better UX
- Improved theme handling with fallback to system preference

---

## [1.2.0] - 2024-12-29

### Added
- **Global hotkey** (`Ctrl+Shift+U`): Show/hide tray window from anywhere
- **Smooth animations**: FadeIn and slideUp transitions for window appearance
- **Glassmorphism effects**: Backdrop blur and refined layered shadows
- **Micro-animations**: Hover and press effects on buttons and actions

### Changed
- Enhanced visual polish matching CodexBar's premium feel
- Smooth cubic-bezier transitions on usage meters
- Updated action items with transform animations

---

## [1.1.0] - 2024-12-29

### Added
- **Mini progress bars**: Tiny color-coded usage meters under each provider icon
- **Two-bar tray icon**: System tray shows session (top) + weekly (bottom) like CodexBar

### Changed
- Provider tabs now show real-time usage at a glance
- Tooltip shows both session and weekly remaining percentages
- Color coding: green (>50%), yellow (20-50%), red (<20%)

---

## [1.0.3] - 2024-12-29

### Added
- **Reset countdown timers**: Shows "Resets in 2h 15m" instead of just date/time
- **Quota alert notifications**: Windows toast notification when usage exceeds 80%
- GitHub Actions CI for automated build verification

### Changed
- Improved reset time display with human-readable countdown format

---

## [1.0.2] - 2024-12-29

### Added
- Browser-based login for Cursor (auto-captures session cookies)
- GitHub OAuth device flow for Copilot
- Browser login for Claude (paid plans only)
- Provider documentation in `docs/` folder (inspired by CodexBar)
- Provider authoring guide

### Fixed
- Claude free tier now shows honest message (no usage API)
- Provider error messages clearly indicate login status
- Acknowledgement corrected to @steipete (CodexBar author)

### Security
- Session files stored in AppData (not project folder)
- Added session/token patterns to .gitignore

---

## [1.0.1] - 2024-12-28

### Added
- Settings window UI improvements
- Shadcn-inspired dark theme

---

## [1.0.0] - 2024-12-28

### Added
- Initial release for Windows (inspired by CodexBar for Mac)
- System tray integration with dynamic usage meter icon
- Antigravity provider support (Windows language server detection)
- Claude Code provider support
- Codex provider support
- Copilot provider support
- Settings window with provider toggles
- Configurable refresh intervals (1m, 2m, 5m, 15m)
- Auto-start on Windows boot option
- Windows installer (NSIS) and portable builds
