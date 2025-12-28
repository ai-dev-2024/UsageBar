/**
 * GitHub Copilot Provider - Full implementation
 * Uses GitHub device flow and Copilot usage API
 */

import { exec } from 'child_process';
import { promisify } from 'util';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
import axios from 'axios';
import { Provider, ProviderUsage, RateWindow } from './index';

const execAsync = promisify(exec);

interface CopilotConfig {
    oauth_token?: string;
    user?: string;
}

interface CopilotUsageResponse {
    usage?: {
        current_period?: {
            used?: number;
            limit?: number;
            remaining?: number;
            resets_at?: string;
        };
        monthly?: {
            used?: number;
            limit?: number;
            resets_at?: string;
        };
    };
    user?: {
        login?: string;
        plan?: string;
    };
}

export class CopilotProvider implements Provider {
    id = 'copilot';
    displayName = 'GitHub Copilot';
    private timeout = 10000;

    async fetch(): Promise<ProviderUsage> {
        try {
            // Try to get token from environment or config
            const token = await this.getToken();

            if (!token) {
                throw new Error('Copilot token not found. Set COPILOT_API_TOKEN or login via GitHub CLI.');
            }

            return await this.fetchUsage(token);
        } catch (error) {
            throw new Error(
                error instanceof Error ? error.message : 'Failed to fetch Copilot usage'
            );
        }
    }

    async isAvailable(): Promise<boolean> {
        try {
            const token = await this.getToken();
            return !!token;
        } catch {
            return false;
        }
    }

    private async getToken(): Promise<string | null> {
        // Check environment variable first
        if (process.env.COPILOT_API_TOKEN) {
            return process.env.COPILOT_API_TOKEN;
        }

        // Try GitHub CLI
        try {
            const { stdout } = await execAsync('gh auth token', {
                timeout: this.timeout,
            });
            if (stdout.trim()) {
                return stdout.trim();
            }
        } catch {
            // gh CLI not available or not logged in
        }

        // Try reading from GitHub Copilot config
        const configPaths = [
            // Windows
            path.join(process.env.APPDATA || '', 'GitHub Copilot', 'hosts.json'),
            path.join(process.env.LOCALAPPDATA || '', 'github-copilot', 'hosts.json'),
            // macOS/Linux
            path.join(os.homedir(), '.config', 'github-copilot', 'hosts.json'),
        ];

        for (const configPath of configPaths) {
            try {
                if (fs.existsSync(configPath)) {
                    const content = fs.readFileSync(configPath, 'utf-8');
                    const config: Record<string, CopilotConfig> = JSON.parse(content);

                    // Find GitHub.com entry
                    for (const [host, data] of Object.entries(config)) {
                        if (host.includes('github.com') && data.oauth_token) {
                            return data.oauth_token;
                        }
                    }
                }
            } catch {
                // Continue to next path
            }
        }

        return null;
    }

    private async fetchUsage(token: string): Promise<ProviderUsage> {
        try {
            // Query GitHub Copilot usage API
            const response = await axios.get<CopilotUsageResponse>(
                'https://api.github.com/copilot/usage',
                {
                    headers: {
                        'Authorization': `Bearer ${token}`,
                        'Accept': 'application/vnd.github+json',
                        'X-GitHub-Api-Version': '2022-11-28',
                    },
                    timeout: this.timeout,
                }
            );

            const data = response.data;

            const primary: RateWindow | undefined = data.usage?.current_period ? {
                usedPercent: data.usage.current_period.limit
                    ? (data.usage.current_period.used || 0) / data.usage.current_period.limit * 100
                    : 0,
                resetsAt: data.usage.current_period.resets_at,
                resetDescription: 'Current Period',
            } : undefined;

            const secondary: RateWindow | undefined = data.usage?.monthly ? {
                usedPercent: data.usage.monthly.limit
                    ? (data.usage.monthly.used || 0) / data.usage.monthly.limit * 100
                    : 0,
                resetsAt: data.usage.monthly.resets_at,
                resetDescription: 'Monthly',
            } : undefined;

            return {
                providerId: this.id,
                displayName: this.displayName,
                primary,
                secondary,
                accountEmail: data.user?.login,
                accountPlan: data.user?.plan || 'Copilot',
                version: 'api',
                updatedAt: new Date().toISOString(),
            };
        } catch (error) {
            // API might not be available for all users
            if (axios.isAxiosError(error) && error.response?.status === 404) {
                return {
                    providerId: this.id,
                    displayName: this.displayName,
                    version: 'api',
                    error: 'Copilot usage API not available for your account.',
                    updatedAt: new Date().toISOString(),
                };
            }

            throw error;
        }
    }
}
