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
