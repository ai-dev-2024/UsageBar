# GitHub Copilot Provider

Copilot uses GitHub OAuth device flow authentication.

## Status: ✅ Tested & Working

## Data Sources & Fallback Order

1. **Stored OAuth token** (preferred)
   - Captured via device flow authentication
   - Stored at: `%APPDATA%/UsageBar/copilot-token.json`

2. **Environment variable** (fallback)
   - `GITHUB_TOKEN` environment variable

3. **GitHub CLI** (fallback)
   - Reads token from `gh auth status`

## Authentication Flow

GitHub OAuth Device Flow:
1. Request device code from `POST https://github.com/login/device/code`
2. Display code to user (e.g., `ABCD-1234`)
3. User enters code at `https://github.com/login/device`
4. Poll `POST https://github.com/login/oauth/access_token` until authorized
5. Store token for future use

## API Endpoints

| Endpoint | Purpose |
|----------|---------|
| `GET https://api.github.com/copilot_internal/user` | Usage quotas + plan info |

## HTTP Headers

```
Authorization: token <github_token>
Accept: application/json
Editor-Version: vscode/1.96.2
Editor-Plugin-Version: copilot-chat/0.26.7
User-Agent: GitHubCopilotChat/0.26.7
X-Github-Api-Version: 2025-04-01
```

## Snapshot Mapping

### Paid Plans (Business/Enterprise)
| Field | Source |
|-------|--------|
| Primary usage | `quota_snapshots.premiumInteractions` percent |
| Secondary usage | `quota_snapshots.chat` percent |
| Plan | `copilot_plan` |

### Free Plans (free_limited_copilot)
| Field | Source |
|-------|--------|
| Primary | `monthly_quotas.completions` (e.g., "4000/mo") |
| Secondary | `monthly_quotas.chat` (e.g., "500/mo") |
| Reset date | `limited_user_reset_date` |

## Key Files

- `src/main/providers/copilot.ts` - Provider implementation
- Token stored in `%APPDATA%/UsageBar/copilot-token.json`
