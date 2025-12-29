/**
 * UsageBar - Main Electron Entry Point
 * Windows system tray application for AI coding tool usage stats
 */

import { app, Tray, Menu, nativeImage, NativeImage, BrowserWindow, ipcMain, shell, globalShortcut } from 'electron';
import * as path from 'path';
import { SettingsStore } from './settings';
import { ProviderManager } from './providers';
import { createTrayIcon } from './tray';

// Prevent multiple instances
const gotTheLock = app.requestSingleInstanceLock();
if (!gotTheLock) {
    app.quit();
}

let tray: Tray | null = null;
let settingsWindow: BrowserWindow | null = null;
let settings: SettingsStore;
let providerManager: ProviderManager;
let refreshInterval: NodeJS.Timeout | null = null;
let selectedProviderId: string | null = null;

// Hide from taskbar - this is a tray-only app
app.on('ready', async () => {
    settings = new SettingsStore();
    providerManager = new ProviderManager(settings);

    // Create system tray
    tray = createTray();

    // Initial fetch
    await refreshUsage();

    // Start refresh loop
    startRefreshLoop();

    // Register IPC handlers
    setupIPC();

    // Register global hotkey (Ctrl+Shift+U to toggle tray)
    globalShortcut.register('CommandOrControl+Shift+U', () => {
        toggleTrayWindow();
    });

    // Configure auto-start
    app.setLoginItemSettings({
        openAtLogin: settings.getAutoStart(),
        path: app.getPath('exe'),
    });

    console.log('UsageBar started successfully (Hotkey: Ctrl+Shift+U)');
});

let trayWindow: BrowserWindow | null = null;

function createTrayWindow() {
    // Restore saved window bounds
    const savedBounds = settings.getWindowBounds();

    trayWindow = new BrowserWindow({
        width: savedBounds.width,
        height: savedBounds.height,
        minWidth: 300,
        minHeight: 350,
        maxWidth: 500,
        maxHeight: 700,
        show: false,
        frame: false,
        fullscreenable: false,
        resizable: true,
        skipTaskbar: true,
        alwaysOnTop: true,
        webPreferences: {
            nodeIntegration: false,
            contextIsolation: true,
            preload: path.join(__dirname, '..', 'preload', 'index.js'),
            backgroundThrottling: false
        }
    });

    // Load the tray HTML
    const trayPath = path.join(__dirname, '..', 'renderer', 'tray.html');
    trayWindow.loadFile(trayPath);

    // Save window bounds on resize
    trayWindow.on('resize', () => {
        if (trayWindow && !trayWindow.isDestroyed()) {
            const bounds = trayWindow.getBounds();
            settings.setWindowBounds({
                width: bounds.width,
                height: bounds.height,
                x: bounds.x,
                y: bounds.y
            });
        }
    });

    // Hide on blur (clicking outside)
    trayWindow.on('blur', () => {
        if (!trayWindow?.webContents.isDevToolsOpened()) {
            trayWindow?.hide();
        }
    });
}

function toggleTrayWindow() {
    if (!trayWindow) createTrayWindow();
    if (!trayWindow || !tray) return;

    if (trayWindow.isVisible()) {
        trayWindow.hide();
    } else {
        const { screen } = require('electron');
        const trayBounds = tray.getBounds();
        const windowBounds = trayWindow.getBounds();
        const display = screen.getDisplayNearestPoint({ x: trayBounds.x, y: trayBounds.y });
        const workArea = display.workArea;

        // Calculate position - try to center horizontally on tray
        let x = Math.round(trayBounds.x + (trayBounds.width / 2) - (windowBounds.width / 2));
        let y = Math.round(trayBounds.y - windowBounds.height - 10);

        // Ensure window stays within screen bounds
        // Clamp X to not go off left or right
        if (x < workArea.x) x = workArea.x + 10;
        if (x + windowBounds.width > workArea.x + workArea.width) {
            x = workArea.x + workArea.width - windowBounds.width - 10;
        }

        // If taskbar is at top, position below it
        if (trayBounds.y < workArea.y + 50) {
            y = trayBounds.y + trayBounds.height + 10;
        }

        // Clamp Y to not go off top or bottom
        if (y < workArea.y) y = workArea.y + 10;
        if (y + windowBounds.height > workArea.y + workArea.height) {
            y = workArea.y + workArea.height - windowBounds.height - 10;
        }

        trayWindow.setPosition(x, y, false);
        trayWindow.show();
        trayWindow.focus();

        // Refresh data on open
        refreshUsage();
    }
}

function createTray(): Tray {
    const iconPath = path.join(__dirname, '../../assets/icon.png');
    const icon = nativeImage.createFromPath(iconPath);

    const tray = new Tray(icon.isEmpty() ? createDefaultIcon() : icon);
    tray.setToolTip('UsageBar - AI Usage Monitor');

    tray.on('click', () => {
        toggleTrayWindow();
    });

    return tray;
}

