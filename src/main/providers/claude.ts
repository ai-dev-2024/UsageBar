/**
 * Claude Provider - Implementation based on CodexBar
 * Uses browser login flow to capture session cookies and fetch usage from console.anthropic.com
 * 
 * API Endpoints:
 * - https://console.anthropic.com/api/usage - Usage data (for Pro users)
 * - https://claude.ai/api/usage - Usage data (for Claude Max users)
 */

import * as fs from 'fs';
import * as path from 'path';
import axios from 'axios';
import { Provider, ProviderUsage, RateWindow } from './index';
import { app, BrowserWindow, session } from 'electron';
import { exec } from 'child_process';
import { promisify } from 'util';

const execAsync = promisify(exec);

// Cookie names used by Claude for authentication
const SESSION_COOKIE_NAMES = [
    'sessionKey',
    '__Secure-next-auth.session-token',
    'next-auth.session-token',
];

interface ClaudeUsageResponse {
    usage?: {
        session?: {
            percent_used?: number;
            reset_at?: string;
        };
        weekly?: {
            percent_used?: number;
            reset_at?: string;
        };
    };
    session_usage?: {
        percent_remaining?: number;
        reset_at?: string;
    };
    weekly_usage?: {
        percent_remaining?: number;
        reset_at?: string;
    };
    organization?: {
        name?: string;
    };
    user?: {
        email?: string;
    };
    plan?: string;
}

interface StoredSession {
    cookies: Array<{
        name: string;
        value: string;
        domain: string;
        path: string;
        expirationDate?: number;
    }>;
    savedAt: string;
    source: 'console' | 'claude.ai';
}

export class ClaudeProvider implements Provider {
    id = 'claude';
    displayName = 'Claude';
    private timeout = 15000;
    private sessionFilePath: string;
    private loginWindow: BrowserWindow | null = null;

    constructor() {
        const appDataPath = app.getPath('userData');
        this.sessionFilePath = path.join(appDataPath, 'claude-session.json');
    }

    async fetch(): Promise<ProviderUsage> {
        try {
            console.log('[Claude] Starting fetch...');

            // FIRST: Try stored session cookies from browser login (paid users)
            const cookieHeader = await this.getCookieHeader();

            if (cookieHeader) {
                console.log('[Claude] Got cookie header, fetching usage...');

                // Try fetching from claude.ai (for Claude Max users)
                const claudeAiResult = await this.fetchFromClaudeAi(cookieHeader);
                if (claudeAiResult) {
                    return claudeAiResult;
                }

                // Try console.anthropic.com (for API/Pro users)
                const consoleResult = await this.fetchFromConsole(cookieHeader);
                if (consoleResult) {
                    return consoleResult;
                }

                // Cookies exist but APIs didn't return usage data
                // Don't clear session - user is logged in, just can't get usage data
                console.log('[Claude] API calls failed - keeping session, showing logged in status');
                return {
                    providerId: this.id,
                    displayName: this.displayName,
                    error: 'Logged in. Usage API not available for your plan.',
                    needsLogin: false, // User IS logged in, just can't get usage
                    dashboardUrl: 'https://claude.ai/settings',
                    updatedAt: new Date().toISOString(),
                };
            }

            // SECOND: Check if Claude CLI is installed
            const cliVersion = await this.detectCLIVersion();
            if (cliVersion) {
                console.log('[Claude] CLI detected:', cliVersion);
                // CLI is installed but we can't get real usage without paid plan
                // Show that CLI is detected but usage requires paid subscription
                return {
                    providerId: this.id,
                    displayName: this.displayName,
                    error: 'Claude CLI detected. Paid plan (Claude Max/Pro) required to view usage.',
                    needsLogin: true,
                    version: cliVersion,
                    dashboardUrl: 'https://console.anthropic.com/settings/usage',
                    statusPageUrl: 'https://status.anthropic.com',
                    updatedAt: new Date().toISOString(),
                };
            }

            // Neither browser session nor CLI - needs setup
            console.log('[Claude] No session - needs login');
            return {
                providerId: this.id,
                displayName: this.displayName,
                error: 'Sign in with Claude Max/Pro to view usage',
                needsLogin: true,
                updatedAt: new Date().toISOString(),
            };
        } catch (error) {
            console.error('[Claude] Fetch error:', error);
            return {
                providerId: this.id,
                displayName: this.displayName,
                error: error instanceof Error ? error.message : 'Failed to fetch Claude usage',
                updatedAt: new Date().toISOString(),
            };
        }
    }

    async isAvailable(): Promise<boolean> {
        const cliVersion = await this.detectCLIVersion();
        if (cliVersion) return true;
        const cookieHeader = await this.getCookieHeader();
        return !!cookieHeader;
    }

