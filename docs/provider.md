# Provider Authoring Guide

This guide covers how UsageBar providers are structured and how to add new ones.

## Terms

- **Provider**: A source of usage/quota data (Cursor, Copilot, Claude, etc.)
- **Descriptor**: Configuration for labels, URLs, defaults, and fetch strategies
- **Fetch strategy**: How to obtain usage data (browser cookies, OAuth, CLI, etc.)

## Architecture Overview

```
src/main/providers/
├── index.ts           # Provider interface + ProviderManager
├── cursor.ts          # Cursor provider
├── copilot.ts         # GitHub Copilot provider
├── claude.ts          # Claude provider
├── antigravity.ts     # Antigravity/Windsurf provider
├── codex.ts           # OpenAI Codex provider
├── factory.ts         # Factory/Droid provider
└── zai.ts             # z.ai provider
```

## Provider Interface

Each provider implements:

```typescript
interface Provider {
  id: string;           // Unique identifier
  displayName: string;  // UI display name
  fetch(): Promise<ProviderUsage>;
  isAvailable(): Promise<boolean>;
}
```

## Fetch Strategies

Providers use different strategies to obtain usage data:

| Strategy | Description | Used By |
|----------|-------------|---------|
| **Browser cookies** | Capture session from web login | Cursor, Claude |
| **OAuth device flow** | GitHub-style code entry | Copilot |
| **CLI detection** | Check for installed CLI tools | Claude, Codex |
| **Process detection** | Find running applications | Antigravity |
| **API token** | Environment variable or config | z.ai |
| **App credentials** | Read from app data folder | Factory |

## Adding a New Provider

1. Create `src/main/providers/<name>.ts`
2. Implement `Provider` interface
3. Register in `ProviderManager` constructor
4. Add to `src/main/index.ts` IPC handlers (if login needed)
5. Update `src/preload/index.ts` (if IPC needed)
6. Update `src/renderer/tray.html` login button handler
7. Create `docs/<name>.md` documentation

## Key Files

- [cursor.md](./cursor.md) - Cursor provider details
- [copilot.md](./copilot.md) - GitHub Copilot provider details
- [claude.md](./claude.md) - Claude provider details
- [antigravity.md](./antigravity.md) - Antigravity provider details