function createDefaultIcon(): NativeImage {
    // Create a simple 16x16 icon if no icon file exists
    const size = 16;
    const canvas = Buffer.alloc(size * size * 4);

    // Fill with a gradient-like pattern (blue to green)
    for (let y = 0; y < size; y++) {
        for (let x = 0; x < size; x++) {
            const i = (y * size + x) * 4;
            canvas[i] = 50;     // R
            canvas[i + 1] = 150 + Math.floor((x / size) * 100); // G
            canvas[i + 2] = 200; // B
            canvas[i + 3] = 255; // A
        }
    }

    return nativeImage.createFromBuffer(canvas, { width: size, height: size });
}

// showContextMenu function removed as we use custom window now

function formatResetTime(date: Date): string {
    const now = new Date();
    const diff = date.getTime() - now.getTime();

    if (diff < 0) return 'now';

    const hours = Math.floor(diff / (1000 * 60 * 60));
    const minutes = Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60));

    if (hours < 1) {
        return `in ${minutes}m`;
    } else if (hours < 24) {
        return `in ${hours}h ${minutes}m`;
    } else {
        const days = Math.floor(hours / 24);
        return `in ${days}d ${hours % 24}h`;
    }
}

async function refreshUsage(): Promise<void> {
    console.log('Refreshing usage...');

    try {
        await providerManager.refreshAll();
        updateTrayIcon();
        const usage = providerManager.getLatestUsage();

        // Push update to tray window if it exists
        if (trayWindow && !trayWindow.isDestroyed()) {
            trayWindow.webContents.send('usage-update', usage);
        }

        console.log('Usage refreshed successfully');
    } catch (error) {
        console.error('Error refreshing usage:', error);
    }
}

function updateTrayIcon(): void {
    if (!tray) return;

    const usage = providerManager.getLatestUsage();
    const enabledProviders = settings.getEnabledProviders();

    // Use selected provider's usage if available, otherwise average
    let sessionPercent = 0;
    let weeklyPercent = 0;
    let providerName = 'UsageBar';

    if (selectedProviderId && usage[selectedProviderId]?.primary) {
        sessionPercent = usage[selectedProviderId].primary!.usedPercent;
        weeklyPercent = usage[selectedProviderId].secondary?.usedPercent || sessionPercent;
        providerName = usage[selectedProviderId].displayName || selectedProviderId;
    } else {
        // Fall back to average of all enabled providers
        let totalSession = 0, totalWeekly = 0, count = 0;
        for (const providerId of enabledProviders) {
            const providerUsage = usage[providerId];
            if (providerUsage?.primary) {
                totalSession += providerUsage.primary.usedPercent;
                totalWeekly += providerUsage.secondary?.usedPercent || providerUsage.primary.usedPercent;
                count++;
            }
        }
        sessionPercent = count > 0 ? totalSession / count : 0;
        weeklyPercent = count > 0 ? totalWeekly / count : 0;
    }

    // Dynamic dual-bar meter for taskbar (session top, weekly bottom)
    const { createDualBarTrayIcon } = require('./tray');
    const icon = createDualBarTrayIcon(sessionPercent, weeklyPercent);
    tray.setImage(icon);

    // Update Windows Taskbar Overlay if Settings Window is open
    if (settingsWindow && !settingsWindow.isDestroyed()) {
        const description = `${(100 - sessionPercent).toFixed(0)}% session, ${(100 - weeklyPercent).toFixed(0)}% weekly`;
        settingsWindow.setOverlayIcon(icon, description);
    }

    // Update tooltip with selected provider info
    const sessionRemaining = Math.max(0, 100 - sessionPercent);
    const weeklyRemaining = Math.max(0, 100 - weeklyPercent);
    const tooltip = selectedProviderId
        ? `${providerName}: ${sessionRemaining.toFixed(0)}% session, ${weeklyRemaining.toFixed(0)}% weekly`
        : `UsageBar: ${sessionRemaining.toFixed(0)}% session, ${weeklyRemaining.toFixed(0)}% weekly`;
    tray.setToolTip(tooltip);
}

function startRefreshLoop(): void {
    if (refreshInterval) {
        clearInterval(refreshInterval);
    }

    const intervalMs = settings.getRefreshInterval() * 60 * 1000;
    refreshInterval = setInterval(() => refreshUsage(), intervalMs);
}

function openSettings(): void {
    if (settingsWindow) {
        settingsWindow.focus();
        return;
    }

    settingsWindow = new BrowserWindow({
        width: 500,
        height: 600,
        resizable: false,
        minimizable: false,
        maximizable: false,
        title: 'UsageBar Settings',
        webPreferences: {
            nodeIntegration: false,
            contextIsolation: true,
            preload: path.join(__dirname, '..', 'preload', 'index.js'),
        },
        icon: path.join(__dirname, '../../assets/icon.png'),
    });

    // Use the correct path relative to dist folder
    const htmlPath = path.join(__dirname, '..', 'renderer', 'settings.html');
    console.log('[Settings] Loading HTML from:', htmlPath);
    settingsWindow.loadFile(htmlPath);

    settingsWindow.on('closed', () => {
        settingsWindow = null;
    });
}

