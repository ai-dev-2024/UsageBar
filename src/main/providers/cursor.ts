/**
 * Cursor Provider - Implementation based on CodexBar
 * Uses browser login flow to capture session cookies and fetch usage from cursor.com API
 * 
 * API Endpoints:
 * - https://cursor.com/api/usage-summary - Usage data
 * - https://cursor.com/api/auth/me - User info
 */

import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
import axios from 'axios';
import { Provider, ProviderUsage, RateWindow } from './index';
import { app, BrowserWindow, session } from 'electron';

// Cookie names used by Cursor for authentication
const SESSION_COOKIE_NAMES = [
    'WorkosCursorSessionToken',
    '__Secure-next-auth.session-token',
    'next-auth.session-token',
];

// Cursor API response types (based on CodexBar's CursorUsageSummary)
interface CursorUsageSummary {
    billingCycleStart?: string;
    billingCycleEnd?: string;
    membershipType?: string;
    limitType?: string;
    isUnlimited?: boolean;
    autoModelSelectedDisplayMessage?: string;
    namedModelSelectedDisplayMessage?: string;
    individualUsage?: {
        plan?: {
            enabled?: boolean;
            used?: number;  // Usage in cents
            limit?: number; // Limit in cents
            remaining?: number;
            totalPercentUsed?: number;
            breakdown?: {
                included?: number;
                bonus?: number;
                total?: number;
            };
        };
        onDemand?: {
            enabled?: boolean;
            used?: number;
            limit?: number;
            remaining?: number;
        };
    };
    teamUsage?: {
        onDemand?: {
            enabled?: boolean;
            used?: number;
            limit?: number;
            remaining?: number;
        };
    };
}

interface CursorUserInfo {
    email?: string;
    emailVerified?: boolean;
    name?: string;
    sub?: string;
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
}

export class CursorProvider implements Provider {
    id = 'cursor';
    displayName = 'Cursor';
    private timeout = 15000;
    private baseURL = 'https://cursor.com';
    private sessionFilePath: string;
    private loginWindow: BrowserWindow | null = null;

    constructor() {
        // Store session in app data directory
        const appDataPath = app.getPath('userData');
        this.sessionFilePath = path.join(appDataPath, 'cursor-session.json');
    }

    async fetch(): Promise<ProviderUsage> {
        try {
            console.log('[Cursor] Starting fetch...');

            // Try to get stored session cookies
            const cookieHeader = await this.getCookieHeader();

            if (!cookieHeader) {
                console.log('[Cursor] No session cookies found - needs login');
                return {
                    providerId: this.id,
                    displayName: this.displayName,
                    error: 'Click "Sign in to Cursor" to connect your account',
                    needsLogin: true,
                    updatedAt: new Date().toISOString(),
                };
            }

            console.log('[Cursor] Got cookie header, fetching usage...');

            // Fetch usage and user info
            const [usageSummary, userInfo] = await Promise.all([
                this.fetchUsageSummary(cookieHeader),
                this.fetchUserInfo(cookieHeader).catch(() => null),
            ]);

            if (!usageSummary) {
                // Session expired - clear stored cookies
                this.clearStoredSession();
                return {
                    providerId: this.id,
                    displayName: this.displayName,
                    error: 'Session expired. Click "Sign in to Cursor" to reconnect.',
                    needsLogin: true,
                    updatedAt: new Date().toISOString(),
                };
            }

            return this.parseUsageSummary(usageSummary, userInfo);
        } catch (error) {
            console.error('[Cursor] Fetch error:', error);
            return {
                providerId: this.id,
                displayName: this.displayName,
                error: error instanceof Error ? error.message : 'Failed to fetch Cursor usage',
                updatedAt: new Date().toISOString(),
            };
        }
    }

    async isAvailable(): Promise<boolean> {
        const cookieHeader = await this.getCookieHeader();
        return !!cookieHeader;
    }

