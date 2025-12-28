/**
 * z.ai Provider - Full implementation
 * Uses API token for quota and MCP windows
 */

import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
import axios from 'axios';
import { Provider, ProviderUsage, RateWindow } from './index';

interface ZaiUsageResponse {
    quota?: {
        used?: number;
        limit?: number;
        percent_used?: number;
        reset_at?: string;
    };
    mcp?: {
        windows?: Array<{
            name?: string;
            used?: number;
            limit?: number;
            reset_at?: string;
        }>;
    };
    user?: {
        email?: string;
        plan?: string;
    };
}

export class ZaiProvider implements Provider {
    id = 'zai';
    displayName = 'z.ai';
    private timeout = 10000;

    async fetch(): Promise<ProviderUsage> {
        try {
            const token = await this.getToken();

            if (!token) {
                return {
                    providerId: this.id,
                    displayName: this.displayName,
                    error: 'Set ZAI_API_TOKEN or configure in settings',
                    needsLogin: true,
                    updatedAt: new Date().toISOString(),
                };
            }

            return await this.fetchUsage(token);
        } catch (error) {
            return {
                providerId: this.id,
                displayName: this.displayName,
                error: error instanceof Error ? error.message : 'Failed to fetch z.ai usage',
                needsLogin: true,
                updatedAt: new Date().toISOString(),
            };
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
        if (process.env.ZAI_API_TOKEN) {
            return process.env.ZAI_API_TOKEN;
        }

        // Try reading from config file
        const configPaths = [
            // Windows
            path.join(process.env.APPDATA || '', 'zai', 'config.json'),
            // macOS
            path.join(os.homedir(), 'Library', 'Application Support', 'zai', 'config.json'),
            // Linux
            path.join(os.homedir(), '.config', 'zai', 'config.json'),
            path.join(os.homedir(), '.zai', 'config.json'),
        ];

        for (const configPath of configPaths) {
            try {
                if (fs.existsSync(configPath)) {
                    const content = fs.readFileSync(configPath, 'utf-8');
                    const config = JSON.parse(content);
                    if (config.api_token || config.apiToken || config.token) {
                        return config.api_token || config.apiToken || config.token;
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
            const response = await axios.get<ZaiUsageResponse>(
                'https://api.z.ai/v1/usage',
                {
                    headers: {
                        'Authorization': `Bearer ${token}`,
                        'Content-Type': 'application/json',
                    },
                    timeout: this.timeout,
                }
            );

            const data = response.data;
            const quota = data.quota;

            const primary: RateWindow | undefined = quota ? {
                usedPercent: quota.percent_used || (quota.limit ? (quota.used || 0) / quota.limit * 100 : 0),
                resetsAt: quota.reset_at,
                resetDescription: 'Quota',
            } : undefined;

            // MCP window as secondary if available
            const mcpWindow = data.mcp?.windows?.[0];
            const secondary: RateWindow | undefined = mcpWindow ? {
                usedPercent: mcpWindow.limit ? (mcpWindow.used || 0) / mcpWindow.limit * 100 : 0,
                resetsAt: mcpWindow.reset_at,
                resetDescription: mcpWindow.name || 'MCP',
            } : undefined;

            return {
                providerId: this.id,
                displayName: this.displayName,
                primary,
                secondary,
                accountEmail: data.user?.email,
                accountPlan: data.user?.plan,
                version: 'api',
                updatedAt: new Date().toISOString(),
            };
        } catch (error) {
            if (axios.isAxiosError(error) && error.response?.status === 401) {
                return {
                    providerId: this.id,
                    displayName: this.displayName,
                    error: 'z.ai token invalid or expired.',
                    updatedAt: new Date().toISOString(),
                };
            }

            throw error;
        }
    }
}