function setupIPC(): void {
    ipcMain.handle('get-settings', () => {
        return settings.getAll();
    });

    ipcMain.handle('save-settings', (_, newSettings) => {
        settings.setAll(newSettings);
        startRefreshLoop(); // Restart with new interval

        // Immediately notify tray window of enabled providers change
        if (trayWindow && !trayWindow.isDestroyed()) {
            trayWindow.webContents.send('enabled-providers-update', settings.getEnabledProviders());
        }

        return true;
    });

    ipcMain.handle('get-usage', () => {
        return providerManager.getLatestUsage();
    });

    ipcMain.handle('refresh-usage', async () => {
        await refreshUsage();
        return providerManager.getLatestUsage();
    });

    ipcMain.handle('get-enabled-providers', () => {
        return settings.getEnabledProviders();
    });

    ipcMain.on('set-selected-provider', (_, providerId) => {
        selectedProviderId = providerId;
        updateTrayIcon();
    });

    // Custom Tray Handlers
    ipcMain.on('open-settings', () => {
        trayWindow?.hide();
        openSettings();
    });

    ipcMain.on('quit-app', () => {
        app.quit();
    });

    ipcMain.on('resize-window', (_, height) => {
        if (trayWindow && !trayWindow.isDestroyed()) {
            // Keep width, update height
            const [width] = trayWindow.getSize();
            // Recalculate y position to stay anchored to bottom
            const bounds = trayWindow.getBounds();
            const newY = bounds.y + (bounds.height - height);
            // Actually it's simpler on Windows since taskbar is usually bottom,
            // growing height upwards means reducing y.
            // But bounds.y is top-left.
            // If we just resize, it grows downwards.
            // We need to move it up by delta.
            const delta = height - bounds.height;
            trayWindow.setBounds({
                x: bounds.x,
                y: bounds.y - delta,
                width: width,
                height: height
            });
        }
    });
    ipcMain.on('open-url', (_, url) => {
        shell.openExternal(url);
    });

    // Windows Toast Notification for quota alerts
    ipcMain.on('show-notification', (_, title, body) => {
        const { Notification } = require('electron');
        if (Notification.isSupported()) {
            const notification = new Notification({
                title: title,
                body: body,
                icon: path.join(__dirname, '../../assets/icon.png'),
                silent: false
            });
            notification.show();
        }
    });

    // Cursor login flow
    ipcMain.handle('cursor-login', async () => {
        const cursorProvider = providerManager.getCursorProvider();
        const success = await cursorProvider.openLoginWindow();
        if (success) {
            await refreshUsage();
        }
        return success;
    });

    ipcMain.handle('cursor-logout', async () => {
        const cursorProvider = providerManager.getCursorProvider();
        cursorProvider.clearStoredSession();
        await refreshUsage();
        return true;
    });

    ipcMain.handle('cursor-has-session', () => {
        const cursorProvider = providerManager.getCursorProvider();
        return cursorProvider.hasStoredSession();
    });

    // Claude login flow
    ipcMain.handle('claude-login', async () => {
        const claudeProvider = providerManager.getClaudeProvider();
        const success = await claudeProvider.openLoginWindow();
        if (success) {
            await refreshUsage();
        }
        return success;
    });

    ipcMain.handle('claude-logout', async () => {
        const claudeProvider = providerManager.getClaudeProvider();
        claudeProvider.clearStoredSession();
        await refreshUsage();
        return true;
    });

    // Copilot login flow
    ipcMain.handle('copilot-login', async () => {
        const copilotProvider = providerManager.getCopilotProvider();
        const success = await copilotProvider.openLoginWindow();
        if (success) {
            await refreshUsage();
        }
        return success;
    });

    ipcMain.handle('copilot-logout', async () => {
        const copilotProvider = providerManager.getCopilotProvider();
        copilotProvider.clearStoredSession();
        await refreshUsage();
        return true;
    });

    // Generic provider login handler
    ipcMain.handle('provider-login', async (_, providerId: string) => {
        let success = false;
        switch (providerId) {
            case 'cursor':
                success = await providerManager.getCursorProvider().openLoginWindow();
                break;
            case 'claude':
                success = await providerManager.getClaudeProvider().openLoginWindow();
                break;
            case 'copilot':
                success = await providerManager.getCopilotProvider().openLoginWindow();
                break;
        }
        if (success) {
            await refreshUsage();
        }
        return success;
    });
}

// Handle app lifecycle
app.on('window-all-closed', () => {
    // Don't quit when all windows are closed (tray app)
});

app.on('before-quit', () => {
    if (refreshInterval) {
        clearInterval(refreshInterval);
    }
});
