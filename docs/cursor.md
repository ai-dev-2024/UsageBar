# Cursor Provider

Cursor is web-only. Usage is fetched via browser cookies captured during login.

## Status: ✅ Tested & Working

## Data Sources & Fallback Order

1. **Stored session cookies** (preferred)
   - Captured by "Sign in to Cursor" browser login flow
   - Stored at: `%APPDATA%/UsageBar/cursor-session.json`

2. **No fallback** - login required if no stored session

## API Endpoints

| Endpoint | Purpose |
|----------|---------|
| `GET https://cursor.com/api/usage-summary` | Plan usage, on-demand, billing cycle |
| `GET https://cursor.com/api/auth/me` | User email + name |

## Required Cookies

Domain: `cursor.com`

| Cookie Name | Required |
|------------|----------|
| `WorkosCursorSessionToken` | Yes (primary) |

## HTTP Headers

```
Accept: application/json
Cookie: <session cookies>
User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36
```

## Snapshot Mapping

| Field | Source |
|-------|--------|
| Primary usage | `individualUsage.plan.totalPercentUsed` |
| Reset date | `billingCycleEnd` |
| Plan | `membershipType` (free/pro/business) |

## Key Files

- `src/main/providers/cursor.ts` - Provider implementation
- Login flow uses Electron `BrowserWindow` with `persist:cursor-login` session
