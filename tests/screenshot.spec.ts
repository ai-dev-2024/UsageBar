/**
 * Playwright Screenshot Test for UsageBar
 * Captures screenshots of the app for visual regression testing
 */

import { test, expect } from '@playwright/test';
import { execSync } from 'child_process';
import * as path from 'path';
import * as fs from 'fs';

const SCREENSHOTS_DIR = path.join(__dirname, '..', 'screenshots');

// Ensure screenshots directory exists
if (!fs.existsSync(SCREENSHOTS_DIR)) {
    fs.mkdirSync(SCREENSHOTS_DIR, { recursive: true });
}

test.describe('UsageBar Visual Tests', () => {
    test('should capture app screenshot', async ({ page }) => {
        // This is a placeholder test - Electron apps need special setup
        // For Electron testing with Playwright, you would use:
        // const electron = require('@playwright/test').electron;
        // const app = await electron.launch({ args: ['dist/main/index.js'] });

        // For now, we capture the tray HTML file directly
        const trayHtmlPath = path.join(__dirname, '..', 'dist', 'renderer', 'tray.html');

        if (fs.existsSync(trayHtmlPath)) {
            await page.goto(`file://${trayHtmlPath}`);
            await page.setViewportSize({ width: 340, height: 480 });

            // Wait for any animations to complete
            await page.waitForTimeout(500);

            // Capture screenshot
            await page.screenshot({
                path: path.join(SCREENSHOTS_DIR, 'tray-window.png'),
                fullPage: true
            });

            console.log('Screenshot saved to screenshots/tray-window.png');
        } else {
            console.log('Build the app first: npm run build');
        }
    });

    test('should capture dark mode screenshot', async ({ page }) => {
        const trayHtmlPath = path.join(__dirname, '..', 'dist', 'renderer', 'tray.html');

        if (fs.existsSync(trayHtmlPath)) {
            // Emulate dark mode
            await page.emulateMedia({ colorScheme: 'dark' });
            await page.goto(`file://${trayHtmlPath}`);
            await page.setViewportSize({ width: 340, height: 480 });

            await page.waitForTimeout(500);

            await page.screenshot({
                path: path.join(SCREENSHOTS_DIR, 'tray-window-dark.png'),
                fullPage: true
            });

            console.log('Dark mode screenshot saved');
        }
    });
});
