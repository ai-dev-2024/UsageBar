# Gemini Provider

Gemini uses the Gemini CLI and can read local OAuth credentials for quota lookups.

## Status: ❓ Untested

## Data Sources & Fallback Order

1. **OAuth quota API** (preferred)
   - Reads Gemini CLI credentials from local credential files
   - Calls Gemini quota API directly

2. **CLI quota command** (fallback)
   - Runs `gemini quota --json`
   - Parses quota output

## Requirements

- Gemini CLI must be installed
- Run `gemini login` to authenticate

## Key Files

- `src/main/providers/gemini.ts` - Provider implementation
