export interface WindowBounds {
    x?: number;
    y?: number;
    width: number;
    height: number;
}

export interface AppSettings {
    enabledProviders: string[];
    refreshInterval: number;
    autoStart: boolean;
    theme: 'light' | 'dark' | 'system';
    hotkey: string;
    popupOpacity: number;
    windowBounds?: WindowBounds;
    settingsWindowBounds?: WindowBounds;
    notifications?: boolean;
    resetDaily?: boolean;
    [key: string]: unknown;
}

export interface ProviderSettings {
    authToken?: string;
    apiKey?: string;
    [key: string]: unknown;
}

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
    needsLogin?: boolean;
    updatedAt: string;
    credits?: {
        balance: string;
        unlimited: boolean;
    };
    dashboardUrl?: string;
    statusPageUrl?: string;
}

export interface UsageDataPoint {
    timestamp: number;
    providerId: string;
    sessionPercent: number;
    weeklyPercent?: number;
}

export enum LogLevel {
    DEBUG = 0,
    INFO = 1,
    WARN = 2,
    ERROR = 3
}

export interface LoggerOptions {
    level?: keyof typeof LogLevel;
    prefix?: string;
}