    /**
     * Detect Claude CLI version
     */
    private async detectCLIVersion(): Promise<string | null> {
        try {
            const { stdout } = await execAsync('claude --version', { timeout: 5000 });
            const match = stdout.match(/(\d+\.\d+\.\d+)/);
            return match ? match[1] : 'unknown';
        } catch {
            return null;
        }
    }

    /**
     * Fetch usage via Claude CLI
     */
    private async fetchWithCLI(version: string): Promise<ProviderUsage> {
        try {
            // Try to get usage info from Claude CLI
            const { stdout } = await execAsync('claude usage --json', { timeout: this.timeout });
            const data = JSON.parse(stdout);

            const primary: RateWindow | undefined = data.session ? {
                usedPercent: data.session.percent_used || 0,
                resetsAt: data.session.reset_at,
                resetDescription: 'Session',
            } : undefined;

            const secondary: RateWindow | undefined = data.weekly ? {
                usedPercent: data.weekly.percent_used || 0,
                resetsAt: data.weekly.reset_at,
                resetDescription: 'Weekly',
            } : undefined;

            return {
                providerId: this.id,
                displayName: this.displayName,
                primary,
                secondary,
                accountEmail: data.email,
                accountPlan: data.plan,
                version,
                dashboardUrl: 'https://console.anthropic.com/settings/usage',
                statusPageUrl: 'https://status.anthropic.com',
                updatedAt: new Date().toISOString(),
            };
        } catch {
            return {
                providerId: this.id,
                displayName: this.displayName,
                error: 'Claude CLI not authenticated',
                needsLogin: true,
                updatedAt: new Date().toISOString(),
            };
        }
    }

    /**
     * Open a login window for the user to sign in to Claude
     */
    async openLoginWindow(): Promise<boolean> {
        return new Promise((resolve) => {
            console.log('[Claude] Opening login window...');

            if (this.loginWindow && !this.loginWindow.isDestroyed()) {
                this.loginWindow.close();
            }

            this.loginWindow = new BrowserWindow({
                width: 800,
                height: 700,
                title: 'Sign in to Claude',
                webPreferences: {
                    nodeIntegration: false,
                    contextIsolation: true,
                    partition: 'persist:claude-login',
                },
                autoHideMenuBar: true,
            });

            const loginSession = session.fromPartition('persist:claude-login');

            // Load claude.ai login page (for free tier users)
            this.loginWindow.loadURL('https://claude.ai/login');

            const checkForSession = async () => {
                try {
                    // Get ALL cookies from the session (empty filter gets all)
                    const allCookies = await loginSession.cookies.get({});

                    // Filter for relevant domains
                    const relevantCookies = allCookies.filter(c =>
                        c.domain?.includes('anthropic.com') ||
                        c.domain?.includes('claude.ai')
                    );

                    console.log('[Claude] Found cookies:', relevantCookies.length, 'relevant cookies');

                    // Look for session cookie
                    const sessionCookie = relevantCookies.find(c => SESSION_COOKIE_NAMES.includes(c.name));

                    if (sessionCookie) {
                        console.log('[Claude] Session cookie found:', sessionCookie.name);
                        await this.saveSessionCookies(relevantCookies, 'console');

                        if (this.loginWindow && !this.loginWindow.isDestroyed()) {
                            this.loginWindow.close();
                        }

                        resolve(true);
                        return true;
                    }
                } catch (error) {
                    console.error('[Claude] Error checking cookies:', error);
                }
                return false;
            };

            const interval = setInterval(async () => {
                if (this.loginWindow?.isDestroyed()) {
                    clearInterval(interval);
                    resolve(false);
                    return;
                }

                const success = await checkForSession();
                if (success) {
                    clearInterval(interval);
                }
            }, 1000);

            this.loginWindow.on('closed', () => {
                clearInterval(interval);
                this.loginWindow = null;
            });

            this.loginWindow.webContents.on('did-navigate', async () => {
                await checkForSession();
            });
        });
    }

    private async saveSessionCookies(cookies: Electron.Cookie[], source: 'console' | 'claude.ai'): Promise<void> {
        try {
            const relevantCookies = cookies.filter(c =>
                c.domain?.includes('anthropic.com') || c.domain?.includes('claude.ai')
            );

            const sessionData: StoredSession = {
                cookies: relevantCookies.map(c => ({
                    name: c.name,
                    value: c.value,
                    domain: c.domain || '',
                    path: c.path || '/',
                    expirationDate: c.expirationDate,
                })),
                savedAt: new Date().toISOString(),
                source,
            };

            fs.writeFileSync(this.sessionFilePath, JSON.stringify(sessionData, null, 2));
            console.log('[Claude] Session saved with', relevantCookies.length, 'cookies');
        } catch (error) {
            console.error('[Claude] Failed to save session:', error);
        }
    }

