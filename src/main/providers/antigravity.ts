/**
 * Antigravity Provider - Windows implementation
 * Detects the Antigravity language server and fetches usage quotas
 */

import { exec } from 'child_process';
import { promisify } from 'util';
import axios from 'axios';
import * as https from 'https';
import { Provider, ProviderUsage, RateWindow } from './index';

const execAsync = promisify(exec);

interface ProcessInfo {
    pid: number;
    csrfToken: string;
    extensionPort?: number;
    commandLine: string;
}

interface ModelQuota {
    label: string;
    modelId: string;
    remainingFraction?: number;
    resetTime?: string;
}

interface UserStatusResponse {
    code?: number | string;
    message?: string;
    userStatus?: {
        email?: string;
        planStatus?: {
            planInfo?: {
                planName?: string;
                planDisplayName?: string;
                displayName?: string;
                productName?: string;
                planShortName?: string;
            };
        };
        cascadeModelConfigData?: {
            clientModelConfigs?: ModelConfig[];
        };
    };
}

interface ModelConfig {
    label: string;
    modelOrAlias: { model: string };
    quotaInfo?: {
        remainingFraction?: number;
        resetTime?: string;
    };
}

export class AntigravityProvider implements Provider {
    id = 'antigravity';
    displayName = 'Antigravity';
    private timeout = 8000;

    async fetch(): Promise<ProviderUsage> {
        try {
            const processInfo = await this.detectProcess();
            const ports = await this.getListeningPorts(processInfo.pid);
            const workingPort = await this.findWorkingPort(ports, processInfo.csrfToken);

            const response = await this.makeRequest(
                workingPort,
                processInfo.csrfToken,
                '/exa.language_server_pb.LanguageServerService/GetUserStatus'
            );

            const usage = this.parseUserStatus(response);
            return usage;
        } catch (error) {
            throw new Error(
                error instanceof Error ? error.message : 'Failed to fetch Antigravity usage'
            );
        }
    }

    async isAvailable(): Promise<boolean> {
        try {
            await this.detectProcess();
            return true;
        } catch {
            return false;
        }
    }

    private async detectProcess(): Promise<ProcessInfo> {
        // Use WMIC to find language_server processes by name
        // This is more reliable than searching by command line pattern
        try {
            const { stdout: wmicOut } = await execAsync(
                'wmic process where "Name like \'%language_server%\'" get ProcessId,CommandLine /format:list',
                { timeout: this.timeout, maxBuffer: 10 * 1024 * 1024 }
            );

            console.log('[Antigravity] WMIC output length:', wmicOut?.length);

            if (!wmicOut || wmicOut.trim() === '') {
                throw new Error('Antigravity/Codeium language server not detected. Launch Windsurf/VS Code and retry.');
            }

            // Parse WMIC output - it's in key=value format
            const entries = wmicOut.split(/\r?\n\r?\n/).filter(block => block.trim());

            for (const entry of entries) {
                const lines = entry.split(/\r?\n/).filter(l => l.trim());
                let commandLine = '';
                let pid = 0;

                for (const line of lines) {
                    if (line.startsWith('CommandLine=')) {
                        commandLine = line.substring('CommandLine='.length);
                    } else if (line.startsWith('ProcessId=')) {
                        pid = parseInt(line.substring('ProcessId='.length), 10);
                    }
                }

                if (!commandLine || !pid) continue;

                console.log('[Antigravity] Found process PID:', pid, 'CommandLine length:', commandLine.length);

                // Extract CSRF token
                const csrfToken = this.extractFlag('--csrf_token', commandLine);
                if (!csrfToken) {
                    console.log('[Antigravity] No CSRF token in process:', pid);
                    continue;
                }

                console.log('[Antigravity] Found valid process:', pid, 'with CSRF token');

                // Extract extension server port
                const extensionPort = this.extractPort('--extension_server_port', commandLine);

                return {
                    pid,
                    csrfToken,
                    extensionPort,
                    commandLine,
                };
            }

            throw new Error('Antigravity/Codeium language server not detected. Launch Windsurf/VS Code and retry.');
        } catch (error) {
            if (error instanceof Error && error.message.includes('not detected')) {
                throw error;
            }
            console.error('[Antigravity] Detection error:', error);
            throw new Error('Failed to detect Antigravity process: ' + (error instanceof Error ? error.message : 'Unknown error'));
        }
    }

    private isAntigravityProcess(commandLine: string): boolean {
        const lower = commandLine.toLowerCase();
        if (lower.includes('--csrf_token')) return true;
        if (lower.includes('language_server')) return true;
        if (lower.includes('codeium')) return true;
        return false;
    }

    private extractFlag(flag: string, commandLine: string): string | undefined {
        // Match --flag=value or --flag value
        const patterns = [
            new RegExp(`${flag}[=\\s]+([^\\s"]+)`, 'i'),
            new RegExp(`${flag}[=\\s]+"([^"]+)"`, 'i'),
        ];

        for (const pattern of patterns) {
            const match = commandLine.match(pattern);
            if (match && match[1]) {
                return match[1];
            }
        }
        return undefined;
    }

    private extractPort(flag: string, commandLine: string): number | undefined {
        const value = this.extractFlag(flag, commandLine);
        return value ? parseInt(value, 10) : undefined;
    }

