/**
 * Codex Provider - Full implementation
 * Communicates with OpenAI Codex CLI via RPC
 */

import { exec, spawn } from 'child_process';
import { promisify } from 'util';
import { Provider, ProviderUsage, RateWindow } from './index';

const execAsync = promisify(exec);

interface CodexRPCResponse {
    account?: {
        type: string;
        email?: string;
        planType?: string;
    };
    primary?: {
        usedPercent: number;
        windowDurationMins?: number;
        resetsAt?: number;
    };
    secondary?: {
        usedPercent: number;
        windowDurationMins?: number;
        resetsAt?: number;
    };
    credits?: {
        hasCredits: boolean;
        unlimited: boolean;
        balance?: string;
    };
}

export class CodexProvider implements Provider {
    id = 'codex';
    displayName = 'Codex';
    private timeout = 15000;

    async fetch(): Promise<ProviderUsage> {
        try {
            // Detect Codex CLI version
            const version = await this.detectVersion();

            // Try RPC-based fetch first
            try {
                return await this.fetchWithRPC(version);
            } catch {
                // Fall back to PTY-based parsing
                return await this.fetchWithPTY(version);
            }
        } catch (error) {
            throw new Error(
                error instanceof Error ? error.message : 'Failed to fetch Codex usage'
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
            const { stdout } = await execAsync('codex --version', {
                timeout: this.timeout,
            });
            const match = stdout.match(/(\d+\.\d+\.\d+)/);
            return match ? match[1] : 'unknown';
        } catch {
            throw new Error('Codex CLI not found. Install it from OpenAI.');
        }
    }

    private async fetchWithRPC(version: string): Promise<ProviderUsage> {
        return new Promise((resolve, reject) => {
            const process = spawn('codex', ['-s', 'read-only', '-a', 'untrusted', 'app-server'], {
                stdio: ['pipe', 'pipe', 'pipe'],
            });

            let stdout = '';
            let stderr = '';
            let resolved = false;

            const timeout = setTimeout(() => {
                if (!resolved) {
                    resolved = true;
                    process.kill();
                    reject(new Error('Codex RPC timed out'));
                }
            }, this.timeout);

            process.stdout.on('data', (data) => {
                stdout += data.toString();

                // Try to parse JSON-RPC response
                try {
                    const lines = stdout.split('\n');
                    for (const line of lines) {
                        if (line.trim().startsWith('{')) {
                            const response: CodexRPCResponse = JSON.parse(line);
                            if (!resolved) {
                                resolved = true;
                                clearTimeout(timeout);
                                process.kill();
                                resolve(this.parseRPCResponse(response, version));
                            }
                        }
                    }
                } catch {
                    // Keep waiting for more data
                }
            });

            process.stderr.on('data', (data) => {
                stderr += data.toString();
            });

            process.on('close', () => {
                if (!resolved) {
                    resolved = true;
                    clearTimeout(timeout);
                    reject(new Error('Codex RPC closed without response'));
                }
            });

            process.on('error', (err) => {
                if (!resolved) {
                    resolved = true;
                    clearTimeout(timeout);
                    reject(err);
                }
            });

            // Send RPC request
            const request = JSON.stringify({
                jsonrpc: '2.0',
                id: 1,
                method: 'getUsage',
                params: {},
            });
            process.stdin.write(request + '\n');
        });
    }

    private parseRPCResponse(response: CodexRPCResponse, version: string): ProviderUsage {
        const primary: RateWindow | undefined = response.primary ? {
            usedPercent: response.primary.usedPercent,
            windowMinutes: response.primary.windowDurationMins,
            resetsAt: response.primary.resetsAt
                ? new Date(response.primary.resetsAt * 1000).toISOString()
                : undefined,
            resetDescription: 'Session',
        } : undefined;

        const secondary: RateWindow | undefined = response.secondary ? {
            usedPercent: response.secondary.usedPercent,
            windowMinutes: response.secondary.windowDurationMins,
            resetsAt: response.secondary.resetsAt
                ? new Date(response.secondary.resetsAt * 1000).toISOString()
                : undefined,
            resetDescription: 'Weekly',
        } : undefined;

        return {
            providerId: this.id,
            displayName: this.displayName,
            primary,
            secondary,
            accountEmail: response.account?.email,
            accountPlan: response.account?.planType,
            version,
            updatedAt: new Date().toISOString(),
            // macOS parity fields
            credits: response.credits ? {
                balance: response.credits.balance || '0',
                unlimited: response.credits.unlimited,
            } : undefined,
            dashboardUrl: 'https://platform.openai.com/usage',
            statusPageUrl: 'https://status.openai.com',
        };
    }

    private async fetchWithPTY(version: string): Promise<ProviderUsage> {
        try {
            // Try to run codex status command
            const { stdout } = await execAsync('codex status', {
                timeout: this.timeout,
            });

            // Parse text output
            const sessionMatch = stdout.match(/session:\s*(\d+)%/i);
            const weeklyMatch = stdout.match(/weekly:\s*(\d+)%/i);
            const emailMatch = stdout.match(/email:\s*(\S+)/i);

            const primary: RateWindow | undefined = sessionMatch ? {
                usedPercent: parseInt(sessionMatch[1], 10),
                resetDescription: 'Session',
            } : undefined;

            const secondary: RateWindow | undefined = weeklyMatch ? {
                usedPercent: parseInt(weeklyMatch[1], 10),
                resetDescription: 'Weekly',
            } : undefined;

            return {
                providerId: this.id,
                displayName: this.displayName,
                primary,
                secondary,
                accountEmail: emailMatch ? emailMatch[1] : undefined,
                version,
                updatedAt: new Date().toISOString(),
            };
        } catch {
            return {
                providerId: this.id,
                displayName: this.displayName,
                version,
                error: 'Could not fetch usage. Run "codex login" to authenticate.',
                updatedAt: new Date().toISOString(),
            };
        }
    }
}
