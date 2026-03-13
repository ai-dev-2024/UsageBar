# z.ai Provider

z.ai uses an API token for authentication.

## Status: ❓ Untested

## Data Sources & Fallback Order

1. **Environment variable** (preferred)
   - `ZAI_API_TOKEN` environment variable

2. **Config file** (fallback)
   - Reads from z.ai config folder

## Config Locations

| Platform | Paths |
|----------|-------|
| Windows | `%APPDATA%/zai/config.json` |
| macOS | `~/Library/Application Support/zai/config.json` |
| Linux | `~/.config/zai/config.json`, `~/.zai/config.json` |

## Config Format

```json
{
  "api_token": "...",
  "apiToken": "...",
  "token": "..."
}
```

Any of these keys will work.

## API Endpoint

| Endpoint | Purpose |
|----------|---------|
| `GET https://api.z.ai/v1/usage` | Quota + MCP windows |

## HTTP Headers

```
Authorization: Bearer <token>
Content-Type: application/json
```

## Snapshot Mapping

| Field | Source |
|-------|--------|
| Primary usage | `quota.percent_used` |
| Secondary usage | First MCP window usage |
| Reset date | `quota.reset_at` |
| Plan | `user.plan` |
| Account | `user.email` |

## Key Files

- `src/main/providers/zai.ts` - Provider implementation
