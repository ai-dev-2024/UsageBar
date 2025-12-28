/**
 * Cursor Provider - Full implementation
 * Fetches usage from Cursor via its local API
 */

import { exec } from 'child_process';
import { promisify } from 'util';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
import axios from 'axios';
import { Provider, ProviderUsage, RateWindow } from './index';

const execAsync = promisify(exec);

interface CursorConfig {
    auth?: {
        accessToken?: string;
        email?: string;
    };
}

interface CursorUsageResponse {
    subscription?: {
        plan?: string;
        usage?: {
            requests_used?: number;
            requests_limit?: number;
            premium_requests_used?: number;
            premium_requests_limit?: number;
            billing_period_end?: string;
        };
    };
    user?: {
        email?: string;
    };
}

export class CursorProvider implements Provider {
    id = 'cursor';
    displayName = 'Cursor';
    private timeout = 10000;

    async fetch(): Promise<ProviderUsage> {
        try {
            // Try to read Cursor config
            const config = await this.readConfig();

            // Priority 1: Remote API (if token exists)
            if (config?.auth?.accessToken) {
                try {
                    return await this.fetchUsage(config.auth.accessToken, config.auth.email);
                } catch (e) {
                    console.error('[Cursor] Remote API failed, trying local:', e);
                    // Fall through to local
                }
            }

            // Priority 2: Local API
            return await this.fetchFromLocalAPI();
        } catch (error) {
            console.error('[Cursor] All fetch methods failed:', error);
            throw new Error(
                error instanceof Error ? error.message : 'Failed to fetch Cursor usage'
            );
        }
    }

    async isAvailable(): Promise<boolean> {
        try {
            const config = await this.readConfig();
            return !!config?.auth?.accessToken;
        } catch {
            return false;
        }
    }

    private async readConfig(): Promise<CursorConfig | null> {
        // Cursor config locations
        const configPaths = [
            // Windows (Roaming)
            path.join(process.env.APPDATA || '', 'Cursor', 'User', 'globalStorage', 'state.vscdb'),
            path.join(process.env.APPDATA || '', 'Cursor', 'storage.json'),
            // Windows (Local - sometimes used for specific installs)
            path.join(process.env.LOCALAPPDATA || '', 'Programs', 'Cursor', 'User', 'globalStorage', 'state.vscdb'),
            path.join(process.env.LOCALAPPDATA || '', 'Cursor', 'User', 'globalStorage', 'state.vscdb'),
            // macOS
            path.join(os.homedir(), 'Library', 'Application Support', 'Cursor', 'User', 'globalStorage', 'state.vscdb'),
            // Linux
            path.join(os.homedir(), '.config', 'Cursor', 'User', 'globalStorage', 'state.vscdb'),
        ];

        for (const configPath of configPaths) {
            try {
                if (fs.existsSync(configPath)) {
                    // Note: state.vscdb is SQLite, storage.json is JSON
                    if (configPath.endsWith('.json')) {
                        const content = fs.readFileSync(configPath, 'utf-8');
                        return JSON.parse(content);
                    }
                    // For SQLite (state.vscdb), we try to extract the token via regex from the binary content
                    try {
                        console.log(`[Cursor] Checking SQLite path: ${configPath}`);
                        const content = fs.readFileSync(configPath, 'latin1');
                        // Pattern 1: Look for cursorAuth/accessToken value structure
                        const match = content.match(/"cursorAuth\/accessToken"[\s\S]*?"value"\s*:\s*"([^"]+)"/);
                        if (match && match[1]) {
                            console.log('[Cursor] Found token via Pattern 1');
                            return { auth: { accessToken: match[1] } };
                        }

                        // Pattern 2: Look for the JWT directly (starts with eyJ)
                        const jwtMatch = content.match(/"(eyJ[a-zA-Z0-9\-_]+\.[a-zA-Z0-9\-_]+\.[a-zA-Z0-9\-_]+)"/);
                        if (jwtMatch && jwtMatch[1] && jwtMatch[1].length > 50) {
                            console.log('[Cursor] Found token via Pattern 2 (JWT scan)');
                            return { auth: { accessToken: jwtMatch[1] } };
                        }
                    } catch (e) {
                        console.error('[Cursor] Error parsing Cursor SQLite:', e);
                    }
                    console.log(`[Cursor] No token found in ${configPath}`);
                    return { auth: {} };
                }
            } catch {
                // Continue to next path
            }
        }

        return null;
    }

    private async fetchUsage(token: string, email?: string): Promise<ProviderUsage> {
        try {
            const response = await axios.get<CursorUsageResponse>(
                'https://api.cursor.sh/usage',
                {
                    headers: {
                        'Authorization': `Bearer ${token}`,
                        'Content-Type': 'application/json',
                    },
                    timeout: this.timeout,
                }
            );

            const data = response.data;
            const usage = data.subscription?.usage;

            const primary: RateWindow | undefined = usage ? {
                usedPercent: usage.requests_limit
                    ? (usage.requests_used || 0) / usage.requests_limit * 100
                    : 0,
                resetsAt: usage.billing_period_end,
                resetDescription: 'Requests',
            } : undefined;

            const secondary: RateWindow | undefined = usage?.premium_requests_limit ? {
                usedPercent: (usage.premium_requests_used || 0) / usage.premium_requests_limit * 100,
                resetsAt: usage.billing_period_end,
                resetDescription: 'Premium',
            } : undefined;

            return {
                providerId: this.id,
                displayName: this.displayName,
                primary,
                secondary,
                accountEmail: email || data.user?.email,
                accountPlan: data.subscription?.plan,
                version: 'api',
                updatedAt: new Date().toISOString(),
            };
        } catch {
            return {
                providerId: this.id,
                displayName: this.displayName,
                error: 'Could not fetch Cursor usage. Make sure Cursor is installed and logged in.',
                updatedAt: new Date().toISOString(),
            };
        }
    }

    private async fetchFromLocalAPI(): Promise<ProviderUsage> {
        // Cursor runs a local server on port 13337 when active
        try {
            const response = await axios.get<CursorUsageResponse>(
                'http://localhost:13337/usage',
                {
                    timeout: 3000,
                }
            );

            const data = response.data;
            const usage = data.subscription?.usage;

            const primary: RateWindow | undefined = usage ? {
                usedPercent: usage.requests_limit
                    ? (usage.requests_used || 0) / usage.requests_limit * 100
                    : 0,
                resetDescription: 'Requests',
            } : undefined;

            return {
                providerId: this.id,
                displayName: this.displayName,
                primary,
                accountEmail: data.user?.email,
                accountPlan: data.subscription?.plan,
                version: 'local',
                updatedAt: new Date().toISOString(),
            };
        } catch {
            throw new Error('Cursor not running or not logged in.');
        }
    }
}