    private async getListeningPorts(pid: number): Promise<number[]> {
        // Use netstat to find listening ports for the process
        try {
            const { stdout } = await execAsync(
                `netstat -ano | findstr "${pid}" | findstr "LISTENING"`,
                { timeout: this.timeout }
            );

            const ports: Set<number> = new Set();
            const lines = stdout.split('\n');

            for (const line of lines) {
                // Parse netstat output: TCP    127.0.0.1:12345    0.0.0.0:0    LISTENING    12345
                const match = line.match(/:(\d+)\s+[\d.:]+\s+LISTENING/);
                if (match && match[1]) {
                    ports.add(parseInt(match[1], 10));
                }
            }

            if (ports.size === 0) {
                throw new Error('No listening ports found for Antigravity');
            }

            return Array.from(ports).sort((a, b) => a - b);
        } catch (error) {
            throw new Error('Failed to detect Antigravity ports');
        }
    }

    private async findWorkingPort(ports: number[], csrfToken: string): Promise<number> {
        for (const port of ports) {
            try {
                await this.testPort(port, csrfToken);
                return port;
            } catch {
                // Try next port
            }
        }
        throw new Error('No working API port found for Antigravity');
    }

    private async testPort(port: number, csrfToken: string): Promise<void> {
        await this.makeRequest(port, csrfToken, '/exa.language_server_pb.LanguageServerService/GetUnleashData');
    }

    private async makeRequest(port: number, csrfToken: string, path: string): Promise<UserStatusResponse> {
        const url = `https://127.0.0.1:${port}${path}`;

        const body = {
            metadata: {
                ideName: 'antigravity',
                extensionName: 'antigravity',
                ideVersion: 'unknown',
                locale: 'en',
            },
        };

        try {
            const response = await axios.post(url, body, {
                headers: {
                    'Content-Type': 'application/json',
                    'Connect-Protocol-Version': '1',
                    'X-Codeium-Csrf-Token': csrfToken,
                },
                timeout: this.timeout,
                httpsAgent: new https.Agent({
                    rejectUnauthorized: false, // Accept self-signed certs
                }),
            });

            return response.data;
        } catch (error) {
            // Try HTTP fallback
            try {
                const httpUrl = `http://127.0.0.1:${port}${path}`;
                const response = await axios.post(httpUrl, body, {
                    headers: {
                        'Content-Type': 'application/json',
                        'Connect-Protocol-Version': '1',
                        'X-Codeium-Csrf-Token': csrfToken,
                    },
                    timeout: this.timeout,
                });
                return response.data;
            } catch (httpError) {
                throw new Error('Failed to connect to Antigravity API');
            }
        }
    }

    private parseUserStatus(response: UserStatusResponse): ProviderUsage {
        const userStatus = response.userStatus;
        if (!userStatus) {
            throw new Error('Missing userStatus in response');
        }

        const modelConfigs = userStatus.cascadeModelConfigData?.clientModelConfigs || [];
        const quotas: ModelQuota[] = modelConfigs
            .filter((config) => config.quotaInfo)
            .map((config) => ({
                label: config.label,
                modelId: config.modelOrAlias.model,
                remainingFraction: config.quotaInfo?.remainingFraction,
                resetTime: config.quotaInfo?.resetTime,
            }));

        // Select primary models (prioritize Claude, then Gemini Pro, then Flash)
        const selectedQuotas = this.selectModels(quotas);

        const primary = this.quotaToRateWindow(selectedQuotas[0]);
        const secondary = selectedQuotas.length > 1 ? this.quotaToRateWindow(selectedQuotas[1]) : undefined;
        const tertiary = selectedQuotas.length > 2 ? this.quotaToRateWindow(selectedQuotas[2]) : undefined;

        const planInfo = userStatus.planStatus?.planInfo;
        const planName =
            planInfo?.planDisplayName ||
            planInfo?.displayName ||
            planInfo?.productName ||
            planInfo?.planName ||
            planInfo?.planShortName;

        return {
            providerId: this.id,
            displayName: this.displayName,
            primary,
            secondary,
            tertiary,
            accountEmail: userStatus.email,
            accountPlan: planName,
            version: 'running',
            updatedAt: new Date().toISOString(),
            // macOS parity fields
            dashboardUrl: 'https://windsurf.ai/account',
            statusPageUrl: 'https://status.codeium.com',
        };
    }

    private selectModels(quotas: ModelQuota[]): ModelQuota[] {
        const selected: ModelQuota[] = [];

        // Prioritize Claude without thinking
        const claude = quotas.find(
            (q) => q.label.toLowerCase().includes('claude') && !q.label.toLowerCase().includes('thinking')
        );
        if (claude) selected.push(claude);

        // Then Gemini Pro Low
        const proPlow = quotas.find(
            (q) => q.label.toLowerCase().includes('pro') && q.label.toLowerCase().includes('low')
        );
        if (proPlow && !selected.some((s) => s.label === proPlow.label)) {
            selected.push(proPlow);
        }

        // Then Gemini Flash
        const flash = quotas.find(
            (q) => q.label.toLowerCase().includes('gemini') && q.label.toLowerCase().includes('flash')
        );
        if (flash && !selected.some((s) => s.label === flash.label)) {
            selected.push(flash);
        }

        // Fallback: sort by remaining fraction (lowest first) and take top 3
        if (selected.length === 0) {
            return quotas
                .sort((a, b) => (a.remainingFraction || 0) - (b.remainingFraction || 0))
                .slice(0, 3);
        }

        return selected;
    }

    private quotaToRateWindow(quota?: ModelQuota): RateWindow | undefined {
        if (!quota) return undefined;

        const remainingPercent = quota.remainingFraction !== undefined
            ? Math.max(0, Math.min(100, quota.remainingFraction * 100))
            : 0;

        return {
            usedPercent: 100 - remainingPercent,
            resetsAt: quota.resetTime,
            resetDescription: `${quota.label}`,
        };
    }
}