    /**
     * Open a login window for the user to sign in to Cursor
     * Returns true if login was successful
     */
    async openLoginWindow(): Promise<boolean> {
        return new Promise((resolve) => {
            console.log('[Cursor] Opening login window...');

            // Close existing window if any
            if (this.loginWindow && !this.loginWindow.isDestroyed()) {
                this.loginWindow.close();
            }

            // Create a new browser window for login
            this.loginWindow = new BrowserWindow({
                width: 800,
                height: 700,
                title: 'Sign in to Cursor',
                webPreferences: {
                    nodeIntegration: false,
                    contextIsolation: true,
                    // Use a separate session to capture cookies cleanly
                    partition: 'persist:cursor-login',
                },
                autoHideMenuBar: true,
            });

            const loginSession = session.fromPartition('persist:cursor-login');

            // Load the Cursor settings page (requires login)
            this.loginWindow.loadURL('https://cursor.com/settings');

            // Check for successful login by monitoring cookies
            const checkForSession = async () => {
                try {
                    const cookies = await loginSession.cookies.get({ domain: 'cursor.com' });
                    const sessionCookie = cookies.find(c => SESSION_COOKIE_NAMES.includes(c.name));

                    if (sessionCookie) {
                        console.log('[Cursor] Session cookie found!');

                        // Save all relevant cookies
                        await this.saveSessionCookies(cookies);

                        // Close the login window
                        if (this.loginWindow && !this.loginWindow.isDestroyed()) {
                            this.loginWindow.close();
                        }

                        resolve(true);
                        return true;
                    }
                } catch (error) {
                    console.error('[Cursor] Error checking cookies:', error);
                }
                return false;
            };

            // Check periodically for login completion
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

            // Clean up on window close
            this.loginWindow.on('closed', () => {
                clearInterval(interval);
                this.loginWindow = null;
            });

            // Also check when navigation completes
            this.loginWindow.webContents.on('did-navigate', async () => {
                await checkForSession();
            });

            this.loginWindow.webContents.on('did-navigate-in-page', async () => {
                await checkForSession();
            });
        });
    }

    /**
     * Save session cookies to file
     */
    private async saveSessionCookies(cookies: Electron.Cookie[]): Promise<void> {
        try {
            const relevantCookies = cookies.filter(c =>
                c.domain?.includes('cursor.com') || c.domain?.includes('cursor.sh')
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
            };

            fs.writeFileSync(this.sessionFilePath, JSON.stringify(sessionData, null, 2));
            console.log('[Cursor] Session saved with', relevantCookies.length, 'cookies');
        } catch (error) {
            console.error('[Cursor] Failed to save session:', error);
        }
    }

    /**
     * Load stored session cookies
     */
    private loadStoredSession(): StoredSession | null {
        try {
            if (fs.existsSync(this.sessionFilePath)) {
                const data = fs.readFileSync(this.sessionFilePath, 'utf-8');
                return JSON.parse(data);
            }
        } catch (error) {
            console.error('[Cursor] Failed to load session:', error);
        }
        return null;
    }

    /**
     * Clear stored session
     */
    clearStoredSession(): void {
        try {
            if (fs.existsSync(this.sessionFilePath)) {
                fs.unlinkSync(this.sessionFilePath);
                console.log('[Cursor] Session cleared');
            }
        } catch (error) {
            console.error('[Cursor] Failed to clear session:', error);
        }
    }

    /**
     * Check if user has a stored session
     */
    hasStoredSession(): boolean {
        const session = this.loadStoredSession();
        if (!session) return false;

        // Check if any session cookie exists
        return session.cookies.some(c => SESSION_COOKIE_NAMES.includes(c.name));
    }

    /**
     * Get cookie header from stored session
     */
    private async getCookieHeader(): Promise<string | null> {
        const storedSession = this.loadStoredSession();
        if (!storedSession || storedSession.cookies.length === 0) {
            return null;
        }

        // Check if session has expired (cookies have expiration dates)
        const now = Date.now() / 1000;
        const validCookies = storedSession.cookies.filter(c => {
            if (!c.expirationDate) return true; // Session cookies
            return c.expirationDate > now;
        });

        if (validCookies.length === 0) {
            console.log('[Cursor] All cookies expired');
            this.clearStoredSession();
            return null;
        }

        // Build cookie header
        const cookieHeader = validCookies
            .map(c => `${c.name}=${c.value}`)
            .join('; ');

        console.log('[Cursor] Cookie header built with', validCookies.length, 'cookies');
        return cookieHeader;
    }

