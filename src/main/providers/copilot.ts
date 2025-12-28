/**
 * GitHub Copilot Provider - Browser-based login flow
 * Uses GitHub OAuth Device Flow for authentication
 * API: https://api.github.com/copilot_internal/user
 */

import * as fs from 'fs';
import * as path from 'path';
import axios from 'axios';
import { Provider, ProviderUsage, RateWindow } from './index';
import { app, BrowserWindow, session, shell } from 'electron';
import { exec } from 'child_process';
import { promisify } from 'util';

const execAsync = promisify(exec);

// GitHub OAuth Client ID (VS Code's public client ID)
const GITHUB_CLIENT_ID = 'Iv1.b507a08c87ecfe98';

interface CopilotUsageResponse {
    chat_enabled?: boolean;
    copilot_plan?: string;
    access_type_sku?: string;
    quota_snapshots?: {
        chat?: {
            percent_remaining?: number;
            resets_at?: string;
        };
        premiumInteractions?: {
            percent_remaining?: number;
            resets_at?: string;
        };
    };
    copilot_ide_code_completions?: string;
    limited_user_quotas?: {
        chat?: number;
        completions?: number;
    };
    monthly_quotas?: {
        chat?: number;
        completions?: number;
    };
    limited_user_reset_date?: string;
}

interface StoredToken {
    token: string;
    savedAt: string;
    username?: string;
}

export class CopilotProvider implements Provider {
    id = 'copilot';
    displayName = 'GitHub Copilot';
    private timeout = 15000;
    private tokenFilePath: string;
    private loginWindow: BrowserWindow | null = null;

    constructor() {
        const appDataPath = app.getPath('userData');
        this.tokenFilePath = path.join(appDataPath, 'copilot-token.json');
    }

    async fetch(): Promise<ProviderUsage> {
        try {
            console.log('[Copilot] Starting fetch...');

            // Try to get token from various sources
            const token = await this.getToken();

            if (!token) {
                console.log('[Copilot] No token found - needs login');
                return {
                    providerId: this.id,
                    displayName: this.displayName,
                    error: 'Click "Sign in to Copilot" to connect your GitHub account',
                    needsLogin: true,
                    updatedAt: new Date().toISOString(),
                };
            }

            console.log('[Copilot] Got token, fetching usage...');
            return await this.fetchUsage(token);
        } catch (error) {
            console.error('[Copilot] Fetch error:', error);
            return {
                providerId: this.id,
                displayName: this.displayName,
                error: error instanceof Error ? error.message : 'Failed to fetch Copilot usage',
                updatedAt: new Date().toISOString(),
            };
        }
    }

    async isAvailable(): Promise<boolean> {
        const token = await this.getToken();
        return !!token;
    }

    /**
     * Get token from stored session, gh CLI, or environment
     */
    private async getToken(): Promise<string | null> {
        // Check stored token first
        const storedToken = this.loadStoredToken();
        if (storedToken?.token) {
            return storedToken.token;
        }

        // Check environment variable
        if (process.env.GITHUB_TOKEN) {
            return process.env.GITHUB_TOKEN;
        }

        // Try GitHub CLI
        try {
            const { stdout } = await execAsync('gh auth token', { timeout: 5000 });
            const token = stdout.trim();
            if (token) {
                // Save for future use
                this.saveToken(token);
                return token;
            }
        } catch {
            // gh CLI not available or not logged in
        }

        return null;
    }

