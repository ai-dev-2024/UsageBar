<p align="center">
  <img src="assets/banner.png" alt="UsageBar Banner" width="100%">
</p>

<p align="center">
  <strong>Windows system tray app for AI coding tool usage stats</strong>
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#screenshots">Screenshots</a> •
  <a href="#installation">Installation</a> •
  <a href="#supported-providers">Providers</a> •
  <a href="#acknowledgments">Acknowledgments</a>
</p>

---

## 🎯 What is UsageBar?

**UsageBar** is a lightweight Windows system tray application that displays your AI coding tool usage statistics at a glance. Stay on top of your usage limits across multiple AI coding assistants without switching between browser tabs or apps.



---

## ✨ Features

- 🖥️ **System Tray Integration** – Lives in your taskbar, always accessible
- 📊 **Real-time Usage Meters** – Session and weekly usage at a glance
- 🔄 **Auto-Refresh** – Configurable refresh intervals (1-30 minutes)
- 🎨 **Beautiful UI** – Modern, macOS-inspired glassmorphic design
- 🔌 **Multi-Provider Support** – Monitor usage across multiple AI tools
- ⚡ **Instant Toggle** – Enable/disable providers with one click
- 📈 **Dynamic Tray Icon** – Usage meter updates in real-time
- 🔗 **Quick Links** – Jump to dashboards and status pages
- 🪟 **Frameless & Resizable** – Drag to move, resize as needed

---

## 📸 Screenshots

<p align="center">
  <img src="screenshots/tray-popup.png" alt="Tray Popup" width="350">
  <br>
  <em>System tray popup showing Antigravity usage stats</em>
</p>

<p align="center">
  <img src="screenshots/settings.png" alt="Settings Window" width="500">
  <br>
  <em>Settings window with provider configuration</em>
</p>

---

## 📥 Installation

### Windows (Portable) - Recommended
1. Go to **[Releases](https://github.com/ai-dev-2024/UsageBar/releases)**.
2. Download `UsageBar-v1.0.1-Portable.zip`.
3. Extract the ZIP file to a folder of your choice (e.g., `Documents\UsageBar`).
4. Open the folder and double-click **`UsageBar.exe`** to run.
5. *(Optional)* Right-click `UsageBar.exe` → "Send to" → "Desktop (create shortcut)" for easy access.

### Build from Source
```bash
# Clone the repository
git clone https://github.com/ai-dev-2024/UsageBar.git
cd UsageBar

# Install dependencies
npm install

# Run in development
npm run dev

# Build installer
npm run package
```

---

## 🔌 Supported Providers

| Provider | Status | Detection Method |
|----------|--------|------------------|
| **Antigravity (Windsurf)** | ✅ Working | Auto-detect via process |
| **Cursor** | ✅ Working | Auto-detect via config |
| **Claude Code** | 🔧 CLI Required | `claude login` |
| **Codex (OpenAI)** | 🔧 CLI Required | `codex` CLI auth |
| **GitHub Copilot** | 🔧 CLI Required | `gh auth login` |
| **Gemini** | 🔑 API Key | Settings → API Key |
| **Factory** | 🔧 Configure | Settings |
| **z.ai** | 🔧 Configure | Settings |

---

## ⚙️ Configuration

### General Settings
- **Refresh Interval**: 1, 2, 5, 10, 15, or 30 minutes
- **Reset Session Daily**: Auto-reset session meter every 24 hours

### Provider Settings
Each provider can be individually enabled/disabled. Some require additional configuration:
- Providers with auto-detection work out-of-the-box
- CLI-based providers need you to run their login command
- API-based providers need an API key in Settings

---

## 🛠️ Development

```bash
# Install dependencies
npm install

# Run development mode
npm run dev

# Build for production
npm run package

# Clean build artifacts
npm run clean
```

### Tech Stack
- **Electron** – Cross-platform desktop framework
- **TypeScript** – Type-safe JavaScript
- **electron-builder** – Packaging and distribution
- **electron-store** – Persistent settings storage

---

## 🙏 Acknowledgments

- **[CodexBar](https://github.com/mzbac/CodexBar)** by [@mzbac](https://github.com/mzbac) – The original macOS inspiration for this project. UsageBar is the Windows counterpart, bringing the same great experience to Windows users.
- Thanks to all the AI coding tool providers for making development more productive!

---

## 💖 Support

If you find UsageBar helpful, consider supporting the development:

<a href="https://ko-fi.com/ai_dev_2024" target="_blank">
  <img src="https://ko-fi.com/img/githubbutton_sm.svg" alt="Support on Ko-fi">
</a>

---

## 📄 License

MIT License – feel free to use, modify, and distribute.

---

<p align="center">
  Made with ❤️ for the Windows developer community
</p>
