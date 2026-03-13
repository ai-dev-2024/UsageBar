# Factory Provider

Factory (Droid) uses app credentials stored locally.

## Status: ❓ Untested

## Data Sources

1. **App credentials** (only method)
   - Reads credentials from Factory/Droid config folder
   - Uses WorkOS token for API authentication

## Credential Locations

| Platform | Paths |
|----------|-------|
| Windows | `%APPDATA%/Factory/credentials.json`, `%APPDATA%/Droid/credentials.json` |
| macOS | `~/Library/Application Support/Factory/credentials.json` |
| Linux | `~/.config/factory/credentials.json`, `~/.config/droid/credentials.json` |

## Credential Format

```json
{
  "accessToken": "...",
  "refreshToken": "...",
  "workosToken": "...",
  "email": "user@example.com"
}
```

## API Endpoint

| Endpoint | Purpose |
|----------|---------|
| `GET https://api.factory.dev/v1/usage` | Usage data |

## HTTP Headers

```
Authorization: Bearer <accessToken or workosToken>
Content-Type: application/json
```

## Snapshot Mapping

| Field | Source |
|-------|--------|
| Primary usage | `usage.current.percent` |
| Reset date | `usage.current.reset_at` |
| Plan | `usage.billing.plan` |
| Account | `user.email` |

## Key Files

- `src/main/providers/factory.ts` - Provider implementation