    /**
     * Open a login window for GitHub OAuth Device Flow
     */
    async openLoginWindow(): Promise<boolean> {
        return new Promise(async (resolve) => {
            console.log('[Copilot] Starting GitHub Device Flow...');

            try {
                // Request device code
                const deviceCodeResponse = await axios.post(
                    'https://github.com/login/device/code',
                    new URLSearchParams({
                        client_id: GITHUB_CLIENT_ID,
                        scope: 'read:user',
                    }).toString(),
                    {
                        headers: {
                            'Accept': 'application/json',
                            'Content-Type': 'application/x-www-form-urlencoded',
                        },
                    }
                );

                const { device_code, user_code, verification_uri, expires_in, interval } = deviceCodeResponse.data;

                console.log('[Copilot] Device code obtained, user_code:', user_code);

                // Open browser for user to authorize
                if (this.loginWindow && !this.loginWindow.isDestroyed()) {
                    this.loginWindow.close();
                }

                this.loginWindow = new BrowserWindow({
                    width: 500,
                    height: 400,
                    title: 'Sign in to GitHub Copilot',
                    webPreferences: {
                        nodeIntegration: false,
                        contextIsolation: true,
                    },
                    autoHideMenuBar: true,
                    resizable: false,
                });

                // Show instructions
                const html = `
                    <!DOCTYPE html>
                    <html>
                    <head>
                        <style>
                            body {
                                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                                background: #0d1117;
                                color: #e6edf3;
                                display: flex;
                                flex-direction: column;
                                align-items: center;
                                justify-content: center;
                                height: 100vh;
                                margin: 0;
                                padding: 20px;
                                box-sizing: border-box;
                            }
                            h2 { margin-bottom: 10px; }
                            .code {
                                font-family: monospace;
                                font-size: 32px;
                                font-weight: bold;
                                background: #21262d;
                                padding: 16px 32px;
                                border-radius: 8px;
                                margin: 20px 0;
                                letter-spacing: 4px;
                                color: #58a6ff;
                            }
                            p { color: #8b949e; text-align: center; }
                            .btn {
                                background: #238636;
                                color: white;
                                border: none;
                                padding: 12px 24px;
                                border-radius: 6px;
                                font-size: 16px;
                                cursor: pointer;
                                margin-top: 20px;
                            }
                            .btn:hover { background: #2ea043; }
                            .status { margin-top: 20px; color: #8b949e; }
                        </style>
                    </head>
                    <body>
                        <h2>🐙 GitHub Device Authorization</h2>
                        <p>Enter this code on github.com:</p>
                        <div class="code">${user_code}</div>
                        <button class="btn" onclick="window.open('${verification_uri}')">Open GitHub</button>
                        <p class="status">Waiting for authorization...</p>
                    </body>
                    </html>
                `;

                this.loginWindow.loadURL(`data:text/html;charset=utf-8,${encodeURIComponent(html)}`);

                // Poll for token
                const pollInterval = (interval || 5) * 1000;
                const maxAttempts = Math.floor((expires_in || 900) * 1000 / pollInterval);
                let attempts = 0;

                const poll = async () => {
                    if (this.loginWindow?.isDestroyed()) {
                        resolve(false);
                        return;
                    }

                    attempts++;
                    if (attempts > maxAttempts) {
                        console.log('[Copilot] Device flow expired');
                        this.loginWindow?.close();
                        resolve(false);
                        return;
                    }

                    try {
                        const tokenResponse = await axios.post(
                            'https://github.com/login/oauth/access_token',
                            new URLSearchParams({
                                client_id: GITHUB_CLIENT_ID,
                                device_code,
                                grant_type: 'urn:ietf:params:oauth:grant-type:device_code',
                            }).toString(),
                            {
                                headers: {
                                    'Accept': 'application/json',
                                    'Content-Type': 'application/x-www-form-urlencoded',
                                },
                            }
                        );

                        const data = tokenResponse.data;

                        if (data.error === 'authorization_pending') {
                            setTimeout(poll, pollInterval);
                            return;
                        }

                        if (data.error === 'slow_down') {
                            setTimeout(poll, pollInterval + 5000);
                            return;
                        }

                        if (data.error) {
                            console.log('[Copilot] Device flow error:', data.error);
                            this.loginWindow?.close();
                            resolve(false);
                            return;
                        }

                        if (data.access_token) {
                            console.log('[Copilot] Token obtained!');
                            this.saveToken(data.access_token);
                            this.loginWindow?.close();
                            resolve(true);
                            return;
                        }
                    } catch (error) {
                        console.error('[Copilot] Poll error:', error);
                    }

                    setTimeout(poll, pollInterval);
                };

                setTimeout(poll, pollInterval);

                this.loginWindow.on('closed', () => {
                    this.loginWindow = null;
                });

            } catch (error) {
                console.error('[Copilot] Device flow error:', error);
                resolve(false);
            }
        });
    }

    private saveToken(token: string, username?: string): void {
        try {
            const data: StoredToken = {
                token,
                savedAt: new Date().toISOString(),
                username,
            };
            fs.writeFileSync(this.tokenFilePath, JSON.stringify(data, null, 2));
            console.log('[Copilot] Token saved');
        } catch (error) {
            console.error('[Copilot] Failed to save token:', error);
        }
    }

