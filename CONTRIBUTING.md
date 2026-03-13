# Contributing to UsageBar

Thank you for your interest in contributing! This guide will help you get started.

## 🚀 Quick Start

```bash
# Clone the repo
git clone https://github.com/ai-dev-2024/UsageBar.git
cd UsageBar

# Install dependencies
npm install

# Run in development
npm run dev

# Build for production
npm run package
```

## 📁 Project Structure

```
UsageBar/
├── src/
│   ├── main/           # Electron main process
│   │   ├── providers/  # Provider implementations
│   │   └── index.ts    # Main entry point
│   ├── preload/        # Preload scripts
│   └── renderer/       # UI (HTML/CSS/JS)
├── docs/               # Provider documentation
└── .github/workflows/  # CI/CD automation
```

## 🔌 Adding a New Provider

1. Create `src/main/providers/<name>.ts`
2. Implement the `Provider` interface:
   ```typescript
   interface Provider {
     id: string;
     displayName: string;
     fetch(): Promise<ProviderUsage>;
     isAvailable(): Promise<boolean>;
   }
   ```
3. Register in `ProviderManager` constructor
4. Add documentation in `docs/<name>.md`
5. See [docs/provider.md](docs/provider.md) for detailed guide

## ✅ Before Submitting a PR

- [ ] Run `npm run build` - ensures TypeScript compiles
- [ ] Test your changes locally with `npm run dev`
- [ ] Update documentation if adding a provider
- [ ] Keep changes focused (one feature per PR)

## 🔄 CI/CD

Every push and PR triggers GitHub Actions to:
- Install dependencies
- Run TypeScript build
- Verify build output

This ensures contributions don't break the existing app.

## 📝 Code Style

- TypeScript for all source files
- Use async/await for asynchronous code
- Add console.log with `[ProviderName]` prefix for debugging
- Handle errors gracefully (return `needsLogin: true` instead of throwing)

## 🙏 Questions?

Open an issue on GitHub if you have questions or need help!
