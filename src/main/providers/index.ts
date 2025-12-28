/**
 * Provider Manager - Orchestrates all provider fetches
 */

import { SettingsStore } from '../settings';
import { AntigravityProvider } from './antigravity';
import { ClaudeProvider } from './claude';
import { CodexProvider } from './codex';
import { CopilotProvider } from './copilot';
import { CursorProvider } from './cursor';
import { GeminiProvider } from './gemini';
import { FactoryProvider } from './factory';
import { ZaiProvider } from './zai';

export interface RateWindow {
    usedPercent: number;
    windowMinutes?: number;
    resetsAt?: string;
    resetDescription?: string;
}

export interface ProviderUsage {
    providerId: string;
    displayName: string;
    primary?: RateWindow;
    secondary?: RateWindow;
    tertiary?: RateWindow;
    accountEmail?: string;
    accountPlan?: string;
    version?: string;
    error?: string;
    updatedAt: string;
    // New fields for macOS parity
    credits?: {
        balance: string;
        unlimited: boolean;
    };
    dashboardUrl?: string;
    statusPageUrl?: string;
}

export interface Provider {
    id: string;
    displayName: string;
    fetch(): Promise<ProviderUsage>;
    isAvailable(): Promise<boolean>;
}

export class ProviderManager {
    private settings: SettingsStore;
    private providers: Map<string, Provider>;
    private latestUsage: Record<string, ProviderUsage> = {};

    constructor(settings: SettingsStore) {
        this.settings = settings;
        this.providers = new Map();

        // Register all providers
        this.registerProvider(new AntigravityProvider());
        this.registerProvider(new ClaudeProvider());
        this.registerProvider(new CodexProvider());
        this.registerProvider(new CopilotProvider());
        this.registerProvider(new CursorProvider());
        this.registerProvider(new GeminiProvider());
        this.registerProvider(new FactoryProvider());
        this.registerProvider(new ZaiProvider());
    }

    private registerProvider(provider: Provider): void {
        this.providers.set(provider.id, provider);
    }

    getProvider(id: string): Provider | undefined {
        return this.providers.get(id);
    }

    getAllProviders(): Provider[] {
        return Array.from(this.providers.values());
    }

    async refreshAll(): Promise<void> {
        const enabledProviders = this.settings.getEnabledProviders();

        const promises = enabledProviders.map(async (providerId) => {
            const provider = this.providers.get(providerId);
            if (!provider) {
                console.warn(`Provider not found: ${providerId}`);
                return;
            }

            try {
                const usage = await provider.fetch();
                this.latestUsage[providerId] = usage;
            } catch (error) {
                console.error(`Error fetching ${providerId}:`, error);
                this.latestUsage[providerId] = {
                    providerId,
                    displayName: provider.displayName,
                    error: error instanceof Error ? error.message : 'Unknown error',
                    updatedAt: new Date().toISOString(),
                };
            }
        });

        await Promise.all(promises);
    }

    async refreshProvider(providerId: string): Promise<ProviderUsage | null> {
        const provider = this.providers.get(providerId);
        if (!provider) {
            return null;
        }

        try {
            const usage = await provider.fetch();
            this.latestUsage[providerId] = usage;
            return usage;
        } catch (error) {
            const errorUsage: ProviderUsage = {
                providerId,
                displayName: provider.displayName,
                error: error instanceof Error ? error.message : 'Unknown error',
                updatedAt: new Date().toISOString(),
            };
            this.latestUsage[providerId] = errorUsage;
            return errorUsage;
        }
    }

    getLatestUsage(): Record<string, ProviderUsage> {
        return { ...this.latestUsage };
    }

    getProviderUsage(providerId: string): ProviderUsage | undefined {
        return this.latestUsage[providerId];
    }
}