    private loadStoredToken(): StoredToken | null {
        try {
            if (fs.existsSync(this.tokenFilePath)) {
                const data = fs.readFileSync(this.tokenFilePath, 'utf-8');
                return JSON.parse(data);
            }
        } catch (error) {
            console.error('[Copilot] Failed to load token:', error);
        }
        return null;
    }

    clearStoredSession(): void {
        try {
            if (fs.existsSync(this.tokenFilePath)) {
                fs.unlinkSync(this.tokenFilePath);
                console.log('[Copilot] Token cleared');
            }
        } catch (error) {
            console.error('[Copilot] Failed to clear token:', error);
        }
    }

    hasStoredSession(): boolean {
        const token = this.loadStoredToken();
        return !!token?.token;
    }

    private async fetchUsage(token: string): Promise<ProviderUsage> {
        try {
            const response = await axios.get<CopilotUsageResponse>(
                'https://api.github.com/copilot_internal/user',
                {
                    headers: {
                        'Authorization': `token ${token}`,
                        'Accept': 'application/json',
                        'Editor-Version': 'vscode/1.96.2',
                        'Editor-Plugin-Version': 'copilot-chat/0.26.7',
                        'User-Agent': 'GitHubCopilotChat/0.26.7',
                        'X-Github-Api-Version': '2025-04-01',
                    },
                    timeout: this.timeout,
                    validateStatus: (status) => status < 500,
                }
            );

            console.log('[Copilot] Response status:', response.status);

            if (response.status === 401 || response.status === 403) {
                this.clearStoredSession();
                return {
                    providerId: this.id,
                    displayName: this.displayName,
                    error: 'Token expired. Click "Sign in to Copilot" to reconnect.',
                    needsLogin: true,
                    updatedAt: new Date().toISOString(),
                };
            }

            if (response.status === 404) {
                // Clear stored token since it's not working for Copilot
                this.clearStoredSession();
                return {
                    providerId: this.id,
                    displayName: this.displayName,
                    error: 'Copilot not enabled. Sign in with a Copilot-enabled account.',
                    needsLogin: true,
                    updatedAt: new Date().toISOString(),
                };
            }

            const data = response.data;
            console.log('[Copilot] Usage data:', JSON.stringify(data, null, 2));

            // Parse quota snapshots
            let primary: RateWindow | undefined;
            let secondary: RateWindow | undefined;

            if (data.quota_snapshots?.premiumInteractions) {
                const snap = data.quota_snapshots.premiumInteractions;
                primary = {
                    usedPercent: Math.max(0, 100 - (snap.percent_remaining || 0)),
                    resetsAt: snap.resets_at,
                    resetDescription: 'Premium',
                };
            }

            if (data.quota_snapshots?.chat) {
                const snap = data.quota_snapshots.chat;
                secondary = {
                    usedPercent: Math.max(0, 100 - (snap.percent_remaining || 0)),
                    resetsAt: snap.resets_at,
                    resetDescription: 'Chat',
                };
            }

            // Handle Free Copilot accounts with monthly_quotas
            if (!primary && data.monthly_quotas) {
                // Free accounts have quotas but usage isn't tracked in this response
                // Show the plan info with 0% used (can't determine actual usage from this API)
                const chatQuota = data.monthly_quotas.chat || 0;
                const completionsQuota = data.monthly_quotas.completions || 0;

                primary = {
                    usedPercent: 0, // Free tier doesn't expose usage percentage
                    resetsAt: data.limited_user_reset_date,
                    resetDescription: `${completionsQuota} completions/mo`,
                };

                if (chatQuota > 0) {
                    secondary = {
                        usedPercent: 0,
                        resetsAt: data.limited_user_reset_date,
                        resetDescription: `${chatQuota} chats/mo`,
                    };
                }
            }

            // If still no quota data, show connected status
            if (!primary) {
                primary = {
                    usedPercent: 0,
                    resetDescription: 'Connected',
                };
            }

            // Determine plan name
            let planName = 'Copilot';
            if (data.access_type_sku === 'free_limited_copilot') {
                planName = 'Copilot Free';
            } else if (data.copilot_plan) {
                planName = data.copilot_plan.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
            }

            return {
                providerId: this.id,
                displayName: this.displayName,
                primary,
                secondary,
                accountPlan: planName,
                version: 'api',
                dashboardUrl: 'https://github.com/settings/copilot',
                statusPageUrl: 'https://www.githubstatus.com',
                updatedAt: new Date().toISOString(),
            };
        } catch (error) {
            console.error('[Copilot] Usage fetch error:', error);
            throw error;
        }
    }
}
