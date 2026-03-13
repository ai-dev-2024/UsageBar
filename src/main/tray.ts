/**
 * Tray Icon Renderer - Creates dynamic usage meter icons
 */

import { nativeImage, NativeImage } from 'electron';

const ICON_SIZE = 16;

/**
 * Create a tray icon showing usage level
 * @param usedPercent - Percentage of quota used (0-100)
 */
export function createTrayIcon(usedPercent: number): NativeImage {
    const canvas = Buffer.alloc(ICON_SIZE * ICON_SIZE * 4);

    // Calculate fill level (inverse of used)
    const remaining = Math.max(0, Math.min(100, 100 - usedPercent));
    const fillHeight = Math.floor((remaining / 100) * (ICON_SIZE - 4));

    // Background color (dark gray)
    const bgR = 40, bgG = 40, bgB = 40;

    // Fill color based on remaining percentage - teal for macOS parity
    let fillR: number, fillG: number, fillB: number;
    if (remaining > 50) {
        // Teal (#14B8A6)
        fillR = 20; fillG = 184; fillB = 166;
    } else if (remaining > 20) {
        // Yellow/Orange
        fillR = 255; fillG = 193; fillB = 7;
    } else {
        // Red
        fillR = 244; fillG = 67; fillB = 54;
    }

    // Border color
    const borderR = 100, borderG = 100, borderB = 100;

    for (let y = 0; y < ICON_SIZE; y++) {
        for (let x = 0; x < ICON_SIZE; x++) {
            const i = (y * ICON_SIZE + x) * 4;

            // Check if on border
            const isBorder = x === 0 || x === ICON_SIZE - 1 || y === 0 || y === ICON_SIZE - 1;

            // Check if in fill area (from bottom)
            const fillStartY = ICON_SIZE - 2 - fillHeight;
            const isInFill = !isBorder && x > 1 && x < ICON_SIZE - 2 && y > fillStartY && y < ICON_SIZE - 1;

            if (isBorder) {
                canvas[i] = borderR;
                canvas[i + 1] = borderG;
                canvas[i + 2] = borderB;
                canvas[i + 3] = 255;
            } else if (isInFill) {
                canvas[i] = fillR;
                canvas[i + 1] = fillG;
                canvas[i + 2] = fillB;
                canvas[i + 3] = 255;
            } else {
                canvas[i] = bgR;
                canvas[i + 1] = bgG;
                canvas[i + 2] = bgB;
                canvas[i + 3] = 255;
            }
        }
    }

    return nativeImage.createFromBuffer(canvas, {
        width: ICON_SIZE,
        height: ICON_SIZE,
    });
}

/**
 * Create a two-bar tray icon like CodexBar (session + weekly)
 * @param sessionPercent - Session/primary usage percentage (0-100)
 * @param weeklyPercent - Weekly/secondary usage percentage (0-100)
 */