    /**
     * Fetch usage summary from Cursor API
     */
    private async fetchUsageSummary(cookieHeader: string): Promise<CursorUsageSummary | null> {
        try {
            console.log('[Cursor] Fetching usage summary...');
            const response = await axios.get<CursorUsageSummary>(
                `${this.baseURL}/api/usage-summary`,
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

            console.log('[Cursor] Usage summary response:', response.status);

            if (response.status === 401 || response.status === 403) {
                console.log('[Cursor] Not authenticated');
                return null;
            }

            if (response.status !== 200) {
                console.log('[Cursor] Unexpected status:', response.status);
                return null;
            }

            console.log('[Cursor] Usage data:', JSON.stringify(response.data, null, 2));
            return response.data;
        } catch (error: unknown) {
            console.error('[Cursor] Usage fetch error:', error);
            const axiosError = error as { response?: { status?: number } };
            if (axiosError.response?.status === 401 || axiosError.response?.status === 403) {
                return null;
            }
            throw error;
        }
    }

    /**
     * Fetch user info from Cursor API
     */
    private async fetchUserInfo(cookieHeader: string): Promise<CursorUserInfo | null> {
        try {
            const response = await axios.get<CursorUserInfo>(
                `${this.baseURL}/api/auth/me`,
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

            if (response.status === 200) {
                return response.data;
            }
            return null;
        } catch {
            return null;
        }
    }

    /**
     * Parse usage summary into ProviderUsage format
     */
    private parseUsageSummary(summary: CursorUsageSummary, userInfo: CursorUserInfo | null): ProviderUsage {
        // Parse billing cycle end date
        let billingCycleEnd: string | undefined;
        if (summary.billingCycleEnd) {
            billingCycleEnd = summary.billingCycleEnd;
        }

        // Calculate plan usage percentage
        const planUsedCents = summary.individualUsage?.plan?.used ?? 0;
        const planLimitCents = summary.individualUsage?.plan?.limit ?? 0;

        let planPercentUsed = 0;
        if (planLimitCents > 0) {
            planPercentUsed = (planUsedCents / planLimitCents) * 100;
        } else if (summary.individualUsage?.plan?.totalPercentUsed !== undefined) {
            const percent = summary.individualUsage.plan.totalPercentUsed;
            planPercentUsed = percent <= 1 ? percent * 100 : percent;
        }

        // For free/hobby plans, also check the display messages
        if (planPercentUsed === 0 && summary.autoModelSelectedDisplayMessage) {
            // Try to parse from display message like "50 requests remaining"
            const match = summary.autoModelSelectedDisplayMessage.match(/(\d+)\s*requests?\s*remaining/i);
            if (match) {
                // Assume 50 requests for hobby plan
                const remaining = parseInt(match[1], 10);
                const total = 50; // Hobby plan limit
                planPercentUsed = ((total - remaining) / total) * 100;
            }
        }

        // Format plan as "Pro", "Hobby", etc.
        const formatMembershipType = (type?: string): string => {
            if (!type) return 'Cursor';
            switch (type.toLowerCase()) {
                case 'enterprise': return 'Enterprise';
                case 'pro': return 'Pro';
                case 'hobby': return 'Hobby (Free)';
                case 'free': return 'Hobby (Free)';
                case 'team': return 'Team';
                default: return type.charAt(0).toUpperCase() + type.slice(1);
            }
        };

        const primary: RateWindow = {
            usedPercent: planPercentUsed,
            resetsAt: billingCycleEnd,
            resetDescription: summary.membershipType === 'hobby' ? 'Monthly Requests' : 'Plan Usage',
        };

        // On-demand usage as secondary (if applicable)
        let secondary: RateWindow | undefined;
        const onDemandUsedCents = summary.individualUsage?.onDemand?.used ?? 0;
        const onDemandLimitCents = summary.individualUsage?.onDemand?.limit;

        if (onDemandLimitCents && onDemandLimitCents > 0) {
            secondary = {
                usedPercent: (onDemandUsedCents / onDemandLimitCents) * 100,
                resetsAt: billingCycleEnd,
                resetDescription: 'On-Demand',
            };
        }

        console.log('[Cursor] Parsed usage:', {
            planPercentUsed,
            planUsedCents,
            planLimitCents,
            membershipType: summary.membershipType
        });

        return {
            providerId: this.id,
            displayName: this.displayName,
            primary,
            secondary,
            accountEmail: userInfo?.email,
            accountPlan: formatMembershipType(summary.membershipType),
            dashboardUrl: 'https://cursor.com/settings',
            statusPageUrl: 'https://status.cursor.com',
            version: 'api',
            updatedAt: new Date().toISOString(),
        };
    }
}
