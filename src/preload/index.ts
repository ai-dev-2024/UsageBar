/**
 * Preload script - Exposes IPC to renderer
 */

import { contextBridge, ipcRenderer } from 'electron';

contextBridge.exposeInMainWorld('usagebar', {
    getSettings: () => ipcRenderer.invoke('get-settings'),
    saveSettings: (settings: unknown) => ipcRenderer.invoke('save-settings', settings),
    getUsage: () => ipcRenderer.invoke('get-usage'),
    refreshUsage: () => ipcRenderer.invoke('refresh-usage'),
    getEnabledProviders: () => ipcRenderer.invoke('get-enabled-providers'),

    // Custom Tray Window support
    openSettings: () => ipcRenderer.send('open-settings'),
    quit: () => ipcRenderer.send('quit-app'),
    resizeWindow: (height: number) => ipcRenderer.send('resize-window', height),
    onUsageUpdate: (callback: (usage: any) => void) => ipcRenderer.on('usage-update', (_, usage) => callback(usage)),
    openUrl: (url: string) => ipcRenderer.send('open-url', url),
    onEnabledProvidersUpdate: (callback: (providers: string[]) => void) => ipcRenderer.on('enabled-providers-update', (_, providers) => callback(providers)),
    setSelectedProvider: (providerId: string) => ipcRenderer.send('set-selected-provider', providerId),

    // Provider login flows
    cursorLogin: () => ipcRenderer.invoke('cursor-login'),
    cursorLogout: () => ipcRenderer.invoke('cursor-logout'),
    cursorHasSession: () => ipcRenderer.invoke('cursor-has-session'),
    claudeLogin: () => ipcRenderer.invoke('claude-login'),
    claudeLogout: () => ipcRenderer.invoke('claude-logout'),
    copilotLogin: () => ipcRenderer.invoke('copilot-login'),
    copilotLogout: () => ipcRenderer.invoke('copilot-logout'),
    providerLogin: (providerId: string) => ipcRenderer.invoke('provider-login', providerId),
});
