# UsageBar - Development Guide for Claude AI

This document provides guidelines for Claude AI agents when working on the UsageBar codebase.

## Project Overview

**UsageBar** is a Windows system tray application that monitors AI coding tool usage across multiple providers (Cursor, GitHub Copilot, Claude, Antigravity/Windsurf, etc.).

- **Tech Stack**: Electron 28, TypeScript 5, Electron-Builder
- **Platform**: Windows 10/11 only
- **Architecture**: Main process (Node.js) + Renderer (HTML/CSS/JS)

## Key Directories

```
src/
├── main/              # Electron main process
│   ├── index.ts       # App entry point
│   ├── providers/     # API providers for each AI tool
│   ├── settings.ts    # Settings storage (electron-store)
│   ├── tray.ts        # Tray icon rendering
│   ├── updater.ts     # Auto-updater
│   ├── history.ts     # Usage history tracking
│   └── utils/         # Utilities (logger, retry, circuit-breaker)
├── preload/           # IPC bridge to renderer
├── renderer/          # UI (tray.html, settings.html)
└── types.ts           # Shared TypeScript types
```

## Common Tasks

### Running the App

```bash
npm run dev      # Build and run in development
npm run build    # TypeScript build
npm run package # Build Windows installer
```

### Running Tests

```bash
npm run test        # Unit tests (Vitest)
npm run test:watch  # Watch mode
npm run test:coverage # With coverage report
npm run lint        # ESLint check
npm run format      # Prettier format
```

### Adding a New Provider

1. Create `src/main/providers/{provider-name}.ts`
2. Implement the `Provider` interface from `src/main/providers/index.ts`
3. Register in `src/main/providers/index.ts` constructor
4. Add to `settings.html` navigation and provider list

### Code Style

- Use TypeScript strict mode
- ESLint + Prettier for formatting
- 4-space indentation
- Async/await for all async operations
- Proper error handling with typed errors

### Provider Architecture

All providers implement:

```typescript
interface Provider {
    id: string;
    displayName: string;
    fetch(): Promise<ProviderUsage>;
    isAvailable(): Promise<boolean>;
}
```

### Testing Guidelines

- Write unit tests for provider parsing logic
- Mock external API calls with Vitest
- Test error handling paths
- Aim for 80%+ coverage on utilities

## Git Workflow

1. Create feature branch from `main`
2. Make changes with passing tests
3. Run lint + format before committing
4. Create PR for review
5. Squash merge to main

## Release Process

1. Update `package.json` version
2. Update `CHANGELOG.md`
3. Create git tag `v{version}`
4. Push tag to trigger release workflow
5. Release workflow builds and uploads to GitHub

## Troubleshooting

**App won't start**: Check `dist/` folder exists and has build output
**Provider not working**: Check `npm run dev` console for API errors
**TypeScript errors**: Run `npm run build` to see all errors

## Useful Resources

- [Electron Docs](https://www.electronjs.org/docs)
- [Electron-Builder](https://www.electron.build/)
- [Vitest](https://vitest.dev/)
- [ESLint](https://eslint.org/)
- [Prettier](https://prettier.io/)