    private loadStoredSession(): StoredSession | null {
        try {
            if (fs.existsSync(this.sessionFilePath)) {
                const data = fs.readFileSync(this.sessionFilePath, 'utf-8');
                return JSON.parse(data);
            }
        } catch (error) {
            console.error('[Claude] Failed to load session:', error);
        }
        return null;
    }

    clearStoredSession(): void {
        try {
            if (fs.existsSync(this.sessionFilePath)) {
                fs.unlinkSync(this.sessionFilePath);
                console.log('[Claude] Session cleared');
            }
        } catch (error) {
            console.error('[Claude] Failed to clear session:', error);
        }
    }

    hasStoredSession(): boolean {
        const session = this.loadStoredSession();
        if (!session) return false;
        return session.cookies.some(c => SESSION_COOKIE_NAMES.includes(c.name));
    }

    private async getCookieHeader(): Promise<string | null> {
        const storedSession = this.loadStoredSession();
        if (!storedSession || storedSession.cookies.length === 0) {
            return null;
        }

        const now = Date.now() / 1000;
        const validCookies = storedSession.cookies.filter(c => {
            if (!c.expirationDate) return true;
            return c.expirationDate > now;
        });

        if (validCookies.length === 0) {
            console.log('[Claude] All cookies expired');
            this.clearStoredSession();
            return null;
        }

        return validCookies.map(c => `${c.name}=${c.value}`).join('; ');
    }

    private async fetchFromConsole(cookieHeader: string): Promise<ProviderUsage | null> {
        try {
            const response = await axios.get<ClaudeUsageResponse>(
                'https://console.anthropic.com/api/usage',
                {
                    headers: {
                        'Accept': 'application/json',
                        'Cookie': cookieHeader,
                        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                    },
                    timeout: this.timeout,
                    validateStatus: (status) => status < 500,
                }
            );

            if (response.status === 401 || response.status === 403) {
                return null;
            }

            if (response.status !== 200) {
                return null;
            }

            return this.parseUsageResponse(response.data, 'console');
        } catch {
            return null;
        }
    }

    private async fetchFromClaudeAi(cookieHeader: string): Promise<ProviderUsage | null> {
        try {
            console.log('[Claude] Fetching from claude.ai/api/usage...');
            const response = await axios.get<ClaudeUsageResponse>(
                'https://claude.ai/api/usage',
                {
                    headers: {
                        'Accept': 'application/json',
                        'Cookie': cookieHeader,
                        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                    },
                    timeout: this.timeout,
                    validateStatus: (status) => status < 500,
                }
            );

            console.log('[Claude] claude.ai response status:', response.status);
            console.log('[Claude] claude.ai response data:', JSON.stringify(response.data, null, 2));

            if (response.status === 401 || response.status === 403) {
                console.log('[Claude] Session expired or unauthorized');
                return null;
            }

            if (response.status !== 200) {
                console.log('[Claude] Non-200 response:', response.status);
                return null;
            }

            return this.parseUsageResponse(response.data, 'claude.ai');
        } catch (error) {
            console.error('[Claude] fetchFromClaudeAi error:', error);
            return null;
        }
    }

    private parseUsageResponse(data: ClaudeUsageResponse, source: string): ProviderUsage {
        // Parse session usage
        let sessionPercent = 0;
        let sessionReset: string | undefined;

        if (data.session_usage) {
            sessionPercent = 100 - (data.session_usage.percent_remaining || 0);
            sessionReset = data.session_usage.reset_at;
        } else if (data.usage?.session) {
            sessionPercent = data.usage.session.percent_used || 0;
            sessionReset = data.usage.session.reset_at;
        }

        // Parse weekly usage
        let weeklyPercent: number | undefined;
        let weeklyReset: string | undefined;

        if (data.weekly_usage) {
            weeklyPercent = 100 - (data.weekly_usage.percent_remaining || 0);
            weeklyReset = data.weekly_usage.reset_at;
        } else if (data.usage?.weekly) {
            weeklyPercent = data.usage.weekly.percent_used || 0;
            weeklyReset = data.usage.weekly.reset_at;
        }

        const primary: RateWindow = {
            usedPercent: sessionPercent,
            resetsAt: sessionReset,
            resetDescription: 'Session',
        };

        const secondary: RateWindow | undefined = weeklyPercent !== undefined ? {
            usedPercent: weeklyPercent,
            resetsAt: weeklyReset,
            resetDescription: 'Weekly',
        } : undefined;

        return {
            providerId: this.id,
            displayName: this.displayName,
            primary,
            secondary,
            accountEmail: data.user?.email,
            accountPlan: data.plan || data.organization?.name || 'Claude',
            version: source,
            dashboardUrl: 'https://console.anthropic.com/settings/usage',
            statusPageUrl: 'https://status.anthropic.com',
            updatedAt: new Date().toISOString(),
        };
    }
}
