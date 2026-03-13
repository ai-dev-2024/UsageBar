# Antigravity Provider

Antigravity (Windsurf) is detected by finding the running language server process.

## Status: ✅ Tested & Working

## Data Sources

1. **Process detection** (only method)
   - Scans for running Antigravity/Windsurf process
   - Extracts CSRF token from process command line
   - Uses local HTTP API to fetch usage

## Detection Method

### Windows
Uses `wmic process` to find processes with:
- Command line containing `--extensionDevelopmentPath`
- CSRF token in command line arguments

### API Endpoint

| Endpoint | Purpose |
|----------|---------|
| `POST http://127.0.0.1:<port>/usage` | Get usage data |

## HTTP Headers

```
X-Requested-With: Cascade
X-CSRF-Token: <extracted from process>
Content-Type: application/json
```

## Snapshot Mapping

| Field | Source |
|-------|--------|
| Primary usage | Session usage percent |
| Secondary usage | Weekly usage percent |
| Credits | Balance if available |

## Requirements

- Antigravity (Windsurf) must be **running**
- No separate authentication needed
- Auto-detects when app is open

## Key Files

- `src/main/providers/antigravity.ts` - Provider implementation
- Uses `child_process.exec` for process detection
