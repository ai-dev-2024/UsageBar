# Claude Provider

Claude supports browser login and CLI detection, but usage API is only available for paid plans.

## Status: ⚠️ Limited (Free tier has no usage API)

## Data Sources & Fallback Order

1. **Stored session cookies** (preferred for paid users)
   - Captured by "Sign in to Claude" browser login flow
   - Stored at: `%APPDATA%/UsageBar/claude-session.json`

2. **CLI detection** (fallback)
   - Checks if `claude` CLI is installed
   - CLI requires paid plan (Claude Max/Pro)

## API Endpoints

| Endpoint | Purpose | Access |
|----------|---------|--------|
| `GET https://claude.ai/api/usage` | Usage data | Paid plans only |
| `GET https://console.anthropic.com/api/usage` | API usage | API users |

## Required Cookies

Domain: `claude.ai`

| Cookie Name | Required |
|------------|----------|
| `sessionKey` | Yes (starts with `sk-ant-...`) |

## Known Limitations

### Free Tier
- `claude.ai/api/usage` returns **404 Not Found**
- No public usage API exists for free accounts
- Shows "Logged in ✓" but cannot display usage data

### Paid Plans (Claude Max/Pro/Team)
- OAuth API via CLI credentials works
- Web API via cookies works
- Shows session + weekly usage + model-specific data

## Snapshot Mapping (Paid Plans)

| Field | Source |
|-------|--------|
| Primary usage | `session_usage.percent_remaining` |
| Secondary usage | `usage.weekly.percent_used` |
| Reset date | `session_usage.reset_at` |
| Plan | Inferred from `rate_limit_tier` |

## Key Files

- `src/main/providers/claude.ts` - Provider implementation
- Login flow opens `claude.ai/login` in Electron BrowserWindow