export function createDualBarTrayIcon(sessionPercent: number, weeklyPercent: number): NativeImage {
    const canvas = Buffer.alloc(ICON_SIZE * ICON_SIZE * 4);

    // Calculate remaining for both bars
    const sessionRemaining = Math.max(0, Math.min(100, 100 - sessionPercent));
    const weeklyRemaining = Math.max(0, Math.min(100, 100 - weeklyPercent));

    // Fill widths (horizontal bars)
    const sessionFillWidth = Math.floor((sessionRemaining / 100) * (ICON_SIZE - 4));
    const weeklyFillWidth = Math.floor((weeklyRemaining / 100) * (ICON_SIZE - 4));

    // Colors based on remaining percentage
    const getColor = (remaining: number) => {
        if (remaining > 50) return { r: 20, g: 184, b: 166 };  // Teal
        if (remaining > 20) return { r: 255, g: 193, b: 7 };   // Yellow
        return { r: 244, g: 67, b: 54 };                        // Red
    };

    const sessionColor = getColor(sessionRemaining);
    const weeklyColor = getColor(weeklyRemaining);

    // Background and border
    const bgR = 40, bgG = 40, bgB = 40;
    const borderR = 80, borderG = 80, borderB = 80;

    // Top bar: y = 2-6 (session, thicker)
    // Bottom bar: y = 9-12 (weekly, thinner)
    for (let y = 0; y < ICON_SIZE; y++) {
        for (let x = 0; x < ICON_SIZE; x++) {
            const i = (y * ICON_SIZE + x) * 4;

            // Border
            const isBorder = x === 0 || x === ICON_SIZE - 1 || y === 0 || y === ICON_SIZE - 1;

            // Session bar area (y: 2-6, thicker 5px)
            const isSessionArea = y >= 2 && y <= 6 && x >= 2 && x < ICON_SIZE - 2;
            const isSessionFill = isSessionArea && x < 2 + sessionFillWidth;

            // Weekly bar area (y: 9-12, thinner 4px)
            const isWeeklyArea = y >= 9 && y <= 12 && x >= 2 && x < ICON_SIZE - 2;
            const isWeeklyFill = isWeeklyArea && x < 2 + weeklyFillWidth;

            if (isBorder) {
                canvas[i] = borderR;
                canvas[i + 1] = borderG;
                canvas[i + 2] = borderB;
                canvas[i + 3] = 255;
            } else if (isSessionFill) {
                canvas[i] = sessionColor.r;
                canvas[i + 1] = sessionColor.g;
                canvas[i + 2] = sessionColor.b;
                canvas[i + 3] = 255;
            } else if (isWeeklyFill) {
                canvas[i] = weeklyColor.r;
                canvas[i + 1] = weeklyColor.g;
                canvas[i + 2] = weeklyColor.b;
                canvas[i + 3] = 255;
            } else if (isSessionArea || isWeeklyArea) {
                // Empty bar background (darker)
                canvas[i] = 25;
                canvas[i + 1] = 25;
                canvas[i + 2] = 25;
                canvas[i + 3] = 255;
            } else {
                canvas[i] = bgR;
                canvas[i + 1] = bgG;
                canvas[i + 2] = bgB;
                canvas[i + 3] = 255;
            }
        }
    }

    return nativeImage.createFromBuffer(canvas, {
        width: ICON_SIZE,
        height: ICON_SIZE,
    });
}

/**
 * Create an error state icon (dimmed with X)
 */
export function createErrorIcon(): NativeImage {
    const canvas = Buffer.alloc(ICON_SIZE * ICON_SIZE * 4);

    for (let y = 0; y < ICON_SIZE; y++) {
        for (let x = 0; x < ICON_SIZE; x++) {
            const i = (y * ICON_SIZE + x) * 4;

            // Dark gray background
            canvas[i] = 60;
            canvas[i + 1] = 60;
            canvas[i + 2] = 60;
            canvas[i + 3] = 180; // Semi-transparent

            // Draw X
            if (Math.abs(x - y) < 2 || Math.abs(x - (ICON_SIZE - 1 - y)) < 2) {
                canvas[i] = 200;
                canvas[i + 1] = 50;
                canvas[i + 2] = 50;
                canvas[i + 3] = 255;
            }
        }
    }

    return nativeImage.createFromBuffer(canvas, {
        width: ICON_SIZE,
        height: ICON_SIZE,
    });
}

/**
 * Create a loading state icon (animated spinner frame)
 */
export function createLoadingIcon(frame: number): NativeImage {
    const canvas = Buffer.alloc(ICON_SIZE * ICON_SIZE * 4);
    const center = ICON_SIZE / 2;
    const radius = ICON_SIZE / 2 - 2;

    for (let y = 0; y < ICON_SIZE; y++) {
        for (let x = 0; x < ICON_SIZE; x++) {
            const i = (y * ICON_SIZE + x) * 4;

            const dx = x - center;
            const dy = y - center;
            const dist = Math.sqrt(dx * dx + dy * dy);
            const angle = Math.atan2(dy, dx);

            // Create spinner effect
            const normalizedAngle = (angle + Math.PI) / (2 * Math.PI);
            const frameAngle = (frame / 8) % 1;
            const diff = Math.abs(normalizedAngle - frameAngle);
            const intensity = Math.max(0, 1 - diff * 4);

            if (dist > radius - 2 && dist < radius + 1) {
                canvas[i] = Math.floor(50 + intensity * 150);
                canvas[i + 1] = Math.floor(150 + intensity * 100);
                canvas[i + 2] = Math.floor(200);
                canvas[i + 3] = 255;
            } else {
                canvas[i] = 40;
                canvas[i + 1] = 40;
                canvas[i + 2] = 40;
                canvas[i + 3] = 0;
            }
        }
    }

    return nativeImage.createFromBuffer(canvas, {
        width: ICON_SIZE,
        height: ICON_SIZE,
    });
}
