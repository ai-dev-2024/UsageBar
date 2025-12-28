/**
 * Claude Code Provider - Full implementation
 * Detects Claude CLI and fetches usage stats
 */

import { exec } from 'child_process';
import { promisify } from 'util';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
import axios from 'axios';
import { Provider, ProviderUsage, RateWindow } from './index';

const execAsync = promisify(exec);

interface ClaudeCredentials {
    accessToken?: string;
    refreshToken?: string;
    expiresAt?: string;
}

interface ClaudeUsageResponse {
    usage?: {
        percent_used?: number;
        tokens_used?: number;
        tokens_limit?: number;
        reset_at?: string;
    };
    weekly_usage?: {
        percent_used?: number;
        reset_at?: string;
    };
    account?: {
        email?: string;
        plan?: string;
    };
}

export class ClaudeProvider implements Provider {
    id = 'claude';
    displayName = 'Claude Code';
    private timeout = 10000;

    async fetch(): Promise<ProviderUsage> {
        try {
            // Try to detect Claude CLI version first
            const version = await this.detectVersion();

            // Try to read credentials
            const credentials = await this.readCredentials();

            if (credentials?.accessToken) {
                // Try OAuth-based fetch
                return await this.fetchWithOAuth(credentials.accessToken, version);
            }

            // No credentials found - require authentication
            return {
                providerId: this.id,
                displayName: this.displayName,
                version,
                error: 'Not authenticated. Run "claude login" to connect your account.',
                updatedAt: new Date().toISOString(),
            };
        } catch (error) {
            throw new Error(
                error instanceof Error ? error.message : 'Failed to fetch Claude usage'
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
            const { stdout } = await execAsync('claude --version', {
                timeout: this.timeout,
            });
            const match = stdout.match(/(\d+\.\d+\.\d+)/);
            return match ? match[1] : 'unknown';
        } catch {
            throw new Error('Claude CLI not found. Install it from https://claude.ai/code');
        }
    }

    private async readCredentials(): Promise<ClaudeCredentials | null> {
        // Windows: %APPDATA%\Claude\credentials.json
        // macOS/Linux: ~/.claude/credentials.json
        const configDir = process.platform === 'win32'
            ? path.join(process.env.APPDATA || '', 'Claude')
            : path.join(os.homedir(), '.claude');

        const credentialsPath = path.join(configDir, 'credentials.json');

        try {
            if (fs.existsSync(credentialsPath)) {
                const content = fs.readFileSync(credentialsPath, 'utf-8');
                return JSON.parse(content);
            }
        } catch {
            // Credentials file doesn't exist or is invalid
        }

        return null;
    }

    private async fetchWithOAuth(accessToken: string, version: string): Promise<ProviderUsage> {
        try {
            const response = await axios.get<ClaudeUsageResponse>('https://api.claude.ai/api/usage', {
                headers: {
                    'Authorization': `Bearer ${accessToken}`,
                    'Content-Type': 'application/json',
                },
                timeout: this.timeout,
            });

            const data = response.data;

            const primary: RateWindow | undefined = data.usage ? {
                usedPercent: data.usage.percent_used || 0,
                resetsAt: data.usage.reset_at,
                resetDescription: 'Session',
            } : undefined;

            const secondary: RateWindow | undefined = data.weekly_usage ? {
                usedPercent: data.weekly_usage.percent_used || 0,
                resetsAt: data.weekly_usage.reset_at,
                resetDescription: 'Weekly',
            } : undefined;

            return {
                providerId: this.id,
                displayName: this.displayName,
                primary,
                secondary,
                accountEmail: data.account?.email,
                accountPlan: data.account?.plan,
                version,
                updatedAt: new Date().toISOString(),
            };
        } catch (error) {
            // OAuth failed, try CLI
            return this.fetchWithCLI(version);
        }
    }

    private async fetchWithCLI(version: string): Promise<ProviderUsage> {
        try {
            // Try to get usage info from Claude CLI
            const { stdout } = await execAsync('claude usage --json', {
                timeout: this.timeout,
            });

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
                updatedAt: new Date().toISOString(),
            };
        } catch {
            // CLI usage command failed, return basic info
            return {
                providerId: this.id,
                displayName: this.displayName,
                version,
                error: 'Could not fetch usage. Run "claude login" to authenticate.',
                updatedAt: new Date().toISOString(),
            };
        }
    }
}
