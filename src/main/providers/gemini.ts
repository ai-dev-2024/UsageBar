/**
 * Gemini Provider - Full implementation
 * Uses Gemini CLI OAuth credentials for quota API
 */

import { exec } from 'child_process';
import { promisify } from 'util';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
import axios from 'axios';
import { Provider, ProviderUsage, RateWindow } from './index';

const execAsync = promisify(exec);

interface GeminiCredentials {
    access_token?: string;
    refresh_token?: string;
    token_expiry?: string;
}

interface GeminiQuotaResponse {
    quotas?: Array<{
        metric?: string;
        limit?: number;
        usage?: number;
        reset_time?: string;
    }>;
    user?: {
        email?: string;
    };
}

export class GeminiProvider implements Provider {
    id = 'gemini';
    displayName = 'Gemini';
    private timeout = 10000;

    async fetch(): Promise<ProviderUsage> {
        try {
            // Detect Gemini CLI version
            const version = await this.detectVersion();

            // Try to get OAuth credentials
            const credentials = await this.readCredentials();

            if (credentials?.access_token) {
                return await this.fetchWithOAuth(credentials.access_token, version);
            }

            // Fallback to CLI-based fetch
            return await this.fetchWithCLI(version);
        } catch (error) {
            throw new Error(
                error instanceof Error ? error.message : 'Failed to fetch Gemini usage'
            );
        }
    }

    async isAvailable(): Promise<boolean> {
        try {
            await this.detectVersion();
            return true;
        } catch {
            return false;
        }
    }

    private async detectVersion(): Promise<string> {
        try {
            const { stdout } = await execAsync('gemini --version', {
                timeout: this.timeout,
            });
            const match = stdout.match(/(\d+\.\d+\.\d+)/);
            return match ? match[1] : 'unknown';
        } catch {
            throw new Error('Gemini CLI not found. Install it from Google.');
        }
    }

    private async readCredentials(): Promise<GeminiCredentials | null> {
        // Gemini CLI credential locations
        const credentialPaths = [
            // Windows
            path.join(process.env.APPDATA || '', 'gemini', 'credentials.json'),
            path.join(process.env.LOCALAPPDATA || '', 'gemini', 'credentials.json'),
            // macOS/Linux
            path.join(os.homedir(), '.config', 'gemini', 'credentials.json'),
            path.join(os.homedir(), '.gemini', 'credentials.json'),
        ];

        for (const credPath of credentialPaths) {
            try {
                if (fs.existsSync(credPath)) {
                    const content = fs.readFileSync(credPath, 'utf-8');
                    return JSON.parse(content);
                }
            } catch {
                // Continue to next path
            }
        }

        return null;
    }

    private async fetchWithOAuth(accessToken: string, version: string): Promise<ProviderUsage> {
        try {
            const response = await axios.get<GeminiQuotaResponse>(
                'https://generativelanguage.googleapis.com/v1/quota',
                {
                    headers: {
                        'Authorization': `Bearer ${accessToken}`,
                        'Content-Type': 'application/json',
                    },
                    timeout: this.timeout,
                }
            );

            const data = response.data;

            // Find relevant quotas
            const requestsQuota = data.quotas?.find(q => q.metric?.includes('requests'));
            const tokensQuota = data.quotas?.find(q => q.metric?.includes('tokens'));

            const primary: RateWindow | undefined = requestsQuota ? {
                usedPercent: requestsQuota.limit
                    ? (requestsQuota.usage || 0) / requestsQuota.limit * 100
                    : 0,
                resetsAt: requestsQuota.reset_time,
                resetDescription: 'Requests',
            } : undefined;

            const secondary: RateWindow | undefined = tokensQuota ? {
                usedPercent: tokensQuota.limit
                    ? (tokensQuota.usage || 0) / tokensQuota.limit * 100
                    : 0,
                resetsAt: tokensQuota.reset_time,
                resetDescription: 'Tokens',
            } : undefined;

            return {
                providerId: this.id,
                displayName: this.displayName,
                primary,
                secondary,
                accountEmail: data.user?.email,
                version,
                updatedAt: new Date().toISOString(),
            };
        } catch {
            // OAuth failed, try CLI
            return this.fetchWithCLI(version);
        }
    }

    private async fetchWithCLI(version: string): Promise<ProviderUsage> {
        try {
            const { stdout } = await execAsync('gemini quota --json', {
                timeout: this.timeout,
            });

            const data = JSON.parse(stdout);

            const primary: RateWindow | undefined = data.requests ? {
                usedPercent: data.requests.limit
                    ? (data.requests.used || 0) / data.requests.limit * 100
                    : 0,
                resetsAt: data.requests.reset_at,
                resetDescription: 'Requests',
            } : undefined;

            return {
                providerId: this.id,
                displayName: this.displayName,
                primary,
                accountEmail: data.email,
                version,
                updatedAt: new Date().toISOString(),
            };
        } catch {
            return {
                providerId: this.id,
                displayName: this.displayName,
                version,
                error: 'Could not fetch Gemini quota. Run "gemini login" to authenticate.',
                updatedAt: new Date().toISOString(),
            };
        }
    }
}
