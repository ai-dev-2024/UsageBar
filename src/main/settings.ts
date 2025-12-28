/**
 * Settings Store - Manages app configuration
 */

import Store from 'electron-store';

export interface AppSettings {
    enabledProviders: string[];
    refreshInterval: number; // in minutes
    autoStart: boolean;
    theme: 'light' | 'dark' | 'system';
}

const defaultSettings: AppSettings = {
    enabledProviders: ['antigravity'],
    refreshInterval: 5,
    autoStart: false,
    theme: 'system',
};

export class SettingsStore {
    private store: Store<AppSettings>;

    constructor() {
        this.store = new Store<AppSettings>({
            name: 'config',
            defaults: defaultSettings,
        });
    }

    getAll(): AppSettings {
        return {
            enabledProviders: this.store.get('enabledProviders', defaultSettings.enabledProviders),
            refreshInterval: this.store.get('refreshInterval', defaultSettings.refreshInterval),
            autoStart: this.store.get('autoStart', defaultSettings.autoStart),
            theme: this.store.get('theme', defaultSettings.theme),
        };
    }

    setAll(settings: Partial<AppSettings>): void {
        if (settings.enabledProviders !== undefined) {
            this.store.set('enabledProviders', settings.enabledProviders);
        }
        if (settings.refreshInterval !== undefined) {
            this.store.set('refreshInterval', settings.refreshInterval);
        }
        if (settings.autoStart !== undefined) {
            this.store.set('autoStart', settings.autoStart);
        }
        if (settings.theme !== undefined) {
            this.store.set('theme', settings.theme);
        }
    }

    getEnabledProviders(): string[] {
        return this.store.get('enabledProviders', defaultSettings.enabledProviders);
    }

    setEnabledProviders(providers: string[]): void {
        this.store.set('enabledProviders', providers);
    }

    getRefreshInterval(): number {
        return this.store.get('refreshInterval', defaultSettings.refreshInterval);
    }

    setRefreshInterval(minutes: number): void {
        this.store.set('refreshInterval', minutes);
    }

    getAutoStart(): boolean {
        return this.store.get('autoStart', defaultSettings.autoStart);
    }

    setAutoStart(enabled: boolean): void {
        this.store.set('autoStart', enabled);
    }

    getTheme(): 'light' | 'dark' | 'system' {
        return this.store.get('theme', defaultSettings.theme);
    }

    setTheme(theme: 'light' | 'dark' | 'system'): void {
        this.store.set('theme', theme);
    }
}
