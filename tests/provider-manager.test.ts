import { describe, it, expect, vi } from 'vitest';
import { ProviderManager, type Provider } from '../src/main/providers';

vi.mock('electron', () => ({
    app: {
        getPath: () => '/tmp',
    },
}));

function createManager(enabledProviders: string[] = ['test']) {
    const fakeSettings = {
        getEnabledProviders: () => enabledProviders,
    } as any;

    return new ProviderManager(fakeSettings);
}

function createProvider(id: string, fetchImpl: () => Promise<any>): Provider {
    return {
        id,
        displayName: `Provider ${id}`,
        fetch: fetchImpl,
        isAvailable: async () => true,
    };
}

describe('ProviderManager', () => {
    it('refreshAll stores successful provider usage', async () => {
        const manager = createManager(['test']);
        const provider = createProvider('test', async () => ({
            providerId: 'test',
            displayName: 'Provider test',
            primary: { usedPercent: 25 },
            updatedAt: new Date().toISOString(),
        }));

        (manager as any).providers = new Map([['test', provider]]);

        await manager.refreshAll();

        const usage = manager.getProviderUsage('test');
        expect(usage?.providerId).toBe('test');
        expect(usage?.primary?.usedPercent).toBe(25);
    });

    it('refreshAll stores provider errors as usage entries', async () => {
        const manager = createManager(['broken']);
        const provider = createProvider('broken', async () => {
            throw new Error('boom');
        });

        (manager as any).providers = new Map([['broken', provider]]);

        await manager.refreshAll();

        const usage = manager.getProviderUsage('broken');
        expect(usage?.providerId).toBe('broken');
        expect(usage?.error).toContain('boom');
    });

    it('refreshProvider returns null for unknown provider', async () => {
        const manager = createManager([]);
        (manager as any).providers = new Map();

        const result = await manager.refreshProvider('missing');
        expect(result).toBeNull();
    });

    it('clearCache removes cached usage', async () => {
        const manager = createManager(['test']);
        const provider = createProvider('test', async () => ({
            providerId: 'test',
            displayName: 'Provider test',
            primary: { usedPercent: 10 },
            updatedAt: new Date().toISOString(),
        }));

        (manager as any).providers = new Map([['test', provider]]);

        await manager.refreshAll();
        expect(manager.getProviderUsage('test')).toBeTruthy();

        manager.clearCache();
        expect(manager.getProviderUsage('test')).toBeUndefined();
    });
});
