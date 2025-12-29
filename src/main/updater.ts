/**
 * Auto-Updater Module - Checks for updates from GitHub releases
 */

import { autoUpdater } from 'electron-updater';
import { dialog, BrowserWindow, Notification } from 'electron';

// Configure auto-updater for GitHub releases
autoUpdater.autoDownload = false;
autoUpdater.autoInstallOnAppQuit = true;

let updateWindow: BrowserWindow | null = null;

export function setupAutoUpdater(): void {
    // Check for updates silently on startup
    autoUpdater.checkForUpdates().catch((err) => {
        console.log('Update check failed:', err.message);
    });

    // Update available
    autoUpdater.on('update-available', (info) => {
        console.log('Update available:', info.version);

        // Notify all browser windows (Settings) about the update
        BrowserWindow.getAllWindows().forEach((win) => {
            win.webContents.send('update-available', info.version);
        });

        // Show notification
        if (Notification.isSupported()) {
            const notification = new Notification({
                title: 'UsageBar Update Available',
                body: `Version ${info.version} is available. Click to download.`,
                icon: undefined
            });
            notification.on('click', () => {
                autoUpdater.downloadUpdate();
            });
            notification.show();
        }
    });

    // Download progress - notify renderer
    autoUpdater.on('download-progress', (progress) => {
        console.log(`Download progress: ${progress.percent.toFixed(1)}%`);
        BrowserWindow.getAllWindows().forEach((win) => {
            win.webContents.send('update-download-progress', progress.percent);
        });
    });

    // Update downloaded
    autoUpdater.on('update-downloaded', (info) => {
        console.log('Update downloaded:', info.version);

        // Notify renderer that download is complete
        BrowserWindow.getAllWindows().forEach((win) => {
            win.webContents.send('update-downloaded', info.version);
        });

        dialog.showMessageBox({
            type: 'info',
            title: 'Update Ready',
            message: `Version ${info.version} has been downloaded.`,
            detail: 'The update will be installed when you quit UsageBar.',
            buttons: ['Install Now', 'Later'],
            defaultId: 0
        }).then((result) => {
            if (result.response === 0) {
                autoUpdater.quitAndInstall(false, true);
            }
        });
    });

    // Error handling
    autoUpdater.on('error', (err) => {
        console.log('Auto-updater error:', err.message);
        BrowserWindow.getAllWindows().forEach((win) => {
            win.webContents.send('update-error', err.message);
        });
    });
}

export function checkForUpdates(): void {
    autoUpdater.checkForUpdates().catch((err) => {
        console.log('Manual update check failed:', err.message);
    });
}

// Start downloading update (called from renderer via IPC)
export function downloadUpdate(): void {
    autoUpdater.downloadUpdate().catch((err) => {
        console.log('Download update failed:', err.message);
    });
}

// Install already downloaded update
export function installUpdate(): void {
    autoUpdater.quitAndInstall(false, true);
}
