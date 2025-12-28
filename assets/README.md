# UsageBar Assets

This directory contains icon assets for the application.

## icon.png
A 256x256 PNG icon for the system tray. The icon displays a two-bar meter:
- Top bar: Session/5-hour usage
- Bottom bar: Weekly usage

Colors:
- Green (>50% remaining)
- Yellow/Orange (20-50% remaining)  
- Red (<20% remaining)

## Generating icon.ico for Windows

Use an online converter or ImageMagick:
```bash
magick icon.png -define icon:auto-resize=256,128,64,48,32,16 icon.ico
```

For now, the app uses a programmatically generated icon via `createTrayIcon()` in `src/main/tray.ts`.
