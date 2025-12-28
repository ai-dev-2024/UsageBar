/**
 * Factory/Droid Provider - Full implementation
 * Uses WorkOS token flows to fetch Factory usage
 */

import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
import axios from 'axios';
import { Provider, ProviderUsage, RateWindow } from './index';

interface FactoryCredentials {
    accessToken?: string;
    refreshToken?: string;
    workosToken?: string;
    email?: string;
}

interface FactoryUsageResponse {
    usage?: {
        current?: {
            used?: number;
            limit?: number;
            percent?: number;
            reset_at?: string;
        };
        billing?: {
            period_end?: string;
            plan?: string;
        };
    };
    user?: {
        email?: string;
        organization?: string;
    };
}

export class FactoryProvider implements Provider {
    id = 'factory';
    displayName = 'Droid (Factory)';
    private timeout = 10000;

    async fetch(): Promise<ProviderUsage> {
        try {
            const credentials = await this.readCredentials();

            if (!credentials?.accessToken && !credentials?.workosToken) {
                throw new Error('Factory credentials not found. Login via Factory app.');
            }

            return await this.fetchUsage(credentials);
        } catch (error) {
            throw new Error(
                error instanceof Error ? error.message : 'Failed to fetch Factory usage'
            );
        }
    }

    async isAvailable(): Promise<boolean> {
        try {
            const credentials = await this.readCredentials();
            return !!(credentials?.accessToken || credentials?.workosToken);
        } catch {
            return false;
        }
    }

    private async readCredentials(): Promise<FactoryCredentials | null> {
        // Factory credential locations
        const credentialPaths = [
            // Windows
            path.join(process.env.APPDATA || '', 'Factory', 'credentials.json'),
            path.join(process.env.APPDATA || '', 'Droid', 'credentials.json'),
            // macOS
            path.join(os.homedir(), 'Library', 'Application Support', 'Factory', 'credentials.json'),
            path.join(os.homedir(), 'Library', 'Application Support', 'Droid', 'credentials.json'),
            // Linux
            path.join(os.homedir(), '.config', 'factory', 'credentials.json'),
            path.join(os.homedir(), '.config', 'droid', 'credentials.json'),
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

    private async fetchUsage(credentials: FactoryCredentials): Promise<ProviderUsage> {
        const token = credentials.accessToken || credentials.workosToken;

        try {
            const response = await axios.get<FactoryUsageResponse>(
                'https://api.factory.dev/v1/usage',
                {
                    headers: {
                        'Authorization': `Bearer ${token}`,
                        'Content-Type': 'application/json',
                    },
                    timeout: this.timeout,
                }
            );

            const data = response.data;
            const usage = data.usage?.current;

            const primary: RateWindow | undefined = usage ? {
                usedPercent: usage.percent || (usage.limit ? (usage.used || 0) / usage.limit * 100 : 0),
                resetsAt: usage.reset_at || data.usage?.billing?.period_end,
                resetDescription: 'Usage',
            } : undefined;

            return {
                providerId: this.id,
                displayName: this.displayName,
                primary,
                accountEmail: credentials.email || data.user?.email,
                accountPlan: data.usage?.billing?.plan,
                version: 'api',
                updatedAt: new Date().toISOString(),
            };
        } catch (error) {
            if (axios.isAxiosError(error) && error.response?.status === 401) {
                return {
                    providerId: this.id,
                    displayName: this.displayName,
                    error: 'Factory session expired. Please login again.',
                    updatedAt: new Date().toISOString(),
                };
            }

            throw error;
        }
    }
}
