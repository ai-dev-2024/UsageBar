# Codex Provider

Codex uses the OpenAI Codex CLI for authentication and usage data.

## Status: ❓ Untested

## Data Sources & Fallback Order

1. **CLI RPC** (preferred)
   - Runs `codex app-server` and sends JSON-RPC requests
   - Returns structured usage data

2. **CLI PTY** (fallback)
   - Runs `codex status` and parses text output
   - Less reliable, depends on output format

## Requirements

- Codex CLI must be installed
- Run `codex login` to authenticate

## API Method

### RPC Mode
```bash
codex -s read-only -a untrusted app-server
```

JSON-RPC request:
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "getUsage",
  "params": {}
}
```

### PTY Fallback
```bash
codex status
```

Parses output for:
- `session: XX%`
- `weekly: XX%`
- `email: user@example.com`

## Snapshot Mapping

| Field | Source |
|-------|--------|
| Primary usage | `primary.usedPercent` |
| Secondary usage | `secondary.usedPercent` |
| Account | `account.email` |
| Plan | `account.planType` |
| Credits | `credits.balance` |

## Key Files

- `src/main/providers/codex.ts` - Provider implementation
- Dashboard URL: `https://platform.openai.com/usage`
